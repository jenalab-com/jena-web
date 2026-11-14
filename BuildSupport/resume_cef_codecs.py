"""Resume the existing pinned checkout without a broad source-history fetch."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from datetime import datetime, timezone


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--checkout-pid', type=int)
    args = parser.parse_args()
    work = args.work.resolve(strict=True)
    old = json.loads((work / 'build-status.json').read_text())
    if old['status'] != 'stopped_for_recovery':
        raise SystemExit('Expected an explicitly stopped build.')
    recipe = old['recipe']
    source = work / 'source'
    chromium = source / 'chromium'
    def head(path):
        return subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
    env = os.environ.copy()
    env.update(PATH=str(source / 'depot_tools') + os.pathsep + env['PATH'],
               DEPOT_TOOLS_UPDATE='0', SSL_CERT_FILE='/etc/ssl/cert.pem',
               GN_DEFINES=old['gn_defines'], PYTHONUNBUFFERED='1')
    commands = [
        ('dependencies', ['gclient', 'sync', '--nohooks', '--no-history', '--jobs=3',
                          '--revision=src@' + recipe['chromium_commit']], chromium),
        ('hooks', ['gclient', 'runhooks'], chromium),
        ('compile_and_package', [sys.executable, str(work / 'automate-git.py'),
            '--download-dir=' + str(source), '--branch=' + recipe['branch'],
            '--checkout=' + recipe['cef_commit'], '--chromium-checkout=' + recipe['chromium_checkout'],
            '--no-update', '--force-build', '--arm64-build', '--no-debug-build',
            '--build-target=cefclient -j 3', '--minimal-distrib-only', '--no-distrib-archive',
            '--build-log-file'], work)]
    state = {'status': 'running', 'started_at': datetime.now(timezone.utc).isoformat(),
             'recipe': recipe, 'gn_defines': old['gn_defines']}
    status = work / 'recovery-status.json'
    with status.open('x') as stream:
        json.dump(state, stream, indent=2)
    def record():
        state['heartbeat_at'] = datetime.now(timezone.utc).isoformat()
        status.write_text(json.dumps(state, indent=2) + '\n')
    if args.checkout_pid:
        state.update(stage='checkout', pid=args.checkout_pid, log=str(work / 'recovery-checkout.log'))
        while True:
            task = subprocess.run(['ps', '-p', str(args.checkout_pid), '-o', 'args='], capture_output=True, text=True)
            if task.returncode != 0:
                break
            if 'checkout --detach ' + recipe['chromium_commit'] not in task.stdout:
                state.update(status='failed', reason='Checkout PID changed; refusing to continue')
                record()
                raise SystemExit(state['reason'])
            record()
            time.sleep(30)
        if 'HEAD is now at' not in (work / 'recovery-checkout.log').read_text(errors='replace'):
            state.update(status='failed', reason='Checkout did not report completion')
            record()
            raise SystemExit(state['reason'])
    for path, expected in [(chromium / 'src', recipe['chromium_commit']),
                           (source / 'cef', recipe['cef_commit']),
                           (source / 'depot_tools', recipe['depot_tools_checkout'])]:
        if head(path) != expected:
            raise SystemExit(f'Unexpected revision at {path}')
    for stage, command, cwd in commands:
        logpath = work / ('recovery-' + stage + '.log')
        state.update(stage=stage, command=command, log=str(logpath))
        with logpath.open('x') as log:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
            state['pid'] = process.pid
            while True:
                record()
                try:
                    result = process.wait(timeout=30)
                    break
                except subprocess.TimeoutExpired:
                    stat = logpath.stat()
                    state['log_bytes'] = stat.st_size
                    state['log_silent_seconds'] = round(time.time() - stat.st_mtime)
            if result:
                state.update(status='failed', exit_code=result)
                record()
                raise SystemExit(result)
    state.update(status='completed', exit_code=0)
    record()


if __name__ == '__main__':
    main()
