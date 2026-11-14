"""Build pinned CEF in a new workspace. Does not launch the resulting app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timezone


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--automate', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    recipe = json.loads((root / 'Configuration/cef/macos-arm64-codecs.json').read_text())
    automate = args.automate.resolve(strict=True)
    work = args.work.resolve()
    if shutil.disk_usage(work.parent).free < 200 * 1024**3:
        raise SystemExit('At least 200 GiB free space is required before starting this build.')
    work.mkdir(exist_ok=False)
    script = work / 'automate-git.py'
    shutil.copy2(automate, script)
    env = os.environ.copy()
    gn = dict(recipe['gn_defines'])
    gn.update(symbol_level=0, is_component_build=False)
    env['GN_DEFINES'] = ' '.join(f'{key}={json.dumps(value)}' for key, value in gn.items())
    env['SSL_CERT_FILE'] = '/etc/ssl/cert.pem'
    env['PYTHONUNBUFFERED'] = '1'
    command = [sys.executable, str(script), '--download-dir=' + str(work / 'source'),
               '--branch=' + recipe['branch'], '--checkout=' + recipe['cef_commit'],
               '--chromium-checkout=' + recipe['chromium_checkout'], '--arm64-build',
               '--no-debug-build', '--build-target=cefclient -j 3',
               '--minimal-distrib-only', '--no-distrib-archive', '--build-log-file']
    record = {'started_at': datetime.now(timezone.utc).isoformat(), 'recipe': recipe,
              'gn_defines': env['GN_DEFINES'], 'command': command,
              'automate_sha256': hashlib.sha256(script.read_bytes()).hexdigest(),
              'status': 'running'}
    status = work / 'build-status.json'
    status.write_text(json.dumps(record, indent=2) + '\n')
    with (work / 'build.log').open('x') as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        record['pid'] = process.pid
        status.write_text(json.dumps(record, indent=2) + '\n')
        result = process.wait()
    record.update(status='completed' if result == 0 else 'failed', exit_code=result,
                  finished_at=datetime.now(timezone.utc).isoformat())
    status.write_text(json.dumps(record, indent=2) + '\n')
    raise SystemExit(result)


if __name__ == '__main__':
    main()
