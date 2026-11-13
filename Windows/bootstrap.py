"""Packaged entry point. Report startup failures even without a console."""
import os
import sys
import traceback
from pathlib import Path

try:
    if os.name == 'nt':
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID('OAnyImport.Desktop')
    from app import main
    sys.exit(main())
except Exception:
    details = traceback.format_exc()
    log_dir = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'OAnyImport' / 'logs'
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / 'startup.log').write_text(details, encoding='utf-8')
        message = f'OAnyImport 启动失败。错误信息已保存到：\n{log_dir / "startup.log"}'
    except OSError:
        message = f'OAnyImport 启动失败：\n{details}'
    if os.name == 'nt':
        import ctypes
        ctypes.windll.user32.MessageBoxW(None, message, 'OAnyImport', 0x10)
    else:
        print(details, file=sys.stderr)
    sys.exit(1)
