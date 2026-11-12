import tempfile
import unittest
from pathlib import Path
from threading import Event
from core import scan, import_files, validate

class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.base = Path(self.tmp.name)
        self.src = self.base / 'card'; self.src.mkdir()
        self.dest = self.base / 'out'; self.dest.mkdir()
    def tearDown(self): self.tmp.cleanup()
    def file(self, name='20261109_clip.MP4', data=b'original'):
        path = self.src / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data); return path
    def test_copy_skip_conflict(self):
        src = self.file(); files, warnings = scan(self.src); self.assertFalse(warnings)
        first = import_files(files, self.dest); self.assertEqual(first[0]['outcome'], 'copied')
        self.assertEqual(Path(first[0]['destination']).read_bytes(), b'original')
        self.assertEqual(import_files(files, self.dest)[0]['outcome'], 'skipped')
        src.write_bytes(b'changed data'); files, _ = scan(self.src)
        second = import_files(files, self.dest); self.assertEqual(second[0]['outcome'], 'copied')
        self.assertNotEqual(first[0]['destination'], second[0]['destination'])
        self.assertEqual(Path(first[0]['destination']).read_bytes(), b'original')
    def test_reject_destination_inside_source(self):
        self.file(); (self.src / 'out').mkdir(); files, _ = scan(self.src)
        with self.assertRaises(ValueError): validate(files, self.src / 'out')
    def test_source_changed_after_scan(self):
        src = self.file(); files, _ = scan(self.src); src.write_bytes(b'different content')
        self.assertEqual(import_files(files, self.dest)[0]['outcome'], 'failed')
        self.assertEqual(list(self.dest.rglob('*.MP4')), [])
    def test_hidden_links_and_cancel(self):
        self.file(); self.file('.hidden.jpg'); (self.src / 'link').symlink_to(self.src / '20261109_clip.MP4')
        files, _ = scan(self.src); self.assertEqual(len(files), 1)
        cancel = Event(); cancel.set(); self.assertEqual(import_files(files, self.dest, cancel=cancel), [])
    def test_preserve_structure_and_date(self):
        self.file('folder/2026-11-09.jpg'); files, _ = scan(self.src)
        records = import_files(files, self.dest, layout='保留原目录')
        self.assertEqual(Path(records[0]['destination']), (self.dest / 'folder' / '2026-11-09.jpg').resolve())
        other = self.base / 'other'; other.mkdir(); records = import_files(files, other)
        self.assertEqual(Path(records[0]['destination']), (other / '图片' / '2026-11-09' / '2026-11-09.jpg').resolve())

if __name__ == '__main__': unittest.main()
