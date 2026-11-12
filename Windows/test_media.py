"""Decode a real local MP4 through the same Qt backend shipped with the app."""
import os
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
import tempfile
import time
import unittest
from pathlib import Path
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import Qt
from PySide6.QtTest import QTest
from PySide6.QtMultimedia import QMediaPlayer
from app import App

APP=QApplication.instance() or QApplication([])
CLIP=Path(__file__).parent/'test-evidence/media/20261109-preview.mp4'

class MediaTests(unittest.TestCase):
    def wait_until(self,condition,seconds=15):
        until=time.monotonic()+seconds
        while not condition() and time.monotonic()<until:
            APP.processEvents(); time.sleep(.01)
        self.assertTrue(condition())
    def test_actual_thumbnail_play_pause_seek_and_close(self):
        window=App(settings=False); window.resize(1094,789); window.show()
        try:
            window.add_path(CLIP.parent)
            self.wait_until(lambda:not window.busy)
            window.details('视频'); APP.processEvents(); pane=window.detail_pane
            self.assertEqual(len(pane.cards),1)
            self.wait_until(lambda:not pane.cards[0].surface.image.isNull())
            self.assertGreater(pane.cards[0].surface.image.width(),0)
            QTest.mouseClick(pane.cards[0].surface,Qt.MouseButton.LeftButton)
            self.wait_until(lambda:pane.player.position()>150 and not pane.video.image.isNull())
            self.assertEqual(pane.stack.currentIndex(),1)
            QTest.mouseClick(pane.play_button,Qt.MouseButton.LeftButton)
            self.assertEqual(pane.player.playbackState(),QMediaPlayer.PlaybackState.PausedState)
            pane.seek.setValue(1200); pane.seek.sliderMoved.emit(1200)
            self.wait_until(lambda:pane.player.position()>=1100)
            pane.back(); APP.processEvents()
            self.assertEqual(pane.player.playbackState(),QMediaPlayer.PlaybackState.StoppedState)
            self.assertEqual(pane.stack.currentIndex(),0)
            window.close_details(); APP.processEvents(); self.assertIsNone(window.detail_pane)
        finally:
            window.close(); APP.processEvents()

if __name__=='__main__': unittest.main()
