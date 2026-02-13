import 'dart:convert';

import 'package:drx/src/github_api.dart';
import 'package:test/test.dart';

import 'test_fakes.dart';

void main() {
  test('decodes release payload from GitHub API', () async {
    final payload = {
      'tag_name': 'v1.0.0',
      'prerelease': false,
      'assets': [
        {
          'name': 'tool-linux-x64.tar.gz',
          'browser_download_url': 'https://example/tool.tgz',
        },
      ],
    };

    final fetcher = FakeByteFetcher({
      'https://api.github.com/repos/org/repo/releases/latest': utf8.encode(
        jsonEncode(payload),
      ),
    });

    final api = HttpGitHubApi(fetcher: fetcher);
    final release = await api.latestRelease('org', 'repo');

    expect(release.tag, 'v1.0.0');
    expect(release.assets, hasLength(1));
    expect(release.assets.single.name, 'tool-linux-x64.tar.gz');
  });

  test('decodes release tags list from GitHub API', () async {
    final fetcher = FakeByteFetcher({
      'https://api.github.com/repos/org/repo/releases?per_page=2': utf8.encode(
        jsonEncode([
          {'tag_name': 'v2.0.0'},
          {'tag_name': 'v1.0.0'},
        ]),
      ),
    });

    final api = HttpGitHubApi(fetcher: fetcher);
    final tags = await api.releaseTags('org', 'repo', limit: 2);

    expect(tags, ['v2.0.0', 'v1.0.0']);
  });

  test('decodes repository tags list from GitHub API', () async {
    final fetcher = FakeByteFetcher({
      'https://api.github.com/repos/org/repo/tags?per_page=2': utf8.encode(
        jsonEncode([
          {'name': 'v0.3.0'},
          {'name': 'v0.2.0'},
        ]),
      ),
    });

    final api = HttpGitHubApi(fetcher: fetcher);
    final tags = await api.repositoryTags('org', 'repo', limit: 2);

    expect(tags, ['v0.3.0', 'v0.2.0']);
  });
}
