# OAnyImort Windows 版

## 安装

直接下载 [产品页](https://oakuno.com/project/oanyimort) 中的 `OAnyImort-Setup-1.1.0-x64.exe` 安装，或解压 ZIP 后运行 Setup.exe。先关闭旧版应用。支持 Windows 10 / 11 x64，自带 Python、Qt 和视频播放运行库。默认安装到当前用户的 `%LOCALAPPDATA%\Programs\OAnyImort`。

## 1.1.0 更新

应用、安装包、快捷方式与日志统一更名，并在首次运行时迁移旧版偏好设置。

## 现有界面功能

- 详情为主窗口右侧的浏览区：缩略图卡片、搜索、来源筛选、逐文件勾选。
- 点击封面在右侧播放视频或预览图片，支持播放/暂停、进度拖动和静音。
- 格式选项在分类卡片内展开，显示勾选框、格式、文件数与大小。
- LRV 调整到“其他文件”，与 Mac 版一致。

视频预览由 Qt Multimedia 提供，在本机解码。缩略图只加载可见卡片；不支持的编码会显示提示，不影响选择导入。单次先显示六张卡片，可展开全部并按需加载。关闭详情或返回列表会停止播放并释放文件。预览不修改来源文件。

界面颜色和布局来自 macOS 版的 `Theme.swift`、`ContentView.swift` 和 `DetailView.swift`。安装包在 macOS 交叉构建，`test-evidence` 是同一代码在本机的实际渲染与测试素材，不是 Windows 实机截图。Windows 上的安装、解码和系统字体仍需实机验证。安装包尚未签名。

现有导入功能包括类型/格式/文件选择、三种归档方式、同名去重和重命名、SHA-256 校验、取消与 JSON 结果导出。源文件只读。尚不包含 EXIF/视频元数据日期、失败项重试、源文件删除及格式化。

## 开发与构建

需要 Python 3.10+ 和 NSIS。固定依赖版本为 Qt for Python 6.8.3。

1. 下载 [WinPython 运行环境](https://sourceforge.net/projects/winpython/files/WinPython_3.13/3.13.18.0/WinPython64-3.13.18.0dot.zip/download) 到 `.downloads/winpython.zip`。
2. 下载 Windows Qt 库：

```sh
python -m pip download --only-binary=:all: --platform win_amd64 --python-version 313 --implementation cp --abi abi3 --dest .downloads/qt PySide6-Essentials==6.8.3 PySide6-Addons==6.8.3
```

3. 执行 `python build_installer.py --makensis /path/to/makensis`。脚本核对 SHA-256，只从 Addons 中提取多媒体和解码所需组件。许可证随安装目录和 ZIP 提供。

源码运行：安装同版本的 Essentials 与 Addons，执行 `python app.py`。运行测试：`python -m unittest discover -p 'test_*.py' -v`。媒体测试使用 `test-evidence/media/20261109-preview.mp4`，通过真实解码检查封面、播放、暂停、进度和释放。
