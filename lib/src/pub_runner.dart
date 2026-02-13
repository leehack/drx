import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'cache_paths.dart';
import 'errors.dart';
import 'lock.dart';
import 'models.dart';
import 'platform_info.dart';
import 'process_executor.dart';

/// Executes tools from pub.dev packages.
final class PubRunner {
  PubRunner({
    required this.paths,
    required this.platform,
    required this.processExecutor,
  });

  final DrxPaths paths;
  final HostPlatform platform;
  final ProcessExecutor processExecutor;

  /// Resolves package dependencies and executes the requested command.
  Future<int> execute(CommandRequest request) async {
    final package = request.source.identifier;
    final versionKey = request.source.version ?? 'latest';
    final lock = paths.lockFileFor('pub:$package:$versionKey');

    _log(
      request.verbose,
      'source=pub package=$package version=$versionKey runtime=${request.runtime.name}',
    );

    return withFileLock(lock, () async {
      if (request.isolated) {
        final isolatedSandbox = await Directory.systemTemp.createTemp(
          'drx_pub_',
        );
        _log(request.verbose, 'using isolated sandbox ${isolatedSandbox.path}');
        try {
          return _executeInSandbox(request, isolatedSandbox);
        } finally {
          await isolatedSandbox.delete(recursive: true);
        }
      }

      final sandbox = paths.pubSandboxDir(package, versionKey);
      if (request.refresh && await sandbox.exists()) {
        _log(request.verbose, 'refresh requested, clearing ${sandbox.path}');
        await sandbox.delete(recursive: true);
      }
      await sandbox.create(recursive: true);
      _log(request.verbose, 'using sandbox ${sandbox.path}');
      return _executeInSandbox(request, sandbox);
    });
  }

  Future<int> _executeInSandbox(
    CommandRequest request,
    Directory sandbox,
  ) async {
    await _writePubspec(
      sandbox,
      package: request.source.identifier,
      version: request.source.version,
    );

    final pubGetCode = await processExecutor.run(
      'dart',
      const ['pub', 'get'],
      workingDirectory: sandbox.path,
      runInShell: platform.isWindows,
    );
    if (pubGetCode != 0) {
      throw DrxException(
        'Failed to resolve pub package "${request.source.identifier}" dependencies.',
      );
    }

    switch (request.runtime) {
      case RuntimeMode.jit:
        return _runJit(request, sandbox);
      case RuntimeMode.aot:
        final binary = await _ensureAotBinary(
          request,
          sandbox,
          allowFallback: false,
        );
        if (binary == null) {
          throw const DrxException('AOT compile did not produce a binary.');
        }
        return _runCompiled(binary, request.args);
      case RuntimeMode.auto:
        final binary = await _ensureAotBinary(
          request,
          sandbox,
          allowFallback: true,
        );
        if (binary != null) {
          return _runCompiled(binary, request.args);
        }
        return _runJit(request, sandbox);
    }
  }

  Future<int> _runJit(CommandRequest request, Directory sandbox) {
    return processExecutor.run(
      'dart',
      [
        'run',
        '${request.source.identifier}:${request.command}',
        ...request.args,
      ],
      workingDirectory: sandbox.path,
      runInShell: platform.isWindows,
    );
  }

  Future<int> _runCompiled(String binaryPath, List<String> args) {
    return processExecutor.run(
      binaryPath,
      args,
      runInShell: platform.isWindows && _isShellScript(binaryPath),
    );
  }

  /// Builds (or reuses) an AOT binary for a pub executable.
  Future<String?> _ensureAotBinary(
    CommandRequest request,
    Directory sandbox, {
    required bool allowFallback,
  }) async {
    final package = request.source.identifier;
    final versionKey = request.source.version ?? 'latest';
    final sdkVersion = Platform.version.split(' ').first;
    final aotDir = request.isolated
        ? await Directory.systemTemp.createTemp('drx_aot_')
        : paths.pubAotDir(
            package,
            versionKey,
            request.command,
            platform,
            sdkVersion,
          );

    if (request.refresh && await aotDir.exists() && !request.isolated) {
      await aotDir.delete(recursive: true);
    }
    await aotDir.create(recursive: true);

    final binaryName = platform.isWindows
        ? '${request.command}.exe'
        : request.command;
    final binaryFile = File(p.join(aotDir.path, binaryName));

    final entrypoint = await _resolveEntrypoint(
      sandbox,
      package: package,
      command: request.command,
    );

    if (await _usesCliLauncher(entrypoint)) {
      if (allowFallback) {
        _log(
          request.verbose,
          'entrypoint uses cli_launcher, skipping AOT and falling back to JIT',
        );
        return null;
      }
      throw DrxException(
        'AOT is not supported for ${request.source.identifier}:${request.command} '
        'because its executable uses package:cli_launcher. Use --runtime jit.',
      );
    }

    if (!request.refresh && await binaryFile.exists()) {
      _log(request.verbose, 'reusing cached AOT binary ${binaryFile.path}');
      return binaryFile.path;
    }

    _log(request.verbose, 'compiling AOT binary ${binaryFile.path}');
    final compileCode = await processExecutor.run(
      'dart',
      [
        'compile',
        'exe',
        '--packages',
        p.join(sandbox.path, _packageConfigRelativePath),
        '--output',
        binaryFile.path,
        entrypoint,
      ],
      workingDirectory: sandbox.path,
      runInShell: platform.isWindows,
    );

    if (compileCode != 0) {
      if (allowFallback) {
        _log(request.verbose, 'AOT compile failed, falling back to JIT');
        return null;
      }
      throw DrxException(
        'AOT compile failed for ${request.source.identifier}:${request.command}.',
      );
    }

    return binaryFile.path;
  }

  Future<void> _writePubspec(
    Directory sandbox, {
    required String package,
    required String? version,
  }) async {
    final value = version ?? 'any';
    final pubspec = File(p.join(sandbox.path, 'pubspec.yaml'));
    final content = StringBuffer()
      ..writeln('name: drx_sandbox')
      ..writeln('environment:')
      ..writeln("  sdk: '>=3.0.0 <4.0.0'")
      ..writeln('dependencies:')
      ..writeln('  $package: "$value"');
    await pubspec.writeAsString(content.toString());
  }

  Future<String> _resolveEntrypoint(
    Directory sandbox, {
    required String package,
    required String command,
  }) async {
    final packageConfig = File(
      p.join(sandbox.path, _packageConfigRelativePath),
    );
    if (!await packageConfig.exists()) {
      throw const DrxException(
        'Missing package config after pub get. Cannot compile AOT.',
      );
    }

    final decoded = jsonDecode(await packageConfig.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const DrxException(
        'Invalid .dart_tool/package_config.json format.',
      );
    }

    final packages = decoded['packages'];
    if (packages is! List) {
      throw const DrxException('Invalid package list in package_config.json.');
    }

    String? rootPath;
    for (final node in packages) {
      if (node is! Map<String, dynamic>) {
        continue;
      }
      if (node['name'] == package) {
        final rootUriRaw = node['rootUri'];
        if (rootUriRaw is! String) {
          break;
        }
        var rootUri = Uri.parse(rootUriRaw);
        if (!rootUri.isAbsolute) {
          rootUri = packageConfig.uri.resolve(rootUriRaw);
        }
        rootPath = p.normalize(p.fromUri(rootUri));
        break;
      }
    }

    if (rootPath == null) {
      throw DrxException('Package "$package" not found in package config.');
    }

    final executableScript = await _resolveExecutableScript(
      rootPath,
      command: command,
    );
    final entrypoint = File(p.join(rootPath, 'bin', '$executableScript.dart'));
    if (!await entrypoint.exists()) {
      final availableExecutables = await _readExecutableNames(rootPath);
      final hint = availableExecutables.isEmpty
          ? ''
          : ' Available executables: ${availableExecutables.join(', ')}.';
      throw DrxException(
        'Executable "$command" not found in package "$package".$hint',
      );
    }
    return entrypoint.path;
  }

  Future<List<String>> _readExecutableNames(String packageRoot) async {
    final names = <String>{};

    final pubspec = await _loadPubspec(packageRoot);
    if (pubspec != null) {
      final executablesNode = pubspec['executables'];
      if (executablesNode is YamlMap) {
        for (final key in executablesNode.keys) {
          final name = key.toString();
          if (name.isNotEmpty) {
            names.add(name);
          }
        }
      }
    }

    final binDir = Directory(p.join(packageRoot, 'bin'));
    if (await binDir.exists()) {
      await for (final entity in binDir.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final fileName = p.basename(entity.path);
        if (!fileName.endsWith('.dart')) {
          continue;
        }
        final script = p.basenameWithoutExtension(fileName);
        if (script.isNotEmpty) {
          names.add(script);
        }
      }
    }

    final result = names.toList(growable: false)..sort();
    return result;
  }

  Future<String> _resolveExecutableScript(
    String packageRoot, {
    required String command,
  }) async {
    final pubspecNode = await _loadPubspec(packageRoot);
    if (pubspecNode == null) {
      return command;
    }

    final executablesNode = pubspecNode['executables'];
    if (executablesNode is! YamlMap) {
      return command;
    }

    if (!executablesNode.containsKey(command)) {
      return command;
    }

    final rawValue = executablesNode[command];
    if (rawValue == null) {
      return command;
    }

    final value = rawValue.toString().trim();
    return value.isEmpty ? command : value;
  }

  bool _isShellScript(String binaryPath) {
    final lower = binaryPath.toLowerCase();
    return lower.endsWith('.cmd') || lower.endsWith('.bat');
  }

  Future<YamlMap?> _loadPubspec(String packageRoot) async {
    final pubspecFile = File(p.join(packageRoot, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) {
      return null;
    }

    final pubspecNode = loadYaml(await pubspecFile.readAsString());
    if (pubspecNode is! YamlMap) {
      return null;
    }
    return pubspecNode;
  }

  /// Detects wrappers that require global activation and break under AOT.
  Future<bool> _usesCliLauncher(String entrypoint) async {
    final file = File(entrypoint);
    if (!await file.exists()) {
      return false;
    }

    final content = await file.readAsString();
    return content.contains("package:cli_launcher/cli_launcher.dart") ||
        content.contains('launchExecutable(');
  }

  void _log(bool enabled, String message) {
    if (!enabled) {
      return;
    }
    stderr.writeln('[drx:pub] $message');
  }
}

const _packageConfigRelativePath = '.dart_tool/package_config.json';
