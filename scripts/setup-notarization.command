#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="OAnyImort-notary"
TEAM_ID="${APPLE_TEAM_ID:-TQ3H9RKZW9}"
print 'OAnyImort · Apple 公证配置'
print ''
print '1. 在 account.apple.com 登录你的 Apple 开发者账号。'
print '2. 在「登录与安全 → App 专用密码」生成一个名为 OAnyImort 的密码。'
print '3. 在下面输入账号邮箱；随后 Apple 的命令行工具会隐藏输入专用密码。'
print '请勿输入 Apple 账号的日常登录密码，也不要把密码发到聊天中。'
print ''
read 'apple_account?Apple 开发者账号邮箱：'
if [[ -z "$apple_account" ]]; then
    print '未输入账号，配置已取消。'
    exit 1
fi
xcrun notarytool store-credentials "$PROFILE" --apple-id "$apple_account" --team-id "$TEAM_ID"
mkdir -p "$PROJECT_ROOT/.release-work"
print -r -- "$PROFILE" > "$PROJECT_ROOT/.release-work/notary-profile-ready.txt"
print ''
print '配置已保存到本机钥匙串。回到 Codex 回复「已配置公证」，即可继续提交和验证。'
read '?按回车关闭窗口。'
