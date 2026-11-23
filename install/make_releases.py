#!/usr/bin/env python3
"""Writes install/releases.json for a build published as a GitHub Release.

Builds are published as GitHub Releases (tag v<version>; see
install/publish_release.sh), not committed. Portals on 2026.12.14 or newer
read the releases straight from GitHub's API. Older builds read this file
from the branch, so it names the newest release's APK on GitHub.

Usage:  python3 install/make_releases.py 2026.12.14 "What changed" [apk]
"""
import json
import os
import sys

REPO = 'rayalavcp/phoenix-portal'
HERE = os.path.dirname(os.path.abspath(__file__))


def asset_name(version):
    # The app picks the APK by this name (see release_apk.dart): the
    # armeabi-v7a split, which every Portal runs.
    return f'kiosk-satellite-{version}.armeabi-v7a.apk'


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    version = sys.argv[1].lstrip('v')
    notes = sys.argv[2] if len(sys.argv) > 2 else ''
    apk = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, 'phoenix-portal.apk')
    size = os.path.getsize(apk)
    tag = f'v{version}'
    release = {
        'tag_name': tag,
        'name': f'Phoenix Portal {version}',
        'draft': False,
        'prerelease': False,
        'body': notes,
        'html_url': f'https://github.com/{REPO}/releases/tag/{tag}',
        'assets': [
            {
                'name': asset_name(version),
                'browser_download_url': f'https://github.com/{REPO}/releases/download/{tag}/{asset_name(version)}',
                'size': size,
                'state': 'uploaded',
            }
        ],
    }
    with open(os.path.join(HERE, 'releases.json'), 'w') as f:
        json.dump([release], f, indent=2)
        f.write('\n')
    print(f'releases.json: {version}, {size} bytes')


if __name__ == '__main__':
    main()
