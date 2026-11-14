"""Generate a separate codec build recipe. No downloads, builds or replacements."""
import argparse
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    recipe_file = Path(__file__).resolve().parents[1] / 'Configuration/cef/macos-arm64-codecs.json'
    recipe = json.loads(recipe_file.read_text())
    # Never reuse a directory that may contain source, profiles or previous output.
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'recipe.json').write_text(json.dumps(recipe, indent=2) + '\n')
    gn = ' '.join(f'{key}={json.dumps(value)}' for key, value in recipe['gn_defines'].items())
    (args.output / 'environment.sh').write_text('export GN_DEFINES=' + shlex.quote(gn) + '\n')
    host = {'python': sys.version.split()[0], 'free_bytes': shutil.disk_usage(args.output).free,
            'downloads_started': False, 'build_started': False}
    if sys.platform == 'darwin':
        host['memory_bytes'] = int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True))
        host['xcode'] = subprocess.check_output(['xcodebuild', '-version'], text=True).strip()
    (args.output / 'host.json').write_text(json.dumps(host, indent=2) + '\n')
    print(f'Recipe prepared at {args.output}. CEF source acquisition and compilation have not started.')


if __name__ == '__main__':
    main()
