"""Local-only, non-destructive media import engine."""
from __future__ import annotations
import hashlib
import os
import re
import shutil
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

KINDS = {
    '视频': 'mp4 mov mts m2ts avi mkv wmv webm m4v 3gp mpg mpeg flv f4v rmvb rm mxf braw r3d insv',
    '图片': 'jpg jpeg png gif bmp tiff tif heic heif webp avif insp',
    'RAW 照片': 'raw cr2 cr3 nef nrw arw dng rw2 orf raf x3f pef srw',
    '音频': 'wav mp3 m4a aac aif aiff flac ogg opus wma',
}
EXTENSIONS = {ext: kind for kind, exts in KINDS.items() for ext in exts.split()}
KINDS['其他文件'] = ''

@dataclass(frozen=True)
class MediaFile:
    source: Path
    root: Path
    relative: Path
    size: int
    mtime_ns: int

    @property
    def kind(self):
        return EXTENSIONS.get(self.source.suffix.lower().lstrip('.'), '其他文件')


def hidden(path: Path) -> bool:
    if path.name.startswith('.'):
        return True
    try:
        return bool(getattr(path.lstat(), 'st_file_attributes', 0) & 2)
    except OSError:
        return True


def scan(root: Path):
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError('来源必须是文件夹')
    files, warnings = [], []
    def onerror(error):
        warnings.append(str(error))
    for current, dirs, names in os.walk(root, followlinks=False, onerror=onerror):
        base = Path(current)
        dirs[:] = [d for d in dirs if not hidden(base / d) and not (base / d).is_symlink() and not is_reparse(base / d)]
        for name in names:
            path = base / name
            if hidden(path) or path.is_symlink() or is_reparse(path):
                continue
            try:
                st = path.stat()
                if path.is_file():
                    files.append(MediaFile(path, root, path.relative_to(root), st.st_size, st.st_mtime_ns))
            except OSError as exc:
                warnings.append(f'{path}: {exc}')
    return files, warnings


def is_reparse(path):
    try:
        return bool(getattr(path.lstat(), 'st_file_attributes', 0) & 1024)
    except OSError:
        return True


def digest(path, cancel=None):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while True:
            if cancel and cancel.is_set():
                raise InterruptedError('已取消')
            block = f.read(1024 * 1024)
            if not block:
                break
            h.update(block)
    return h.digest()


def validate(files, destination):
    dest = Path(destination).resolve(strict=True)
    if not dest.is_dir():
        raise ValueError('保存位置必须是文件夹')
    for item in files:
        root = item.root.resolve(strict=True)
        if dest == root or root in dest.parents:
            raise ValueError('保存位置不能位于来源目录内')
        if item.relative.is_absolute() or '..' in item.relative.parts:
            raise ValueError('来源相对路径无效')
    return dest


def unchanged(item):
    st = item.source.stat()
    if st.st_size != item.size or st.st_mtime_ns != item.mtime_ns:
        raise ValueError('来源文件发生变化，请重新扫描')
    if item.source.is_symlink() or is_reparse(item.source) or item.source.resolve() != item.root / item.relative:
        raise ValueError('来源路径发生变化，请重新扫描')


def date_for(item):
    # Filenames such as 2026-11-09 and 20261109; otherwise modification date.
    match = re.search(r'(?<!\d)(20\d{2})[-_.]?(\d{2})[-_.]?(\d{2})(?!\d)', item.source.stem)
    if match:
        try:
            return datetime(*map(int, match.groups())).strftime('%Y-%m-%d')
        except ValueError:
            pass
    return datetime.fromtimestamp(item.mtime_ns / 1e9).strftime('%Y-%m-%d')


def import_files(files, destination, layout='类型 / 日期', separate=False, verify=True, cancel=None, progress=None):
    dest = validate(files, destination)
    records = []
    for index, item in enumerate(files):
        if cancel and cancel.is_set():
            break
        if progress:
            progress(index, len(files), item.source.name)
        temp = None
        try:
            unchanged(item)
            parts = []
            if separate:
                # Include a stable path hash so identically named source folders never collide.
                suffix = hashlib.sha256(str(item.root).encode('utf-8')).hexdigest()[:8]
                parts.append(f'{item.root.name or "来源"}-{suffix}')
            if layout == '类型 / 日期':
                parts.extend([item.kind, date_for(item)])
            elif layout == '日期 / 类型':
                parts.extend([date_for(item), item.kind])
            elif layout == '保留原目录':
                parts.extend(item.relative.parts[:-1])
            else:
                raise ValueError('未知归档方式')
            folder = dest.joinpath(*parts)
            if folder.resolve() != dest and dest not in folder.resolve().parents:
                raise ValueError('目标路径越界')
            folder.mkdir(parents=True, exist_ok=True)
            if folder.resolve() != dest and dest not in folder.resolve().parents:
                raise ValueError('目标路径越界')
            source_hash = digest(item.source, cancel)
            unchanged(item)
            target = folder / item.source.name
            counter = 1
            while target.exists():
                if target.is_file() and not target.is_symlink() and digest(target, cancel) == source_hash:
                    records.append({'source': str(item.source), 'destination': str(target), 'outcome': 'skipped'})
                    break
                target = folder / f'{item.source.stem} ({counter}){item.source.suffix}'
                counter += 1
            else:
                fd, name = tempfile.mkstemp(prefix='.oanyimport-', suffix='.tmp', dir=folder)
                temp = Path(name)
                with os.fdopen(fd, 'wb') as out, item.source.open('rb') as src:
                    while True:
                        if cancel and cancel.is_set():
                            raise InterruptedError('已取消')
                        block = src.read(1024 * 1024)
                        if not block:
                            break
                        out.write(block)
                unchanged(item)
                if verify and digest(temp, cancel) != source_hash:
                    raise ValueError('SHA-256 校验失败')
                shutil.copystat(item.source, temp, follow_symlinks=False)
                # Hard-link creates the destination atomically and never overwrites a racing file.
                if os.name == 'nt':
                    # Windows rename fails if the destination already exists, including on exFAT.
                    os.rename(temp, target)
                else:
                    os.link(temp, target)
                    temp.unlink()
                temp = None
                records.append({'source': str(item.source), 'destination': str(target), 'outcome': 'copied'})
        except InterruptedError:
            break
        except (OSError, ValueError) as exc:
            records.append({'source': str(item.source), 'destination': None, 'outcome': 'failed', 'message': str(exc)})
        finally:
            if temp is not None:
                temp.unlink(missing_ok=True)
    if progress:
        progress(len(records), len(files), '')
    return records
