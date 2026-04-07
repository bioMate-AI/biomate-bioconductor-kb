"""Download AiZynthFinder public models into /opt/aizynthfinder/models at image build time."""
import os
import sys

dest = '/opt/aizynthfinder/models'
os.makedirs(dest, exist_ok=True)

try:
    # aizynthfinder >= 4.2 provides download_public_data
    from aizynthfinder.tools.download_public_data import download_public_data
    download_public_data(dest)
    print(f'AiZynthFinder models downloaded to {dest}')
    files = os.listdir(dest)
    print(f'Files: {files}')
except ImportError:
    # Older API: try the CLI entry point
    import subprocess
    r = subprocess.run(
        ['aizynthcli', '--download-public-data', dest],
        capture_output=True, text=True
    )
    if r.returncode == 0:
        print('AiZynthFinder models downloaded via CLI')
    else:
        print(f'WARNING: model download failed: {r.stderr}')
        print('Template-based expansion will be used instead.')
except Exception as e:
    print(f'WARNING: model download failed: {e}')
    print('Template-based expansion will be used instead.')
