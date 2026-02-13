import 'dart:convert';

import 'package:drx/src/errors.dart';
import 'package:drx/src/version_lister.dart';
import 'package:test/test.dart';

import 'test_fakes.dart';

void main() {
  group('VersionLister', () {
    test('lists pub versions newest first with limit', () async {
      final fetcher = FakeByteFetcher({
        'https://pub.dev/api/packages/melos': utf8.encode(
          jsonEncode({
            'name': 'melos',
            'versions': [
              {'version': '1.0.0'},
              {'version': '1.1.0'},
              {'version': '2.0.0'},
            ],
          }),
        ),
      });

      final lister = VersionLister(
        fetcher: fetcher,
        gitHubApi: FakeGitHubApi(releaseTagList: const ['v2.0.0', 'v1.0.0']),
      );
      final versions = await lister.listVersions('melos', limit: 2);

      expect(versions, ['2.0.0', '1.1.0']);
    });

    test('parses pub target variants', () async {
      final fetcher = FakeByteFetcher({
        'https://pub.dev/api/packages/mason_cli': utf8.encode(
          jsonEncode({
            'versions': [
              {'version': '0.1.0'},
            ],
          }),
        ),
      });

      final lister = VersionLister(
        fetcher: fetcher,
        gitHubApi: FakeGitHubApi(releaseTagList: const ['v1']),
      );

      expect(await lister.listVersions('pub:mason_cli'), ['0.1.0']);
      expect(await lister.listVersions('mason_cli:mason'), ['0.1.0']);
      expect(await lister.listVersions('mason_cli:mason@0.1.0'), ['0.1.0']);
    });

    test('lists gh release tags', () async {
      final lister = VersionLister(
        fetcher: FakeByteFetcher(const {}),
        gitHubApi: FakeGitHubApi(
          releaseTagList: const ['v3.0.0', 'v2.5.0', 'v2.0.0'],
        ),
      );

      final versions = await lister.listVersions('gh:cli/cli', limit: 2);
      expect(versions, ['v3.0.0', 'v2.5.0']);
    });

    test('throws on invalid gh target', () async {
      final lister = VersionLister(
        fetcher: FakeByteFetcher(const {}),
        gitHubApi: FakeGitHubApi(releaseTagList: const ['v1']),
      );

      expect(
        () => lister.listVersions('gh:invalid-target'),
        throwsA(isA<DrxException>()),
      );
    });

    test('falls back to repository tags when releases are empty', () async {
      final lister = VersionLister(
        fetcher: FakeByteFetcher(const {}),
        gitHubApi: FakeGitHubApi(
          releaseTagList: const [],
          repositoryTagList: const ['v0.3.0', 'v0.2.0'],
        ),
      );

      final versions = await lister.listVersions('gh:org/repo');
      expect(versions, ['v0.3.0', 'v0.2.0']);
    });
  });
}
