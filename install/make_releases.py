#!/usr/bin/env python3
"""Writes install/releases.json for the APK in install/phoenix-portal.apk.

The Portal's "Check for updates" (Update source: GitHub Repository) reads
this file from the repository and offers the APK it names when its version
is newer than the one installed. The file has the shape of GitHub's own
releases list, which the app already understands.

Usage:  python3 install/make_releases.py 2026.12.3 "What changed in this build"
"""
import json
import os
import sys

BRANCH = 'claude/fervent-hopper-25a7jk'
REPO = 'rayalavcp/phoenix-portal'
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    version = sys.argv[1].lstrip('v')
    notes = sys.argv[2] if len(sys.argv) > 2 else ''
    apk = os.path.join(HERE, 'phoenix-portal.apk')
    size = os.path.getsize(apk)
    release = {
        'tag_name': version,
        'name': f'Phoenix Portal {version}',
        'draft': False,
        'prerelease': False,
        'body': notes,
        'html_url': f'https://github.com/{REPO}/tree/{BRANCH}/install',
        'assets': [
            {
                # The app picks the APK by this name (see release_apk.dart).
                'name': f'kiosk-satellite-{version}.apk',
                'browser_download_url': f'https://github.com/{REPO}/raw/{BRANCH}/install/phoenix-portal.apk',
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
