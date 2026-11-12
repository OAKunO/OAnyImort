"""Build an offline Windows installer using a pinned portable CPython runtime."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VERSION = '1.1.0'
RUNTIME_SHA256 = '50c4f17809457e411c2db30959c8fb25a958ff3a6f624080044992809509bc37'
RUNTIME_URL = 'https://sourceforge.net/projects/winpython/files/WinPython_3.13/3.13.18.0/WinPython64-3.13.18.0dot.zip/download'
RUNTIME_PREFIX = 'WPy64-313180/python/'
QT_WHEELS = {
    'PySide6_Essentials-6.8.3-cp39-abi3-win_amd64.whl': '3c0fae5550aff69f2166f46476c36e0ef56ce73d84829eac4559770b0c034b07',
    'shiboken6-6.8.3-cp39-abi3-win_amd64.whl': 'bca3a94513ce9242f7d4bbdca902072a1631888e0aa3a8711a52cc5dbe93588f',
    'PySide6_Addons-6.8.3-cp39-abi3-win_amd64.whl': '67548f6db11f4e1b7e4b6efd9c3fc2e8d275188a7b2feac388961128572a6955',
}

def needed_addon(name):
    # Only multimedia is needed; omit unrelated WebEngine/3D/Charts modules.
    return (name in ['PySide6/QtMultimedia.pyd', 'PySide6/QtMultimedia.pyi', 'PySide6/Qt6Multimedia.dll']
        or name.startswith(('PySide6/plugins/multimedia/', 'PySide6/plugins/audio/'))
        or (name.startswith('PySide6/') and name.endswith('.dll')
            and Path(name).name.startswith(('avcodec-', 'avformat-', 'avutil-', 'swscale-', 'swresample-')))
        or '.dist-info/' in name)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--makensis', default=shutil.which('makensis'))
    args = parser.parse_args()
    if not args.makensis:
        parser.error('Install NSIS, or supply --makensis /path/to/makensis')
    runtime_zip = ROOT / '.downloads' / 'winpython.zip'
    if not runtime_zip.is_file():
        parser.error('Download the pinned runtime into .downloads/winpython.zip from ' + RUNTIME_URL)
    if sha(runtime_zip) != RUNTIME_SHA256:
        raise SystemExit('Runtime SHA-256 mismatch; refusing to package.')
    payload = ROOT / 'build' / 'payload'
    if payload.exists():
        shutil.rmtree(payload)
    runtime = payload / 'runtime'
    runtime.mkdir(parents=True)
    with zipfile.ZipFile(runtime_zip) as archive:
        for info in archive.infolist():
            if not info.filename.startswith(RUNTIME_PREFIX) or info.is_dir():
                continue
            relative = Path(info.filename[len(RUNTIME_PREFIX):])
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe runtime archive path')
            target = runtime / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as src, target.open('wb') as dest:
                shutil.copyfileobj(src, dest)
    for required in ['pythonw.exe', 'python.exe', 'python313.dll', 'LICENSE.txt']:
        if not (runtime / required).is_file():
            raise ValueError('Incomplete runtime: ' + required)
    for filename, checksum in QT_WHEELS.items():
        wheel = ROOT / '.downloads' / 'qt' / filename
        if not wheel.is_file() or sha(wheel) != checksum:
            raise SystemExit('Missing or invalid Windows Qt wheel: ' + filename)
        with zipfile.ZipFile(wheel) as archive:
            for info in archive.infolist():
                relative = Path(info.filename)
                if relative.is_absolute() or '..' in relative.parts:
                    raise ValueError('Unsafe wheel archive path')
            members=[n for n in archive.namelist() if 'Addons' not in filename or needed_addon(n)]
            archive.extractall(runtime / 'Lib' / 'site-packages',members=members)
    for required in ['PySide6/QtWidgets.pyd', 'PySide6/plugins/platforms/qwindows.dll', 'shiboken6/Shiboken.pyd', 'PySide6/QtMultimedia.pyd', 'PySide6/Qt6Multimedia.dll', 'PySide6/plugins/multimedia/ffmpegmediaplugin.dll', 'PySide6/avcodec-61.dll', 'PySide6/avformat-61.dll', 'PySide6/avutil-59.dll', 'PySide6/swscale-8.dll', 'PySide6/swresample-5.dll']:
        if not (runtime / 'Lib' / 'site-packages' / required).is_file():
            raise ValueError('Incomplete Qt runtime: ' + required)
    for file in ['app.py', 'core.py', 'media_browser.py', 'bootstrap.py', 'app.ico', 'checkmark.svg', '使用说明.txt', 'THIRD_PARTY_NOTICES.txt']:
        shutil.copy2(ROOT / file, payload / file)
    shutil.copytree(ROOT / 'licenses', payload / 'licenses')
    shutil.copy2(ROOT.parent / 'LICENSE', payload / 'LICENSE.txt')
    (payload / 'runtime-source.json').write_text(json.dumps({
        'distribution': 'WinPython64-3.13.18.0dot', 'source': RUNTIME_URL,
        'sha256': RUNTIME_SHA256,
        'qt_wheels': QT_WHEELS,
        'license': 'runtime/LICENSE.txt; additional component licenses are retained in runtime',
    }, indent=2), encoding='utf-8')
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    env = os.environ.copy()
    compiler = Path(args.makensis).resolve()
    local_nsis = compiler.parent.parent / 'share' / 'nsis'
    if local_nsis.is_dir():
        env['NSISDIR'] = str(local_nsis)
    for script in ['launcher.nsi', 'installer.nsi']:
        command = [str(compiler), '-V2']
        if script == 'installer.nsi':
            command.append('-DPAYLOAD_GLOB=' + str(payload / '*'))
        subprocess.run([*command, script], cwd=ROOT, env=env, check=True)
    setup = dist / f'OAnyImort-Setup-{VERSION}-x64.exe'
    manifest = {
        'product': 'OAnyImort',
        'version': VERSION, 'target': 'Windows 10/11 x64',
        'signing': 'Unsigned: trusted Windows Authenticode certificate not configured.',
        'setup_sha256': sha(setup), 'runtime_sha256': RUNTIME_SHA256,
        'qt_wheels': QT_WHEELS,
        'verification': 'Qt UI rendered and interaction-tested on macOS; Windows installation and UI are not yet runtime-tested.',
        'files': {str(p.relative_to(payload)): sha(p) for p in payload.rglob('*') if p.is_file()},
    }
    (dist / 'build-manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
    release = dist / f'OAnyImort-Windows-{VERSION}-x64.zip'
    with zipfile.ZipFile(release, 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(setup, 'OAnyImort-Windows/Setup.exe')
        z.write(ROOT / '使用说明.txt', 'OAnyImort-Windows/使用说明.txt')
        z.write(ROOT.parent / 'LICENSE', 'OAnyImort-Windows/LICENSE.txt')
        z.write(dist / 'build-manifest.json', 'OAnyImort-Windows/build-manifest.json')
        for license_file in sorted((ROOT / 'licenses').glob('*.txt')):
            z.write(license_file, 'OAnyImort-Windows/licenses/' + license_file.name)
    print(f'Created {release} ({release.stat().st_size / 1024 / 1024:.1f} MB)')

if __name__ == '__main__':
    main()
