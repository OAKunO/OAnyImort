"""Interaction checks use the actual Qt widgets and real temporary source files."""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from PySide6.QtCore import Qt, QPoint
from PySide6.QtTest import QTest
from PySide6.QtGui import QImage, QColor
from PySide6.QtWidgets import QApplication
from app import App, migrate_preferences
from PySide6.QtCore import QSettings

APP = QApplication.instance() or QApplication([])

class InterfaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.src = self.root / 'card'; self.src.mkdir()
        (self.src / '20261109.mp4').write_bytes(b'video bytes')
        (self.src / 'photo.jpg').write_bytes(b'photo bytes')
        self.window = App(settings=False)
        self.window.show(); APP.processEvents()
    def tearDown(self):
        self.window.busy = False; self.window.close(); APP.processEvents(); self.tmp.cleanup()
    def wait_for_idle(self):
        until = time.monotonic() + 5
        while self.window.busy and time.monotonic() < until:
            APP.processEvents(); time.sleep(.01)
        self.assertFalse(self.window.busy)
        APP.processEvents()
    def test_name_correction_migrates_preferences_once_without_overwriting(self):
        def store(name):
            return QSettings(str(self.root / (name + '.ini')), QSettings.Format.IniFormat)
        current, legacy, older = store('current'), store('legacy'), store('older')
        current.setValue('appearance', 'light')
        legacy.setValue('destination', '/old/media')
        legacy.setValue('verify', 'false')
        legacy.setValue('appearance', 'dark')
        legacy.setValue('migratedLegacyPreferences', True)
        older.setValue('destination', '/older/media')
        older.setValue('layout', '保留原目录')
        migrate_preferences(current, [legacy, older])
        self.assertEqual(current.value('destination'), '/old/media')
        self.assertEqual(current.value('verify'), 'false')
        self.assertEqual(current.value('appearance'), 'light')
        self.assertEqual(current.value('layout'), '保留原目录')
        current.remove('destination')
        migrate_preferences(current, [legacy, older])
        self.assertIsNone(current.value('destination'))
        self.assertEqual(self.window.windowTitle(), 'OAnyImport')
    def click(self, key):
        APP.processEvents()
        rect = next(rect for hit,rect,_ in self.window.hits if hit==key)
        pt = rect.center()*self.window.scale
        QTest.mouseClick(self.window,Qt.MouseButton.LeftButton,pos=QPoint(round(pt.x()),round(pt.y())))
        APP.processEvents()
    def test_category_selection_theme_and_layout(self):
        self.window.add_path(self.src); self.wait_for_idle()
        self.assertEqual(len(self.window.selected_files()),2)
        self.click('kind-视频'); self.assertEqual(len(self.window.selected_files()),1)
        self.click('kind-视频'); self.assertEqual(len(self.window.selected_files()),2)
        self.click('theme-dark'); self.assertEqual(self.window.appearance,'dark')
        self.click('verify'); self.assertFalse(self.window.verify)
        self.click('separate'); self.assertTrue(self.window.separate)
        self.window.set_layout('保留原目录'); self.assertEqual(self.window.layout,'保留原目录')
    def test_import_from_visible_action(self):
        self.window.add_path(self.src); self.wait_for_idle()
        self.window.destination = self.root / 'destination'
        self.window.set_layout('保留原目录')
        with patch.object(self.window,'report'):
            self.click('start'); self.wait_for_idle()
        self.assertEqual(len(self.window.records),2)
        self.assertTrue(all(r['outcome']=='copied' for r in self.window.records))
        self.assertEqual((self.window.destination/'20261109.mp4').read_bytes(),b'video bytes')
    def test_inline_formats_remain_visible_and_lrv_is_other(self):
        (self.src / 'proxy.LRV').write_bytes(b'proxy bytes')
        self.window.add_path(self.src); self.wait_for_idle()
        self.assertEqual(next(f.kind for f in self.window.files if f.source.suffix=='.LRV'),'其他文件')
        self.click('ext-视频')
        self.assertIn('视频',self.window.expanded_kinds)
        self.click('extension-视频-.mp4')
        self.assertEqual(sum(f.kind=='视频' for f in self.window.selected_files()),0)
        self.assertIn('视频',self.window.expanded_kinds)
        self.assertFalse(any(w.isVisible() and w.inherits('QMenu') for w in QApplication.topLevelWidgets()))
        self.click('extension-视频-.mp4')
        self.assertEqual(sum(f.kind=='视频' for f in self.window.selected_files()),1)

    def test_right_browser_thumbnail_search_and_check(self):
        image=QImage(240,140,QImage.Format.Format_RGB32); image.fill(QColor('#80a293')); image.save(str(self.src/'photo.jpg'))
        self.window.add_path(self.src); self.wait_for_idle()
        self.click('detail-图片')
        pane=self.window.detail_pane
        self.assertIsNotNone(pane); self.assertIs(pane.parent(),self.window)
        self.assertEqual(pane.geometry().right(),self.window.width()-1)
        self.assertEqual(len(pane.cards),1)
        until=time.monotonic()+5
        while pane.cards[0].surface.image.isNull() and time.monotonic()<until:
            APP.processEvents(); time.sleep(.01)
        self.assertFalse(pane.cards[0].surface.image.isNull())
        QTest.mouseClick(pane.cards[0].check,Qt.MouseButton.LeftButton)
        self.assertEqual(sum(f.kind=='图片' for f in self.window.selected_files()),0)
        pane.search.setText('missing-file'); APP.processEvents()
        self.assertEqual(len(pane.cards),0)
        self.window.close_details(); self.assertIsNone(self.window.detail_pane)

    def test_resize_preserves_key_controls(self):
        for width,height in [(1020,760),(1094,789),(1600,900)]:
            self.window.resize(width,height); APP.processEvents()
            for key in ['add','choose-dest','theme-light','layout']:
                rect=next(rect for hit,rect,_ in self.window.hits if hit==key)
                self.assertGreaterEqual(rect.left(),0)
                self.assertLessEqual(rect.right(),self.window.W)
                self.assertLessEqual(rect.bottom(),self.window.H)

if __name__=='__main__': unittest.main()
