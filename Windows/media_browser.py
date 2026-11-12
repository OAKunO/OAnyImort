"""Right-hand media browser and local, read-only multimedia preview."""
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import queue

from PySide6.QtCore import Qt, QObject, Signal, QTimer, QUrl, QRectF, QPoint, QPointF, QSize
from PySide6.QtGui import QImage, QImageReader, QPainter, QColor, QPainterPath, QPen, QPolygonF
from PySide6.QtMultimedia import QMediaPlayer, QVideoSink, QAudioOutput
from PySide6.QtWidgets import (QWidget, QFrame, QLabel, QPushButton, QVBoxLayout, QHBoxLayout,
    QScrollArea, QLineEdit, QComboBox, QCheckBox, QStackedWidget, QSlider, QSizePolicy)


def bytes_text(size):
    for unit in ('B', 'KB', 'MB', 'GB', 'TB'):
        if size < 1000 or unit == 'TB': return f'{size:.0f} {unit}' if size >= 10 or unit == 'B' else f'{size:.1f} {unit}'
        size /= 1000


def read_image(path, size=QSize(800, 450)):
    reader = QImageReader(str(path))
    reader.setAutoTransform(True)
    original = reader.size()
    if original.isValid(): reader.setScaledSize(original.scaled(size, Qt.AspectRatioMode.KeepAspectRatio))
    return reader.read()


class ThumbnailService(QObject):
    ready = Signal(str, QImage)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.cache = {}
        self.pending = set()
        self.jobs = deque()
        self.video_pending = set()
        self.results = queue.Queue()
        self.executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix='thumbnail')
        self.active = None
        self.closed = False
        self.player = QMediaPlayer(self)
        self.sink = QVideoSink(self)
        self.player.setVideoSink(self.sink)
        self.sink.videoFrameChanged.connect(self.frame)
        self.player.errorOccurred.connect(self.failed)
        self.timeout = QTimer(self); self.timeout.setSingleShot(True)
        self.timeout.timeout.connect(self.failed)
        self.poller = QTimer(self); self.poller.timeout.connect(self.drain); self.poller.start(60)

    def request(self, file):
        path = str(file.source)
        if self.closed: return
        if path in self.cache: self.ready.emit(path, self.cache[path]); return
        if path in self.pending: return
        self.pending.add(path)
        if file.kind == '视频' or file.source.suffix.lower() == '.lrv':
            self.video_pending.add(path); self.jobs.append(path); self.next_video()
        elif file.kind in ('图片', 'RAW 照片'):
            def job():
                try: image = read_image(path)
                except Exception: image = QImage()
                self.results.put((path, image))
            self.executor.submit(job)
        else:
            self.results.put((path, QImage()))

    def drain(self):
        while not self.results.empty():
            path, image = self.results.get_nowait()
            if not self.closed: self.finish(path, image)

    def finish(self, path, image):
        self.pending.discard(path); self.video_pending.discard(path)
        self.cache[path] = image
        self.ready.emit(path, image)

    def next_video(self):
        if self.closed or self.active or not self.jobs: return
        self.active = self.jobs.popleft()
        self.timeout.start(8000)
        self.player.setSource(QUrl.fromLocalFile(self.active))
        self.player.play()

    def frame(self, frame):
        if not self.active or not frame.isValid(): return
        image = frame.toImage()
        if image.isNull(): return
        image = image.scaled(800, 450, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
        self.complete_video(image)

    def failed(self, *args):
        if self.active: self.complete_video(QImage())

    def complete_video(self, image):
        path = self.active; self.active = None
        self.timeout.stop(); self.player.stop(); self.player.setSource(QUrl())
        if path: self.finish(path, image)
        QTimer.singleShot(0, self.next_video)

    def suspend(self):
        self.jobs.clear()
        if self.active: self.pending.discard(self.active)
        self.active = None
        self.pending.difference_update(self.video_pending)
        self.video_pending.clear()
        self.timeout.stop(); self.player.stop(); self.player.setSource(QUrl())

    def shutdown(self):
        self.closed = True; self.suspend(); self.poller.stop()
        self.executor.shutdown(wait=False, cancel_futures=True)


class MediaSurface(QWidget):
    clicked = Signal()

    def __init__(self, owner, thumbnail=True, parent=None):
        super().__init__(parent)
        self.owner = owner; self.thumbnail = thumbnail
        self.image = QImage(); self.playable = False
        self.placeholder = '正在读取预览…'
        self.setCursor(Qt.CursorShape.PointingHandCursor if thumbnail else Qt.CursorShape.ArrowCursor)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.setMinimumHeight(100)

    def set_image(self, image): self.image = image; self.update()

    def paintEvent(self, event):
        p = QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing)
        colors = self.owner.palette(); rect = QRectF(self.rect())
        clip = QPainterPath(); clip.addRoundedRect(rect, 12, 12); p.setClipPath(clip)
        p.fillRect(rect, QColor(colors['selected'] if self.thumbnail else '#151513'))
        if not self.image.isNull():
            size = self.image.size().scaled(self.size(), Qt.AspectRatioMode.KeepAspectRatio)
            target = QRectF((self.width()-size.width())/2, (self.height()-size.height())/2, size.width(), size.height())
            p.drawImage(target, self.image)
        else:
            p.setPen(QColor(colors['faint'])); p.drawText(rect.adjusted(12,12,-12,-12), Qt.AlignmentFlag.AlignCenter, self.placeholder)
        if self.playable and self.thumbnail:
            cx, cy = self.width()-28, self.height()-27
            p.setBrush(QColor(colors['panel'])); p.setPen(Qt.PenStyle.NoPen); p.drawEllipse(QPoint(cx,cy),17,17)
            p.setBrush(QColor(colors['ink'])); p.drawPolygon(QPolygonF([QPointF(cx-4,cy-7),QPointF(cx+7,cy),QPointF(cx-4,cy+7)]))
        p.end()

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton: self.clicked.emit()


class PreviewCard(QFrame):
    def __init__(self, pane, file):
        super().__init__()
        self.setObjectName('previewCard')
        self.pane, self.file = pane, file
        scale = pane.ui_scale
        layout = QVBoxLayout(self); layout.setContentsMargins(0,0,0,0); layout.setSpacing(0)
        self.surface = MediaSurface(pane.owner, parent=self)
        self.surface.setFixedHeight(round(136*scale))
        self.surface.playable = file.kind in ('视频','音频') or file.source.suffix.lower()=='.lrv'
        if file.kind == '音频': self.surface.placeholder='音频 · 点击播放'
        elif file.kind == '其他文件' and not self.surface.playable: self.surface.placeholder='点击查看预览'
        self.surface.clicked.connect(lambda:pane.preview(file))
        layout.addWidget(self.surface)
        self.check = QCheckBox(self.surface); self.check.setObjectName('fileCheck')
        self.check.setToolTip('选择 '+file.source.name)
        self.check.move(round(9*scale),round(9*scale)); self.check.setFixedSize(round(32*scale),round(32*scale))
        self.check.setChecked(str(file.source) not in pane.owner.excluded)
        self.check.toggled.connect(self.toggle)
        info = QWidget(); box = QVBoxLayout(info); box.setContentsMargins(round(12*scale),round(10*scale),round(12*scale),round(10*scale)); box.setSpacing(round(5*scale))
        name = QLabel(file.source.name); name.setObjectName('fileName'); name.setToolTip(str(file.source)); name.setWordWrap(False)
        name.setMinimumWidth(0); name.setSizePolicy(QSizePolicy.Policy.Ignored,QSizePolicy.Policy.Preferred)
        box.addWidget(name)
        row = QHBoxLayout(); source = QLabel(file.root.name or str(file.root)); source.setObjectName('muted')
        source.setMinimumWidth(30); source.setSizePolicy(QSizePolicy.Policy.Expanding,QSizePolicy.Policy.Preferred)
        row.addWidget(source,1); size=QLabel(bytes_text(file.size)); size.setObjectName('muted'); row.addWidget(size); box.addLayout(row)
        path = QLabel(str(file.relative)); path.setObjectName('faint'); path.setToolTip(str(file.relative))
        path.setMinimumWidth(0); path.setSizePolicy(QSizePolicy.Policy.Ignored,QSizePolicy.Policy.Preferred); box.addWidget(path)
        layout.addWidget(info)

    def toggle(self, checked):
        if self.pane.owner.busy:
            self.check.blockSignals(True); self.check.setChecked(str(self.file.source) not in self.pane.owner.excluded); self.check.blockSignals(False); return
        self.pane.owner.select_group([self.file], checked)

    def sync(self):
        self.check.blockSignals(True); self.check.setChecked(str(self.file.source) not in self.pane.owner.excluded); self.check.blockSignals(False)
        self.check.setEnabled(not self.pane.owner.busy)


class DetailPane(QFrame):
    def __init__(self, owner, kind, scale=1):
        super().__init__(owner)
        self.owner, self.kind, self.ui_scale = owner, kind, scale
        self.setObjectName('detailPane'); self.setAcceptDrops(False)
        self.setAttribute(Qt.WidgetAttribute.WA_NoMousePropagation)
        self.cards = []; self.limit = 6; self.current_file = None
        self.thumbnails = ThumbnailService(self); self.thumbnails.ready.connect(self.thumbnail_ready)
        self.player = QMediaPlayer(self); self.audio = QAudioOutput(self); self.audio.setVolume(.7)
        self.player.setAudioOutput(self.audio); self.sink = QVideoSink(self); self.player.setVideoSink(self.sink)
        self.sink.videoFrameChanged.connect(self.video_frame)
        self.player.durationChanged.connect(self.duration_changed); self.player.positionChanged.connect(self.position_changed)
        self.player.playbackStateChanged.connect(self.playback_changed); self.player.errorOccurred.connect(self.media_error)
        layout=QVBoxLayout(self); layout.setContentsMargins(0,0,0,0); layout.setSpacing(0)
        header=QWidget(); header_box=QHBoxLayout(header); header_box.setContentsMargins(22,22,22,18)
        title_box=QVBoxLayout(); self.title=QLabel(kind+'详情'); self.title.setObjectName('paneTitle'); title_box.addWidget(self.title)
        subtitle=QLabel('先看一眼，再好好收藏。'); subtitle.setObjectName('muted'); title_box.addWidget(subtitle)
        header_box.addLayout(title_box); header_box.addStretch()
        close=QPushButton('×'); close.setObjectName('closePane'); close.setFixedSize(28,28); close.clicked.connect(owner.close_details); header_box.addWidget(close)
        layout.addWidget(header)
        self.stack=QStackedWidget(); layout.addWidget(self.stack,1)
        gallery=QWidget(); gallery_box=QVBoxLayout(gallery); gallery_box.setContentsMargins(0,0,0,0); gallery_box.setSpacing(0)
        filters=QWidget(); filter_box=QVBoxLayout(filters); filter_box.setContentsMargins(22,0,22,16); filter_box.setSpacing(12)
        self.source=QComboBox(); self.source.addItem('所有选中的来源','')
        for s in owner.sources:
            if s['enabled']: self.source.addItem(s['name'],str(Path(s['path']).resolve()))
        self.source.setVisible(self.source.count()>2); self.source.currentIndexChanged.connect(self.reset_list); filter_box.addWidget(self.source)
        self.search=QLineEdit(); self.search.setPlaceholderText('搜索文件名'); self.search.setClearButtonEnabled(True); self.search.textChanged.connect(self.reset_list); filter_box.addWidget(self.search)
        row=QHBoxLayout(); self.count=QLabel(); self.count.setObjectName('muted'); row.addWidget(self.count); row.addStretch(); hint=QLabel('点击预览'); hint.setObjectName('faint'); row.addWidget(hint); filter_box.addLayout(row)
        gallery_box.addWidget(filters)
        self.scroll=QScrollArea(); self.scroll.setWidgetResizable(True); self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff); self.scroll.setFrameShape(QFrame.Shape.NoFrame)
        self.scroll.viewport().setObjectName('browserViewport')
        self.contents=QWidget(); self.contents.setObjectName('browserContents'); self.card_box=QVBoxLayout(self.contents); self.card_box.setContentsMargins(20,4,20,18); self.card_box.setSpacing(13)
        self.scroll.setWidget(self.contents); gallery_box.addWidget(self.scroll,1)
        self.scroll.verticalScrollBar().valueChanged.connect(lambda:QTimer.singleShot(0,self.load_visible))
        self.stack.addWidget(gallery)
        playback=QWidget(); play_box=QVBoxLayout(playback); play_box.setContentsMargins(20,0,20,20); play_box.setSpacing(12)
        back=QPushButton('‹  返回素材列表'); back.clicked.connect(self.back); play_box.addWidget(back,alignment=Qt.AlignmentFlag.AlignLeft)
        self.play_name=QLabel(); self.play_name.setWordWrap(True); play_box.addWidget(self.play_name)
        self.video=MediaSurface(owner,False); self.video.setMinimumHeight(round(180*scale)); self.video.clicked.connect(self.toggle_play); play_box.addWidget(self.video,1)
        self.status=QLabel(); self.status.setWordWrap(True); self.status.setObjectName('muted'); play_box.addWidget(self.status)
        self.seek=QSlider(Qt.Orientation.Horizontal); self.seek.setRange(0,0); self.seek.sliderMoved.connect(self.player.setPosition); self.seek.sliderReleased.connect(lambda:self.player.setPosition(self.seek.value())); play_box.addWidget(self.seek)
        controls=QHBoxLayout(); self.play_button=QPushButton('播放'); self.play_button.clicked.connect(self.toggle_play); controls.addWidget(self.play_button)
        self.time=QLabel('00:00 / 00:00'); self.time.setObjectName('muted'); controls.addWidget(self.time); controls.addStretch()
        self.mute=QPushButton('静音'); self.mute.setCheckable(True); self.mute.toggled.connect(self.audio.setMuted); controls.addWidget(self.mute); play_box.addLayout(controls)
        self.stack.addWidget(playback)
        footer=QLabel('勾选要导入的文件；点击缩略图可预览。'); footer.setObjectName('paneFooter'); footer.setWordWrap(True); layout.addWidget(footer)
        self.apply_theme(); self.rebuild()

    def apply_theme(self):
        p=self.owner.palette(); s=self.ui_scale
        self.setStyleSheet(f'''
        QFrame#detailPane {{ background:{p['background']}; border-left:1px solid {p['line']}; }}
        QWidget {{ color:{p['ink']}; font-family:"{self.owner.font_family}"; font-size:{round(11*s)}px; }}
        QLabel#paneTitle {{ font-size:{round(19*s)}px; font-weight:600; }}
        QLabel#muted {{ color:{p['secondary']}; font-size:{round(10*s)}px; }}
        QLabel#faint {{ color:{p['faint']}; font-size:{round(9*s)}px; }}
        QLabel#fileName {{ font-size:{round(11*s)}px; font-weight:500; }}
        QLabel#paneFooter {{ color:{p['secondary']}; border-top:1px solid {p['line']}; padding:{round(20*s)}px; font-size:{round(10*s)}px; }}
        QScrollArea, QStackedWidget {{ background:transparent; border:0; }}
        QWidget#browserContents {{ background:{p['background']}; }}
        QFrame#previewCard {{ background:{p['panel']}; border:1px solid {p['line']}; border-radius:{round(13*s)}px; }}
        QLineEdit,QComboBox {{ background:{p['selected']};border:0;border-radius:8px;padding:{round(9*s)}px; }}
        QPushButton {{ background:{p['selected']};border:0;border-radius:8px;padding:8px 12px; }}
        QPushButton:hover {{ background:{p['line']}; }}
        QPushButton#closePane {{ padding:0;border-radius:14px;font-size:20px; }}
        QCheckBox#fileCheck {{ background:{p['panel']}; border-radius:8px;padding:7px; }}
        QCheckBox::indicator {{ width:{round(18*s)}px;height:{round(18*s)}px;border:1px solid {p['faint']};border-radius:4px;background:{p['panel']}; }}
        QCheckBox::indicator:checked {{ background:{p['accent']};border-color:{p['accent']};image:url("{self.checkmark_path()}"); }}
        QScrollBar:vertical {{ width:7px;background:transparent; }}
        QScrollBar::handle:vertical {{ background:{p['line']};min-height:25px;border-radius:3px; }}
        QScrollBar::add-line:vertical,QScrollBar::sub-line:vertical {{ height:0; }}
        QSlider::groove:horizontal {{ background:{p['line']};height:4px;border-radius:2px; }}
        QSlider::handle:horizontal {{ background:{p['accent']};width:12px;margin:-4px 0;border-radius:6px; }}
        ''')
        self.scroll.viewport().setStyleSheet(f"QWidget#browserViewport {{ background:{p['background']}; }}")
        for card in self.cards: card.surface.update()
        self.video.update()

    def checkmark_path(self):
        return Path(__file__).with_name('checkmark.svg').as_posix()

    def filtered(self):
        query=self.search.text().casefold(); root=self.source.currentData()
        return [f for f in self.owner.active_files() if f.kind==self.kind and (not query or query in f.source.name.casefold()) and (not root or str(f.root)==root)]

    def reset_list(self):
        selected=self.source.currentData()
        self.source.blockSignals(True); self.source.clear(); self.source.addItem('所有选中的来源','')
        for source in self.owner.sources:
            if source['enabled']: self.source.addItem(source['name'],str(Path(source['path']).resolve()))
        index=self.source.findData(selected)
        self.source.setCurrentIndex(max(0,index)); self.source.setVisible(self.source.count()>2); self.source.blockSignals(False)
        self.limit=6; self.back(); self.rebuild()

    def rebuild(self):
        self.thumbnails.suspend()
        self.cards=[]
        while self.card_box.count():
            item=self.card_box.takeAt(0)
            if item.widget(): item.widget().deleteLater()
        files=self.filtered()
        if not files:
            empty=QLabel('没有匹配的文件'); empty.setAlignment(Qt.AlignmentFlag.AlignCenter); self.card_box.addWidget(empty)
        for file in files[:self.limit]:
            card=PreviewCard(self,file); self.cards.append(card); self.card_box.addWidget(card)
        if len(files)>self.limit:
            more=QPushButton(f'查看全部 {len(files)} 个文件'); more.clicked.connect(self.show_all); self.card_box.addWidget(more)
        self.card_box.addStretch(1); self.refresh_selection()
        QTimer.singleShot(50,self.load_visible)

    def show_all(self): self.limit=len(self.filtered()); self.rebuild()

    def refresh_selection(self):
        files=self.filtered(); selected=sum(str(f.source) not in self.owner.excluded for f in files)
        self.count.setText(f'{len(files)} 个文件 · 已选 {selected} 个')
        for card in self.cards: card.sync()

    def load_visible(self):
        if not self.isVisible() or self.stack.currentIndex()!=0: return
        viewport=self.scroll.viewport()
        for card in self.cards:
            pos=card.mapTo(viewport,QPoint(0,0))
            if pos.y()+card.height()>=0 and pos.y()<viewport.height(): self.thumbnails.request(card.file)

    def thumbnail_ready(self,path,image):
        for card in self.cards:
            if str(card.file.source)==path:
                card.surface.placeholder='暂时无法生成封面 · 点击预览' if card.surface.playable else '该格式暂不支持预览'
                card.surface.set_image(image)

    def preview(self,file):
        self.thumbnails.suspend(); self.current_file=file
        self.player.stop(); self.video.image=QImage(); self.video.placeholder='正在打开预览…'; self.video.update()
        self.play_name.setText(file.source.name); self.status.setText(''); self.stack.setCurrentIndex(1)
        playable=file.kind in ('视频','音频') or file.source.suffix.lower()=='.lrv'
        for widget in [self.seek,self.play_button,self.time,self.mute]: widget.setVisible(playable)
        if playable:
            if file.kind=='音频': self.video.placeholder='音频预览'
            self.player.setSource(QUrl.fromLocalFile(str(file.source))); self.player.play()
        else:
            image=read_image(file.source,QSize(1800,1200)); self.video.set_image(image)
            if image.isNull(): self.video.placeholder='该格式暂不支持内嵌预览'; self.video.update()

    def back(self):
        self.player.stop(); self.player.setSource(QUrl()); self.current_file=None
        self.stack.setCurrentIndex(0); QTimer.singleShot(0,self.load_visible)

    def video_frame(self,frame):
        if frame.isValid():
            image=frame.toImage()
            if not image.isNull(): self.video.set_image(image)

    def toggle_play(self):
        if not self.current_file or not self.current_file.source.is_file(): return
        if self.current_file.kind not in ('视频','音频') and self.current_file.source.suffix.lower()!='.lrv': return
        if self.player.playbackState()==QMediaPlayer.PlaybackState.PlayingState: self.player.pause()
        else: self.player.play()

    def playback_changed(self,state):
        self.play_button.setText('暂停' if state==QMediaPlayer.PlaybackState.PlayingState else '播放')

    def duration_changed(self,duration): self.seek.setRange(0,duration)

    def position_changed(self,position):
        if not self.seek.isSliderDown(): self.seek.setValue(position)
        def clock(ms): return f'{ms//60000:02d}:{ms//1000%60:02d}'
        self.time.setText(clock(position)+' / '+clock(self.player.duration()))

    def media_error(self,*args):
        self.status.setText('无法播放此文件：'+self.player.errorString())
        self.video.placeholder='该视频或编码暂不支持预览'; self.video.update()

    def shutdown(self):
        self.thumbnails.shutdown(); self.player.stop(); self.player.setSource(QUrl())
