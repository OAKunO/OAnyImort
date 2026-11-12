# OAnyImort

一个安静的本地素材导入与归档工具，支持 macOS 和 Windows。存储卡、U 盘、移动硬盘和普通文件夹，都可以作为来源。奶油白 / 暖夜黑 / 跟随系统，所有素材处理均在本机完成。

## 打开 App

从 [产品页](https://oakuno.com/project/oanyimort) 下载对应安装包，无需安装开发环境。

- **macOS 14+**：下载通用版 ZIP，解压后将 `OAnyImort.app` 拖到 Applications，支持 Apple silicon 和 Intel。下载版已通过 Developer ID 签名、Apple 公证、公证票据和 Gatekeeper 检查。
- **Windows 10 / 11 x64**：直接下载 Setup.exe 安装；Python、Qt 和媒体组件均已包含，无需额外下载。当前未配置受信任的 Windows 代码签名证书，系统可能提示未知发布者。

网站：[oakuno.com/project/oanyimort](https://oakuno.com/project/oanyimort)。

以下为 macOS 操作；Windows 操作与差异见 [Windows/README.md](Windows/README.md)。

1. 连接存储卡、U 盘或硬盘，在左侧勾选一个或多个来源。也可按 `⌘O` 添加素材文件夹。
2. 选择视频、图片、RAW、音频或其他文件；下拉箭头可细分文件格式。
3. 点击「详情」查看文件并用方框逐个选择；点击缩略图可使用系统 Quick Look 预览。格式支持取决于 macOS 已安装的解码器与预览扩展。
4. 选择保存位置，设置归档方式，点击「开始导入」（`⌘I`）。

默认保存到 `~/Documents/视频素材`，可更改位置或拖入目标文件夹。支持「类型 / 日期」「日期 / 类型」「保留原目录」，可按来源卡建立子文件夹。日期优先读取照片 EXIF 或视频元数据，之后尝试文件名日期，最后回退到文件创建 / 修改日期。

## 文件处理

- 默认只读取来源文件，不删除、不移动、不格式化 SD 卡。成功导入后，可在结果页面选择卡片并确认删除已导入的原文件，或选择格式化整张卡。
- 删除前会重新比较原文件与电脑副本的 SHA-256；身份无法确认或内容变化的文件不会删除。格式化需要滑动和再次确认，会清空卡上所有分区和文件，并创建名为 OANYIMORT 的 ExFAT 卷。
- 同一目标位置的同名文件比较 SHA-256；内容相同跳过，不同则添加序号，绝不覆盖。
- 复制过程中写入隐藏的临时文件，完成后再移动到正式名称。
- 默认开启 SHA-256 目标校验，并保留文件创建 / 修改日期。
- 取消或失败会清理本次未完成的临时副本，已成功导入的文件保留。
- 结果窗口可查看、导出 JSON 记录，并仅重试失败或未完成项。
- 扫描忽略隐藏文件、符号链接和软件包内部。文件数统计不包含这些内容。
- 外接设备通过 macOS 卷信息检测；USB 磁盘也可作为来源。手动添加的文件夹只保留在本次会话中。
- 目标位置与归档 / 校验 / 主题选项通过本机 UserDefaults 记忆。

## 开发与构建

项目采用 SwiftUI + AppKit，核心扫描、分类、导入逻辑放在独立的 `OAnyImortCore` 模块，无第三方依赖。

```sh
zsh scripts/test.sh
zsh scripts/build.sh
open dist/OAnyImort.app
```

可使用 Xcode 打开 `Package.swift`。开发构建默认使用 ad-hoc 签名。`UNIVERSAL=1` 可构建 Apple silicon + Intel 通用版；`CODE_SIGN_IDENTITY` 可指定本机钥匙串中的 Developer ID 签名身份。

本次正式分发复用了 Xcode 已登录的开发者账号，通过 Developer ID / Direct Distribution 提交 Apple 公证，再使用 `xcodebuild -exportNotarizedApp` 导出。此路径不需要新建 App 专用密码。

维护者若已有 notarytool 钥匙串配置，也可使用以下自动化脚本；普通下载用户不需要执行：

```sh
CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARY_PROFILE="your-existing-profile" zsh scripts/release-macos.sh
```

等待公证时应复查同一提交，不重复上传。当前公开下载提供已公证并带票据的 ZIP。

图标源代码位于 `scripts/make-icon.swift`，可用以下命令重新生成：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift scripts/make-icon.swift "$PWD"
```

`--demo` 启动参数仅展示模拟卡片与统计，会禁用导入操作；正常启动读取真实设备。任何系统磁盘 / 文件夹访问提示均由 macOS 管理。

## 验证

核心测试覆盖：格式识别、隐藏文件与符号链接过滤、目录保留、重复跳过、同名冲突、多卡同名隔离、危险目标与越界路径拒绝、文件变化检测、文件名日期、取消清理和校验失败清理。

2026-11-12：16 项 macOS 核心测试、11 项 Windows 同源核心 / Qt 界面 / 真实媒体解码测试通过。通用版的 arm64 和 x86_64 可执行文件均检查为最低 macOS 14.0，Developer ID、Hardened Runtime、安全时间戳、Apple 公证票据和 Gatekeeper 均已验证。Windows 安装包在 Mac 上交叉构建，Windows 实机安装尚未验证。

## 改名与许可

OAnyImort 1.1.0 将应用、模块、安装包和界面名称统一。首次运行会读取旧版设置，保留保存位置和外观等偏好。旧名称只用于设置迁移。

源码采用 [MIT License](LICENSE)。Windows 随附组件按各自的开源许可证分发，详见 [第三方声明](Windows/THIRD_PARTY_NOTICES.txt)。

## Code signing policy

- 作者、代码审阅与发布负责人：OAKunO。
- macOS 下载版使用维护者的 Developer ID Application 证书签名，并通过 Apple 公证。默认发布流程复用 Xcode 账号。`scripts/setup-notarization.command` 仅供需要 notarytool 自动化的维护者选用，普通用户不需要运行。
- Windows 当前安装包未签名。正在准备申请免费开源签名服务，尚未提交或获批；不会把未签名包标为已签名。`.github/workflows/windows-build.yml` 提供可追溯的 Windows 原生构建，尚待 GitHub 发布后实际运行验证。
- 应用只在本机处理所选文件，不主动上传用户文件或使用数据；复制到网络存储仅在用户主动选择该位置时进行。
- 签名只用于本项目自有的可执行文件与安装包；随附的 Python、Qt、FFmpeg 等第三方组件保留各自来源和许可证。
