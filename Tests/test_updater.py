#!/usr/bin/env python3
"""Exercise updater validation and rollback with isolated, locally signed bundles."""
from pathlib import Path
import argparse
import struct
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--release-archive', type=Path)
args = parser.parse_args()
executable = root / 'TD Capture.app/Contents/MacOS/TDCapture'
if not executable.is_file():
    raise SystemExit('Build TD Capture with ./build.sh first.')
with tempfile.TemporaryDirectory(prefix='td-capture-updater-check-') as temporary:
    folder = Path(temporary)
    for name, entry in [('good', 'TD Capture.app/Contents/Info.plist'), ('traversal', '../escape')]:
        with zipfile.ZipFile(folder / (name + '.zip'), 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(entry, b'test')
    with zipfile.ZipFile(folder / 'symlink.zip', 'w') as archive:
        entry = zipfile.ZipInfo('TD Capture.app/Contents/link')
        entry.create_system = 3
        entry.external_attr = 0o120777 << 16
        archive.writestr(entry, b'/tmp')
    data = bytearray((folder / 'good.zip').read_bytes())
    length = struct.unpack_from('<H', data, 26)[0]
    data[30:30 + length] = b'X' * length
    (folder / 'local-mismatch.zip').write_bytes(data)
    runner = folder / 'update-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-target', 'arm64-apple-macosx15.0',
                    '-module-cache-path', '/tmp/TDCapture-update-module-cache',
                    str(root / 'Sources/UpdateCore.swift'), str(root / 'Sources/UpdateInstaller.swift'),
                    str(root / 'Tests/UpdateTests.swift'), '-o', str(runner)], check=True)
    command = [str(runner), str(folder), str(executable)]
    if args.release_archive:
        command.append(str(args.release_archive.resolve()))
    subprocess.run(command, check=True)
