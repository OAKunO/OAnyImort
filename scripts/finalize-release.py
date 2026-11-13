"""Update documentation and source metadata for the verified distribution."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def command(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def api(path, method=None, payload=None):
    args = ['gh', 'api', path]
    if method:
        args += ['--method', method]
    if payload is not None:
        args += ['--input', '-']
    result = command(*args, input=json.dumps(payload) if payload is not None else None)
    return json.loads(result) if result else None


def main():
    repo = os.environ['GH_REPO']
    prefix = f'repos/{repo}'
    tag = 'v1.1.1'
    release = api(f'{prefix}/releases/tags/{tag}')
    assert not release['draft']
    expected = {
        'OAnyImport-macOS-1.1.1-universal.zip': '29fbe65450f134312ab022bb9ca0425c2f117a9efd40622d451dcef58e1ebfd8',
        'OAnyImport-Windows-1.1.1-x64.zip': '6feea98aa4f25ea892ce9ba1b1e9f2ccc6c04af42ef375bd79dd45272feff7cf',
        'OAnyImport-Setup-1.1.1-x64.exe': '8299033d229ed6ba8c77723356521da92ac25b52b7abd60586e67bd5458e2a92',
    }
    assets = {asset['name']: asset for asset in release['assets']}
    for name, digest in expected.items():
        assert assets[name]['digest'] == 'sha256:' + digest, name
    checksum_name = 'OAnyImport-1.1.1-SHA256SUMS.txt'
    source_name = 'OAnyImport-1.1.1-source.zip'
    assert checksum_name in assets and source_name in assets
    head = command('git', 'rev-parse', 'HEAD')
    tag_object = api(f'{prefix}/git/ref/tags/{tag}')['object']
    assert tag_object['type'] == 'commit'
    previous = tag_object['sha']
    assert previous in ['422436004afaec46aad747b57af64efe7b6e0d4c', head]
    runtime_paths = ['Sources', 'Resources', 'Package.swift', 'Windows/app.py', 'Windows/core.py',
                     'Windows/bootstrap.py', 'Windows/media_browser.py', 'Windows/build_installer.py',
                     'Windows/installer.nsi', 'Windows/launcher.nsi', 'Windows/requirements.txt',
                     'scripts/build.sh', 'scripts/release-macos.sh']
    subprocess.run(['git', 'diff', '--quiet', previous, head, '--', *runtime_paths], check=True)
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        subprocess.run(['gh', 'release', 'download', tag, '--pattern', checksum_name, '--dir', temporary], check=True)
        checksums = {name: digest for digest, name in
                     (line.split() for line in (directory / checksum_name).read_text().splitlines())}
        for name, digest in expected.items():
            assert checksums[name] == digest
        source = directory / source_name
        subprocess.run(['git', 'archive', '--format=zip', '--prefix=OAnyImport-1.1.1/',
                        '--output=' + str(source), head], check=True)
        checksums[source_name] = hashlib.sha256(source.read_bytes()).hexdigest()
        (directory / checksum_name).write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(checksums.items())))
        subprocess.run(['gh', 'release', 'upload', tag, str(source), str(directory / checksum_name), '--clobber'], check=True)
    if previous != head:
        api(f'{prefix}/git/refs/tags/{tag}', 'PATCH', {'sha': head, 'force': True})
    subprocess.run(['gh', 'release', 'edit', tag, '--title', 'OAnyImport 1.1.1',
                    '--notes-file', 'RELEASE_NOTES.md', '--latest'], check=True)
    remaining = api(f'{prefix}/releases/tags/{tag}')
    assert remaining['name'] == 'OAnyImport 1.1.1'
    print(json.dumps({'current_release': remaining['html_url'], 'source_commit': head}, indent=2))


if __name__ == '__main__':
    main()
