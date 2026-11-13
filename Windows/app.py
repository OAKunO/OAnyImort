"""OAnyImport desktop interface, rendered consistently with the macOS design."""
import ctypes
import json
import os
import queue
import shutil
import sys
import threading
from collections import Counter
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import Qt, QRectF, QPointF, QTimer, QSettings, QSize
from PySide6.QtGui import QColor, QPainter, QPen, QPainterPath, QFont, QIcon, QPolygonF, QDesktopServices
from PySide6.QtCore import QUrl
from PySide6.QtWidgets import (QApplication, QWidget, QFileDialog, QMessageBox, QDialog,
    QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QTreeWidget, QTreeWidgetItem, QMenu)
from core import KINDS, MediaFile, scan, import_files, validate

LIGHT = dict(background='#F8F5EF', sidebar='#F0EBE2', panel='#FFFDFA', ink='#3B362F', secondary='#847B6F', faint='#A49B8F', line='#E8E1D6', selected='#F3EDE2', accent='#806A50', button='#494339', onButton='#FFF9EF')
DARK = dict(background='#201F1D', sidebar='#262522', panel='#2B2A27', ink='#EEE9DF', secondary='#B3ADA2', faint='#827C73', line='#413E38', selected='#39352F', accent='#D3C1A7', button='#E5DAC7', onButton='#292720')
LAYOUTS = ['类型 / 日期', '日期 / 类型', '保留原目录']
SYMBOLS = ['video', 'photo', 'raw', 'audio', 'file']


def byte_string(size):
    if size == 0: return '0 KB'
    for unit in ('B', 'KB', 'MB', 'GB', 'TB'):
        if size < 1000 or unit == 'TB': return f'{size:.0f} {unit}' if size >= 10 or unit == 'B' else f'{size:.1f} {unit}'
        size /= 1000


def devices():
    if os.name != 'nt': return []
    result = []
    kernel = ctypes.windll.kernel32
    for letter in 'DEFGHIJKLMNOPQRSTUVWXYZ':
        root = f'{letter}:\\'
        if kernel.GetDriveTypeW(root) == 2:
            name = ctypes.create_unicode_buffer(261)
            kernel.GetVolumeInformationW(root, name, 261, None, None, None, None, 0)
            result.append((root, name.value or f'存储卡 ({letter}:)'))
    return result


def migrate_preferences(settings, legacy_stores=None):
    marker = 'migratedOAnyImportPreferences'
    if settings.contains(marker):
        return
    if legacy_stores is None:
        legacy_stores = [QSettings('OAnyImort', 'OAnyImort'), QSettings('SDImport', 'SDImport')]
    for legacy in legacy_stores:
        for key in legacy.allKeys():
            if not settings.contains(key):
                settings.setValue(key, legacy.value(key))
    settings.setValue(marker, True)
    settings.sync()


class App(QWidget):
    def __init__(self, demo=False, settings=True):
        super().__init__()
        self.setWindowTitle('OAnyImport')
        self.setWindowIcon(QIcon(str(Path(__file__).with_name('app.ico'))))
        self.setWindowFlags(Qt.WindowType.Window | Qt.WindowType.FramelessWindowHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setMinimumSize(820, 590)
        available = QApplication.primaryScreen().availableGeometry()
        fit = min(1, available.width() * .94 / 1094, available.height() * .94 / 789)
        self.resize(max(820, round(1094 * fit)), max(590, round(789 * fit)))
        self.setMouseTracking(True)
        self.setAcceptDrops(True)
        self.settings = QSettings('OAnyImport', 'OAnyImport') if settings else None
        if self.settings:
            migrate_preferences(self.settings)
        self.appearance = self.pref('appearance', 'light')
        self.destination = Path(self.pref('destination', str(Path.home() / 'Documents' / '视频素材')))
        self.layout = self.pref('layout', LAYOUTS[0])
        if self.layout not in LAYOUTS: self.layout = LAYOUTS[0]
        self.separate = self.pref('separate', 'false') == 'true'
        self.verify = self.pref('verify', 'true') == 'true'
        self.sources = []
        self.files = []
        self.excluded = set()
        self.records = []
        self.warnings = []
        self.events = queue.Queue()
        self.cancel = threading.Event()
        self.busy = False
        self.scanning = False
        self.closing = False
        self.demo = demo
        self.progress = (0, 0, '')
        self.hits = []
        self.source_scroll = 0
        self.main_scroll = 0
        self.expanded_kinds = set()
        self.detail_pane = None
        self.hover = None
        self.dropping = False
        self.font_family = 'Microsoft YaHei UI' if os.name == 'nt' else 'PingFang SC'
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.poll)
        self.timer.start(60)
        self.device_timer = QTimer(self)
        self.device_timer.timeout.connect(self.check_devices)
        self.device_timer.start(4000)
        if demo: self.seed_demo()
        else: QTimer.singleShot(0, self.check_devices)

    def pref(self, key, default):
        return str(self.settings.value(key, default)) if self.settings else default

    def save_preferences(self):
        if self.settings:
            for key, value in dict(appearance=self.appearance, destination=str(self.destination), layout=self.layout,
                separate=str(self.separate).lower(), verify=str(self.verify).lower()).items():
                self.settings.setValue(key, value)

    def seed_demo(self):
        self.demo = True
        self.sources = [dict(path='E:\\', name='files / memories', enabled=True, device=True)]
        root = Path('E:/')
        self.files = [MediaFile(root / f'DCIM/{i:04d}.{ext}', root, Path(f'DCIM/{i:04d}.{ext}'), size, 1794153600000000000)
            for i, ext, size in [(1,'mp4',1842000000),(2,'mov',754000000),(3,'jpg',14200000),(4,'jpg',8700000),(5,'dng',42700000),(6,'wav',28400000)]]

    def palette(self):
        dark = self.appearance == 'dark'
        if self.appearance == 'system':
            dark = QApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark
        return DARK if dark else LIGHT

    def selected_files(self):
        roots = {str(Path(s['path']).resolve()) for s in self.sources if s['enabled']}
        if self.demo: roots = {str(f.root) for f in self.files}
        return [f for f in self.files if str(f.root) in roots and str(f.source) not in self.excluded]

    def active_files(self):
        roots = {str(Path(s['path']).resolve()) for s in self.sources if s['enabled']}
        if self.demo: return self.files
        return [f for f in self.files if str(f.root) in roots]

    def add_hit(self, key, rect, callback, enabled=True):
        if enabled: self.hits.append((key, QRectF(*rect), callback))

    def paintEvent(self, event):
        self.p = self.palette()
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        self.scale = min(self.width() / 1094, self.height() / 789)
        p.scale(self.scale, self.scale)
        self.W, self.H = self.width() / self.scale, self.height() / self.scale
        self.painter = p
        self.hits = []
        outline = QPainterPath()
        outline.addRoundedRect(QRectF(0, 0, self.W, self.H), 0 if self.isMaximized() else 16, 0 if self.isMaximized() else 16)
        p.setClipPath(outline)
        self.round(0, 0, self.W, self.H, 0, 'background')
        self.round(0, 0, 242, self.H, 0, 'sidebar')
        self.line(242, 28, 242, self.H, 'line')
        self.draw_titlebar()
        self.draw_sidebar()
        self.draw_main()
        self.draw_footer()
        p.end()

    def color(self, c): return QColor(self.p.get(c, c))

    def round(self, x, y, w, h, r=12, fill=None, stroke=None, dashed=False):
        p = self.painter
        p.setBrush(self.color(fill) if fill else Qt.BrushStyle.NoBrush)
        pen = QPen(self.color(stroke), 1) if stroke else QPen(Qt.PenStyle.NoPen)
        if dashed: pen.setStyle(Qt.PenStyle.DashLine); pen.setDashPattern([4, 4])
        p.setPen(pen)
        p.drawRoundedRect(QRectF(x, y, w, h), r, r)

    def line(self, x1, y1, x2, y2, color='line', width=1):
        self.painter.setPen(QPen(self.color(color), width))
        self.painter.drawLine(QPointF(x1,y1), QPointF(x2,y2))

    def text(self, x, y, w, h, text, size=12, color='ink', bold=False, align=Qt.AlignmentFlag.AlignLeft):
        f = QFont(self.font_family)
        f.setPixelSize(size); f.setWeight(QFont.Weight.DemiBold if bold else QFont.Weight.Normal)
        self.painter.setFont(f); self.painter.setPen(self.color(color))
        text = self.painter.fontMetrics().elidedText(str(text), Qt.TextElideMode.ElideMiddle, int(w))
        self.painter.drawText(QRectF(x,y,w,h), align | Qt.AlignmentFlag.AlignVCenter, text)

    def icon(self, name, x, y, size, color='accent'):
        p = self.painter
        p.save(); p.translate(x,y); p.scale(size/24, size/24)
        pen = QPen(self.color(color), 1.25, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
        p.setPen(pen); p.setBrush(Qt.BrushStyle.NoBrush)
        path = QPainterPath()
        if name == 'card':
            path.moveTo(7,2); path.lineTo(20,2); path.lineTo(20,22); path.lineTo(4,22); path.lineTo(4,6); path.closeSubpath(); p.drawPath(path)
            for xx in [12,14,16,18]: p.drawLine(QPointF(xx,4),QPointF(xx,8))
        elif name == 'folder':
            path.moveTo(2,6); path.lineTo(9,6); path.lineTo(11,8); path.lineTo(22,8); path.lineTo(22,21); path.lineTo(2,21); path.closeSubpath(); p.drawPath(path); p.drawLine(3,10,21,10)
        elif name == 'video':
            p.drawRoundedRect(QRectF(1,4,22,16),2,2)
            p.setBrush(self.color(color)); p.setPen(Qt.PenStyle.NoPen); p.drawPolygon(QPolygonF([QPointF(10,8),QPointF(17,12),QPointF(10,16)]))
        elif name == 'photo':
            p.drawRoundedRect(QRectF(1,3,22,18),2,2); p.drawEllipse(QPointF(7,8),1.8,1.8)
            p.setBrush(self.color(color)); p.setPen(Qt.PenStyle.NoPen); p.drawPolygon(QPolygonF([QPointF(2,19),QPointF(8,12),QPointF(12,16),QPointF(16,10),QPointF(23,18),QPointF(23,21),QPointF(2,21)]))
        elif name == 'raw':
            p.drawEllipse(QRectF(2,2,20,20))
            import math
            for i in range(6):
                a = i * math.pi / 3
                p.drawLine(QPointF(12+10*math.cos(a),12+10*math.sin(a)), QPointF(12+5*math.cos(a+1),12+5*math.sin(a+1)))
        elif name == 'audio':
            for xx,hh in [(3,6),(7,15),(11,22),(15,13),(19,17),(23,5)]: p.drawLine(QPointF(xx,12-hh/2),QPointF(xx,12+hh/2))
        elif name == 'file':
            path.moveTo(5,2); path.lineTo(14,2); path.lineTo(21,9); path.lineTo(21,23); path.lineTo(5,23); path.closeSubpath(); p.drawPath(path)
            p.drawLine(14,2,14,9); p.drawLine(14,9,21,9)
        elif name == 'refresh':
            p.drawArc(QRectF(4,5,16,16),35*16,-305*16); p.drawLine(20,4,20,10); p.drawLine(20,10,15,8)
        elif name == 'sun':
            import math
            p.drawEllipse(QRectF(8,8,8,8))
            for i in range(8):
                a=i*math.pi/4; p.drawLine(QPointF(12+7*math.cos(a),12+7*math.sin(a)),QPointF(12+10*math.cos(a),12+10*math.sin(a)))
        elif name == 'moon':
            path.moveTo(16,2); path.cubicTo(0,1,1,25,20,20); path.cubicTo(9,21,6,10,16,2); p.drawPath(path)
        elif name == 'system':
            p.drawEllipse(QRectF(3,3,18,18)); p.setBrush(self.color(color)); p.drawChord(QRectF(3,3,18,18),90*16,180*16)
        elif name == 'down': p.drawLine(8,10,12,14); p.drawLine(12,14,16,10)
        elif name == 'up': p.drawLine(8,14,12,10); p.drawLine(12,10,16,14)
        elif name == 'arrow': p.drawLine(3,12,21,12); p.drawLine(16,7,21,12); p.drawLine(16,17,21,12)
        elif name == 'up-right': p.drawLine(7,17,17,7); p.drawLine(9,7,17,7); p.drawLine(17,7,17,15)
        elif name == 'plus': p.drawLine(5,12,19,12); p.drawLine(12,5,12,19)
        elif name == 'close': p.drawLine(7,7,17,17); p.drawLine(17,7,7,17)
        elif name == 'path': p.drawLine(4,5,4,12); p.drawLine(4,12,19,12); p.drawLine(14,7,19,12); p.drawLine(14,17,19,12)
        p.restore()

    def checkbox(self, x, y, selected, enabled=True, mixed=False, small=False):
        size = 14 if small else 18
        self.round(x,y,size,size,4, 'accent' if selected else 'panel', 'accent' if selected else 'line')
        if selected:
            if mixed: self.line(x+4,y+size/2,x+size-4,y+size/2,'panel',1.7)
            else:
                self.line(x+4,y+size/2,x+size*.45,y+size-4,'panel',1.7); self.line(x+size*.45,y+size-4,x+size-3,y+4,'panel',1.7)

    def button(self, key, x,y,w,h,label,callback,enabled=True,accent=False):
        fill = 'button' if accent and enabled else ('#DEDBD7' if accent and self.p == LIGHT else ('line' if accent else 'selected'))
        self.round(x,y,w,h,12,fill)
        self.text(x+12,y,w-24,h,label,12,'onButton' if accent else 'ink',True,Qt.AlignmentFlag.AlignCenter)
        self.add_hit(key,(x,y,w,h),callback,enabled)

    def draw_titlebar(self):
        # Keep the content geometry identical; only window actions follow Windows conventions.
        for i, name in enumerate(['minimize','maximize','close-window']):
            x=self.W-108+i*36
            if self.hover == name: self.round(x,0,36,28,0, 'selected')
            if i == 0: self.line(x+13,15,x+23,15,'secondary')
            elif i == 1: self.round(x+14,9,9,9,0,None,'secondary')
            else: self.icon('close',x+10,5,18,'secondary')
            callback = self.showMinimized if i == 0 else (self.toggle_maximize if i == 1 else self.close)
            self.add_hit(name,(x,0,36,28),callback)

    def draw_sidebar(self):
        self.round(22,68,42,42,13,'panel'); self.icon('card',32,77,24)
        self.text(74,68,155,25,'OAnyImport',18,bold=True)
        self.text(74,95,150,16,'一点一滴，好好收藏',9,'secondary')
        self.text(23,145,57,20,'素材来源',11,'secondary',True)
        self.text(76,145,50,20,str(len(self.sources)),9,'faint')
        self.icon('refresh',195,147,16,'ink'); self.add_hit('refresh',(190,140,29,30),self.refresh,not self.busy)
        if not self.sources:
            self.round(13,178,216,158,16,None,'line',True)
            self.icon('card',106,203,32,'faint')
            self.text(25,249,192,25,'等待素材来源',12,bold=True,align=Qt.AlignmentFlag.AlignCenter)
            self.text(23,279,196,20,'连接存储卡、U 盘或硬盘',10,'secondary',align=Qt.AlignmentFlag.AlignCenter)
            self.text(23,297,196,20,'也可以添加一个素材文件夹',10,'secondary',align=Qt.AlignmentFlag.AlignCenter)
            self.add_hit('empty-add',(13,178,216,158),self.add_source,not self.busy)
        else:
            self.painter.save(); self.painter.setClipRect(QRectF(0,175,242,self.H-255))
            for i, source in enumerate(self.sources):
                y=178+i*144-self.source_scroll
                if y+134<175 or y>self.H-80: continue
                self.round(13,y,216,134,15,'panel' if source['enabled'] else 'sidebar','accent' if source['enabled'] else 'line')
                self.icon('card' if source['device'] else 'folder',28,y+15,24)
                self.checkbox(196,y+18,source['enabled'])
                self.text(28,y+52,180,23,source['name'],12,bold=True)
                count=sum(str(f.root)==str(Path(source['path']).resolve()) for f in self.files)
                if self.demo: count = len(self.files)
                self.text(28,y+77,180,17,'外接存储' if source['device'] else '素材文件夹',9,'secondary')
                self.text(28,y+105,120,17,'正在扫描…' if self.scanning else f'{count} 个文件',9,'secondary')
                self.text(174,y+104,35,18,'移除',10,'secondary')
                if y>=175:
                    self.add_hit(f'source-{i}',(13,y,216,100),lambda i=i:self.toggle_source(i),not self.busy)
                    self.add_hit(f'remove-{i}',(165,y+99,52,30),lambda i=i:self.remove_source(i),not self.busy)
            self.painter.restore()
        self.round(18,self.H-65,206,39,11,'panel')
        self.icon('plus',28,self.H-52,14,'ink')
        self.text(48,self.H-65,145,39,'添加素材文件夹',11)
        self.text(182,self.H-65,33,39,'Ctrl O',9,'faint',align=Qt.AlignmentFlag.AlignRight)
        self.add_hit('add',(18,self.H-65,206,39),self.add_source,not self.busy)

    def draw_main(self):
        x=276; w=self.W-x-34
        self.round(self.W-133,53,99,33,17,'sidebar')
        for i,(mode,icon) in enumerate([('light','sun'),('dark','moon'),('system','system')]):
            xx=self.W-129+31*i
            if self.appearance==mode: self.round(xx,57,29,25,13,'panel')
            self.icon(icon,xx+6,61,17,'ink' if self.appearance==mode else 'secondary')
            self.add_hit('theme-'+mode,(xx,57,29,25),lambda mode=mode:self.change_theme(mode))
        files=self.active_files(); selected={str(f.source) for f in self.selected_files()}
        groups={kind:[f for f in files if f.kind==kind] for kind in KINDS}
        extensions={kind:sorted({f.source.suffix.lower() for f in groups[kind]}) for kind in KINDS}
        extras={kind:(len(extensions[kind])*30+12 if kind in self.expanded_kinds and groups[kind] else 0) for kind in KINDS}
        extra=sum(extras.values())
        self.main_scroll=max(0,min(self.main_scroll,max(0,685+extra-(self.H-95))))
        offset=-self.main_scroll
        viewport=QRectF(x-2,102,w+4,self.H-197)
        first_hit=len(self.hits)
        self.painter.save(); self.painter.setClipRect(viewport,Qt.ClipOperation.IntersectClip)
        self.text(x,108+offset,18,24,'01',10,'faint')
        self.text(x+22,108+offset,250,24,'想带回哪些素材？',14,bold=True)
        self.text(x+w-230,108+offset,230,24,'按类型选择 · 详情里看预览',10,'secondary',align=Qt.AlignmentFlag.AlignRight)
        self.round(x,140+offset,w,300+extra,20,'panel','line')
        y=140+offset
        for i,kind in enumerate(KINDS):
            group=groups[kind]
            included=sum(str(f.source) in selected for f in group)
            if i: self.line(x+66,y,x+w,y)
            self.checkbox(x+18,y+21,included>0,mixed=0<included<len(group))
            self.round(x+49,y+12,35,35,10,'background')
            self.icon(SYMBOLS[i],x+56,y+19,22,'accent' if group else 'faint')
            self.text(x+97,y+12,w-300,23,kind,12,'ink' if group else 'faint',True)
            exts=sorted({f.source.suffix.upper().lstrip('.') or '无扩展名' for f in group})
            sub=' / '.join(exts) if exts else ('未发现此类文件' if self.sources else '等待选择素材来源')
            self.text(x+97,y+34,w-300,18,sub,9,'secondary' if group else 'faint')
            self.text(x+w-155,y+12,55,23,f'{len(group)} 个',11,align=Qt.AlignmentFlag.AlignRight)
            self.text(x+w-155,y+34,55,18,byte_string(sum(f.size for f in group)),9,'secondary',align=Qt.AlignmentFlag.AlignRight)
            self.icon('up' if kind in self.expanded_kinds else 'down',x+w-87,y+25,14,'faint')
            self.text(x+w-56,y+17,29,26,'详情',10,'secondary' if group else 'faint')
            self.icon('up-right',x+w-26,y+26,11,'faint')
            self.add_hit('kind-'+kind,(x+10,y+5,w-185,50),lambda kind=kind:self.toggle_kind(kind),bool(group) and not self.busy)
            self.add_hit('ext-'+kind,(x+w-94,y+14,30,33),lambda kind=kind:self.extension_menu(kind),bool(group) and not self.busy)
            self.add_hit('detail-'+kind,(x+w-64,y+10,58,40),lambda kind=kind:self.details(kind),bool(group))
            if extras[kind]:
                for j,ext in enumerate(extensions[kind]):
                    ey=y+60+j*30
                    subset=[f for f in group if f.source.suffix.lower()==ext]
                    chosen=sum(str(f.source) in selected for f in subset)
                    self.checkbox(x+66,ey+6,chosen>0,small=True,mixed=0<chosen<len(subset))
                    self.text(x+91,ey,w-270,26,ext or '无扩展名',11)
                    self.text(x+w-240,ey,160,26,f'{len(subset)} 个 · {byte_string(sum(f.size for f in subset))}',10,'secondary',align=Qt.AlignmentFlag.AlignRight)
                    self.add_hit('extension-'+kind+'-'+ext,(x+60,ey,w-120,28),lambda subset=subset:self.select_group(subset,not all(str(f.source) not in self.excluded for f in subset)),not self.busy)
            y+=60+extras[kind]
        destination_offset=offset+extra
        self.text(x,460+destination_offset,18,24,'02',10,'faint')
        self.text(x+22,460+destination_offset,250,24,'给素材一个新家',14,bold=True)
        self.text(x+w-230,460+destination_offset,230,24,'仅复制，保留卡内原文件',10,'secondary',align=Qt.AlignmentFlag.AlignRight)
        self.round(x,494+destination_offset,w,161,20,'panel','accent' if self.dropping else 'line')
        self.round(x+18,512+destination_offset,44,44,12,'selected'); self.icon('folder',x+27,523+destination_offset,26)
        self.text(x+75,512+destination_offset,w-205,25,self.destination.name or str(self.destination),13,bold=True)
        path=str(self.destination).replace(str(Path.home()), '~')
        self.text(x+75,537+destination_offset,w-205,17,path,10,'secondary')
        self.button('choose-dest',x+w-103,518+destination_offset,85,33,'更改位置…',self.choose_destination,not self.busy)
        self.line(x+18,573+destination_offset,x+w-18,573+destination_offset)
        self.text(x+18,586+destination_offset,48,26,'整理方式',11,'secondary')
        self.round(x+70,591+destination_offset,142,19,5,'background','line')
        self.text(x+77,589+destination_offset,120,23,self.layout,11)
        self.icon('down',x+194,594+destination_offset,12)
        self.add_hit('layout',(x+70,585+destination_offset,142,33),self.layout_menu,not self.busy)
        self.checkbox(x+w-197,592+destination_offset,self.separate,small=True)
        self.text(x+w-178,585+destination_offset,88,29,'按卡分文件夹',11)
        self.add_hit('separate',(x+w-200,585+destination_offset,105,30),self.toggle_separate,not self.busy)
        self.checkbox(x+w-92,592+destination_offset,self.verify,small=True)
        self.text(x+w-73,585+destination_offset,64,29,'导入后校验',11)
        self.add_hit('verify',(x+w-95,585+destination_offset,87,30),self.toggle_verify,not self.busy)
        self.icon('path',x+18,624+destination_offset,13,'faint')
        day=datetime.now().strftime('%Y-%m-%d')
        parts = (['视频',day] if self.layout==LAYOUTS[0] else [day,'视频']) if self.layout != LAYOUTS[2] else ['DCIM','100MEDIA']
        example=' / '.join([self.destination.name]+(['卡片名'] if self.separate else [])+parts+['C0001.MP4'])
        self.text(x+36,620+destination_offset,w-54,22,example,10,'faint')
        if self.warnings:
            self.text(x,661+destination_offset,w,23,f'{len(self.warnings)} 项扫描提示 · 点击查看',10,'secondary')
            self.add_hit('warnings',(x,657+destination_offset,w,30),lambda:QMessageBox.information(self,'扫描提示','\n\n'.join(self.warnings)))

        self.painter.restore()
        self.hits=self.hits[:first_hit]+[(key,rect.intersected(viewport),callback) for key,rect,callback in self.hits[first_hit:] if rect.intersects(viewport)]

    def draw_footer(self):
        y=self.H-85; x=276; w=self.W-x-34
        self.round(243,y,self.W-243,85,0,'panel'); self.line(243,y,self.W,y)
        if self.busy and not self.scanning:
            done,total,name=self.progress
            self.text(x,y+13,w-120,23,f'正在导入素材    {done} / {total}',12,bold=True)
            self.round(x,y+45,w-130,3,1.5,'line')
            self.round(x,y+45,(w-130)*done/max(total,1),3,1.5,'accent')
            self.text(x,y+53,w-120,20,name or '准备导入…',10,'secondary')
            self.button('cancel',self.W-125,y+23,91,39,'取消导入',self.cancel.set)
        else:
            files=self.selected_files()
            self.text(x,y+20,400,25,'正在清点素材…' if self.scanning else f'{len(files)} 个文件  ·  {byte_string(sum(f.size for f in files))}',14,bold=True)
            hint='先在左侧选择存储设备，也可以添加素材文件夹' if not self.sources else '相同内容自动跳过，同名不同内容保留两份'
            if self.demo: hint='设计预览模式 · 不会读取或导入真实文件'
            self.text(x,y+46,w-150,20,hint,10,'secondary')
            if self.records:
                self.text(self.W-235,y+30,68,27,'上次结果',11,'secondary')
                self.add_hit('last-report',(self.W-235,y+20,68,45),self.report)
            self.button('start',self.W-160,y+21,126,44,'开始导入    →',self.start_import,bool(files) and not self.busy and not self.demo,True)

    def mousePressEvent(self,event):
        if event.button()!=Qt.MouseButton.LeftButton: return
        point=event.position()/self.scale
        for _,rect,callback in reversed(self.hits):
            if rect.contains(point): callback(); self.update(); return
        margin=5
        edges=Qt.Edge(0)
        if event.position().x()<margin: edges|=Qt.Edge.LeftEdge
        if event.position().x()>self.width()-margin: edges|=Qt.Edge.RightEdge
        if event.position().y()<margin: edges|=Qt.Edge.TopEdge
        if event.position().y()>self.height()-margin: edges|=Qt.Edge.BottomEdge
        if edges: self.windowHandle().startSystemResize(edges)
        elif point.y()<40: self.windowHandle().startSystemMove()

    def mouseMoveEvent(self,event):
        point=event.position()/self.scale
        key=next((key for key,rect,_ in reversed(self.hits) if rect.contains(point)),None)
        self.setCursor(Qt.CursorShape.PointingHandCursor if key else Qt.CursorShape.ArrowCursor)
        if key!=self.hover: self.hover=key; self.update()

    def mouseDoubleClickEvent(self,event):
        if event.position().y()<35*self.scale: self.toggle_maximize()

    def toggle_maximize(self): self.showNormal() if self.isMaximized() else self.showMaximized()

    def wheelEvent(self,event):
        if event.position().x()<242*self.scale:
            self.source_scroll=max(0,min(max(0,len(self.sources)*144-(self.H-255)),self.source_scroll-event.angleDelta().y()/2))
            self.update()
        elif event.position().y()>102*self.scale and event.position().y()<self.height()-85*self.scale:
            self.main_scroll=max(0,self.main_scroll-event.angleDelta().y()/2); self.update()

    def keyPressEvent(self,event):
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            if event.key()==Qt.Key.Key_O: self.add_source()
            elif event.key() in (Qt.Key.Key_I,Qt.Key.Key_Return): self.start_import()
        elif event.key()==Qt.Key.Key_Escape:
            if self.detail_pane: self.close_details()
            elif self.isMaximized(): self.showNormal()

    def dragEnterEvent(self,event):
        if event.mimeData().hasUrls() and not self.busy:
            self.dropping=True; self.update(); event.acceptProposedAction()

    def dragLeaveEvent(self,event): self.dropping=False; self.update()

    def dropEvent(self,event):
        self.dropping=False
        paths=[Path(url.toLocalFile()) for url in event.mimeData().urls()]
        if paths and paths[0].is_dir():
            if event.position().x()>242*self.scale:
                self.destination=paths[0]; self.save_preferences()
            else: self.add_path(paths[0])
        self.update()

    def change_theme(self,value):
        self.appearance=value; self.save_preferences(); self.update()
        if self.detail_pane: self.detail_pane.apply_theme()
    def toggle_separate(self): self.separate=not self.separate; self.save_preferences(); self.update()
    def toggle_verify(self): self.verify=not self.verify; self.save_preferences(); self.update()

    def menu_style(self, widget):
        p=self.palette()
        widget.setStyleSheet(f"QWidget {{background:{p['panel']};color:{p['ink']};font-size:12px;}} QMenu {{padding:8px;border:1px solid {p['line']};}} QMenu::item {{padding:8px 18px;}} QMenu::item:selected {{background:{p['selected']};}} QPushButton {{background:{p['selected']};border:1px solid {p['line']};border-radius:8px;padding:8px 14px;}} QTreeWidget {{border:1px solid {p['line']};border-radius:10px;}} QHeaderView::section {{background:{p['sidebar']};padding:10px;border:none;}} QTreeWidget::item {{padding:5px;}}")

    def layout_menu(self):
        menu=QMenu(self); self.menu_style(menu)
        for layout in LAYOUTS:
            action=menu.addAction(layout); action.setCheckable(True); action.setChecked(self.layout==layout)
            action.triggered.connect(lambda checked=False,layout=layout:self.set_layout(layout))
        menu.exec(self.cursor().pos())

    def set_layout(self,value): self.layout=value; self.save_preferences(); self.update()

    def extension_menu(self,kind):
        if kind in self.expanded_kinds: self.expanded_kinds.remove(kind)
        else: self.expanded_kinds.add(kind)
        self.update()

    def select_group(self,files,selected):
        for f in files:
            if selected: self.excluded.discard(str(f.source))
            else: self.excluded.add(str(f.source))
        self.update()
        if self.detail_pane: self.detail_pane.refresh_selection()

    def toggle_kind(self,kind):
        files=[f for f in self.active_files() if f.kind==kind]
        self.select_group(files,not all(str(f.source) not in self.excluded for f in files))

    def check_devices(self):
        if self.busy or self.demo: return
        current=devices(); paths={root for root,_ in current}
        retained=[s for s in self.sources if not s['device'] or s['path'] in paths]
        known={s['path'] for s in retained}
        retained.extend(dict(path=root,name=name,enabled=True,device=True) for root,name in current if root not in known)
        if retained!=self.sources: self.sources=retained; self.rescan()

    def refresh(self):
        if self.busy or self.demo: return
        self.check_devices()
        if not self.busy: self.rescan()

    def add_source(self):
        if self.busy or self.demo: return
        path=QFileDialog.getExistingDirectory(self,'选择存储设备或素材文件夹')
        if path: self.add_path(Path(path))

    def add_path(self,path):
        if self.busy or self.demo: return
        path=path.resolve()
        if any(Path(s['path']).resolve()==path for s in self.sources): return
        self.sources.append(dict(path=str(path),name=path.name or str(path),enabled=True,device=False)); self.rescan()

    def remove_source(self,index):
        if self.busy: return
        del self.sources[index]; self.source_scroll=0; self.rescan()

    def toggle_source(self,index):
        if self.busy: return
        self.sources[index]['enabled']=not self.sources[index]['enabled']; self.update()
        if self.detail_pane: self.detail_pane.reset_list()

    def choose_destination(self):
        if self.busy: return
        path=QFileDialog.getExistingDirectory(self,'选择素材的新家',str(self.destination))
        if path: self.destination=Path(path); self.save_preferences(); self.update()

    def rescan(self):
        if self.busy: return
        self.busy=True; self.scanning=True
        roots=[s['path'] for s in self.sources]
        def work():
            found={}; warnings=[]
            for root in roots:
                try:
                    files,issues=scan(Path(root)); warnings.extend(issues)
                    for f in files: found[str(f.source)]=f
                except (OSError,ValueError) as exc: warnings.append(str(exc))
            self.events.put(('scan',list(found.values()),warnings))
        threading.Thread(target=work,daemon=True).start(); self.update()

    def start_import(self):
        if self.busy or self.demo: return
        files=self.selected_files()
        if not files: return
        dest=self.destination.expanduser().resolve()
        try:
            if any(dest==f.root or f.root in dest.parents for f in files): raise ValueError('保存位置不能位于来源目录内')
            if dest==Path(__file__).resolve().parent or Path(__file__).resolve().parent in dest.parents: raise ValueError('请将素材保存到软件安装目录以外的位置')
            dest.mkdir(parents=True,exist_ok=True); validate(files,dest)
            if shutil.disk_usage(dest).free<sum(f.size for f in files): raise ValueError('目标磁盘空间不足，请更改保存位置或减少所选文件')
        except (OSError,ValueError) as exc: QMessageBox.warning(self,'暂时无法继续',str(exc)); return
        self.busy=True; self.cancel.clear(); self.progress=(0,len(files),'准备导入…')
        layout,separate,verify=self.layout,self.separate,self.verify
        def progress(done,total,name): self.events.put(('progress',done,total,name))
        def work():
            try:
                records=import_files(files,dest,layout,separate,verify,self.cancel,progress)
                self.events.put(('done',records,self.cancel.is_set(),len(files)))
            except Exception as exc: self.events.put(('error',str(exc)))
        threading.Thread(target=work,daemon=True).start(); self.update()

    def poll(self):
        changed=False
        try:
            while True:
                e=self.events.get_nowait(); changed=True
                if e[0]=='scan': self.files=e[1]; self.warnings=e[2]; self.busy=False; self.scanning=False
                elif e[0]=='progress': self.progress=e[1:]
                elif e[0]=='done':
                    self.busy=False; self.records=e[1]; self.cancelled=e[2]; self.unprocessed=e[3]-len(e[1])
                    if not self.closing: self.report()
                elif e[0]=='error':
                    self.busy=False
                    if not self.closing: QMessageBox.warning(self,'暂时无法继续',e[1])
        except queue.Empty: pass
        if changed:
            self.update()
            if self.detail_pane:
                if e[0]=='scan': self.detail_pane.reset_list()
                else: self.detail_pane.refresh_selection()
        if self.closing and not self.busy: self.close()

    def details(self,kind):
        from media_browser import DetailPane
        self.close_details()
        self.detail_pane=DetailPane(self,kind,getattr(self,'scale',1))
        self.position_details(); self.detail_pane.show(); self.detail_pane.raise_()
        QTimer.singleShot(0,self.detail_pane.load_visible)

    def position_details(self):
        if not self.detail_pane: return
        scale=min(self.width()/1094,self.height()/789)
        width=round(390*scale); top=round(28*scale)
        self.detail_pane.setGeometry(self.width()-width,top,width,self.height()-top)

    def resizeEvent(self,event):
        if getattr(self,'detail_pane',None): self.position_details()
        super().resizeEvent(event)

    def close_details(self):
        if self.detail_pane:
            self.detail_pane.shutdown(); self.detail_pane.hide(); self.detail_pane.deleteLater(); self.detail_pane=None
        self.update()

    def report(self):
        if not self.records: return
        dialog=QDialog(self); dialog.setWindowTitle('导入结果'); dialog.resize(650,460); self.menu_style(dialog)
        layout=QVBoxLayout(dialog); layout.setContentsMargins(24,24,24,24); layout.setSpacing(18)
        count=Counter(r['outcome'] for r in self.records)
        layout.addWidget(QLabel(f"已导入 {count['copied']}   ·   已跳过 {count['skipped']}   ·   失败 {count['failed']}"))
        if getattr(self,'cancelled',False): layout.addWidget(QLabel(f'已取消，未处理 {self.unprocessed} 个文件。已完成文件已保留。'))
        tree=QTreeWidget(); tree.setHeaderLabels(['文件','结果']); tree.setColumnWidth(0,440)
        titles=dict(copied='已导入',skipped='相同内容已跳过',failed='导入失败')
        for r in self.records:
            item=QTreeWidgetItem([Path(r['source']).name,titles[r['outcome']]])
            item.setToolTip(0,r.get('message') or r.get('destination') or r['source']); tree.addTopLevelItem(item)
        layout.addWidget(tree); buttons=QHBoxLayout()
        export=QPushButton('导出 JSON 记录'); export.clicked.connect(self.export_report); buttons.addWidget(export); buttons.addStretch()
        done=QPushButton('完成'); done.clicked.connect(dialog.accept); buttons.addWidget(done); layout.addLayout(buttons); dialog.exec()

    def export_report(self):
        path,_=QFileDialog.getSaveFileName(self,'导出导入记录','OAnyImport-result.json','JSON (*.json)')
        if path:
            try: Path(path).write_text(json.dumps(dict(exportedAt=datetime.now().isoformat(),records=self.records),ensure_ascii=False,indent=2),encoding='utf-8')
            except OSError as exc: QMessageBox.warning(self,'导出失败',str(exc))

    def closeEvent(self,event):
        if self.busy:
            self.closing=True; self.cancel.set(); event.ignore()
        else: self.close_details(); self.save_preferences(); event.accept()


def main():
    app=QApplication.instance() or QApplication(sys.argv)
    app.setApplicationName('OAnyImport'); app.setOrganizationName('OAnyImport')
    window=App(demo='--demo' in sys.argv)
    window.show()
    return app.exec()

if __name__=='__main__': sys.exit(main())
