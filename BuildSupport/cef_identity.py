"""Bind a product build directory to immutable CEF inputs; never replace inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for entry in sorted(root.rglob('*')):
        relative = entry.relative_to(root).as_posix()
        if entry.is_symlink():
            record = ['link', relative, str(entry.readlink())]
        elif entry.is_file():
            content = hashlib.sha256()
            with entry.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    content.update(chunk)
            record = ['file', relative, content.hexdigest()]
        else:
            continue
        digest.update(json.dumps(record, ensure_ascii=True).encode() + b'\n')
    return digest.hexdigest()


def identity(root: Path) -> dict:
    root = root.resolve(strict=True)
    header = (root / 'include/cef_version.h').read_text()
    version = re.search(r'^#define CEF_VERSION "([^"]+)"', header, re.MULTILINE)
    if not version:
        raise ValueError('CEF_VERSION missing')
    parts = ['include', 'libcef_dll', 'cmake', 'Release/Chromium Embedded Framework.framework']
    for name in parts:
        if not (root / name).is_dir():
            raise ValueError(f'Missing CEF input: {name}')
    return {'schema': 1, 'root': str(root), 'version': version[1],
            'sha256': {name: tree_digest(root / name) for name in parts}}


def require_lock(root: Path, lock: Path) -> dict:
    actual = identity(root)
    if json.loads(lock.read_text()) != actual:
        raise ValueError('CEF inputs changed. Preserve this build and use a new build directory.')
    return actual


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cef-root', type=Path, required=True)
    parser.add_argument('--lock', type=Path, required=True)
    args = parser.parse_args()
    if args.lock.exists():
        require_lock(args.cef_root, args.lock)
    else:
        result = identity(args.cef_root)
        with args.lock.open('x') as stream:
            json.dump(result, stream, indent=2)
            stream.write('\n')


if __name__ == '__main__':
    main()
