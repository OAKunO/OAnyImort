"""Render real UI states with generated, non-user media fixtures."""
import os
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
import shutil
import sys
import time
from pathlib import Path
from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QImage,QColor
from app import App

root=Path(__file__).resolve().parent
evidence=root/'test-evidence'
fixtures=evidence/'browser-fixtures'; fixtures.mkdir(exist_ok=True)
for name in ['VID_20261109_133417.mp4','VID_20261109_133502.mov','VID_20261109_133617.mp4','LRV_20261109_133417.lrv']:
    shutil.copy2(evidence/'media/20261109-preview.mp4',fixtures/name)
image=QImage(640,360,QImage.Format.Format_RGB32); image.fill(QColor('#91a69d')); image.save(str(fixtures/'IMG_20261109_134200.jpg'))
app=QApplication([])
window=App(settings=False); window.resize(1094,789); window.show()
def until(test,seconds=15):
    end=time.monotonic()+seconds
    while not test() and time.monotonic()<end: app.processEvents(); time.sleep(.01)
    if not test(): raise RuntimeError('Preview did not become ready')
window.add_path(fixtures); until(lambda:not window.busy)
window.extension_menu('视频'); app.processEvents()
window.grab().save(str(evidence/'05-inline-formats.png'))
window.details('视频'); app.processEvents(); pane=window.detail_pane
until(lambda:pane.cards and all(not card.surface.image.isNull() for card in pane.cards),seconds=25)
window.grab().save(str(evidence/'06-right-browser.png'))
pane.preview(pane.cards[0].file)
until(lambda:pane.player.position()>500 and not pane.video.image.isNull())
pane.player.pause(); app.processEvents()
window.grab().save(str(evidence/'07-inline-video-player.png'))
pane.back(); window.change_theme('dark'); app.processEvents()
window.grab().save(str(evidence/'08-right-browser-dark.png'))
window.close(); app.processEvents()
print('Four browser/format/player screenshots saved.')
