# Claude Code MiMo / DeepSeek Installer

一键安装 Claude Code，并把 Claude Code 配置为使用 Xiaomi MiMo 或 DeepSeek 的 Anthropic-compatible API。

脚本不会把你的 API key 提交、发布或上传到 GitHub。安装时可以交互式输入，也可以通过环境变量传入。

API key 会保存在你本机的 `~/.claude/provider-switch.json`。MiMo 和 DeepSeek 会各自保留一份；切换 provider 时，脚本会把当前 provider 的 key 写入 Claude Code 实际读取的 `~/.claude/settings.json`。

## macOS / Linux 一键部署

macOS / Linux 会优先使用 Claude Code 官方 native installer，不需要提前安装 Node.js 或 npm。若 `https://claude.ai/install.sh` 被网络或地区策略拦截，脚本会在本机已有 `npm` 时自动回退到 `npm install -g @anthropic-ai/claude-code`。配置文件写入优先使用系统自带的 `python3`，没有 `python3` 时会尝试使用 `node`。

Release 一键安装：

```bash
curl -fsSL https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/install.sh | bash
```

非交互式 Release 安装：

```bash
curl -fsSL https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/install.sh | MIMO_API_KEY="<your-mimo-api-key>" DEEPSEEK_API_KEY="<your-deepseek-api-key>" bash
```

交互式安装：

```bash
./install.sh
```

非交互式安装：

```bash
MIMO_API_KEY="<your-mimo-api-key>" ./install.sh
```

同时保存 DeepSeek key，之后可直接切换：

```bash
MIMO_API_KEY="<your-mimo-api-key>" DEEPSEEK_API_KEY="<your-deepseek-api-key>" ./install.sh
```

指定模型：

```bash
MIMO_API_KEY="<your-mimo-api-key>" MIMO_MODEL="mimo-v2.5-pro" ./install.sh
```

只安装 Claude Code 和切换工具，暂不写入 API key：

```bash
./install.sh --skip-api-key
```

如果 Linux 上出现 `curl: (22) The requested URL returned error: 403`，这是访问 Claude 官方安装脚本被拒。新版脚本会自动尝试 npm 兜底；如果你的机器没有 npm，会尝试通过 `apt-get`、`dnf`、`yum` 或 `apk` 自动安装 Node.js/npm 后继续。若系统没有这些包管理器或当前用户没有安装权限，再手动安装 Node.js/npm 后重试，或换一个能访问 `https://claude.ai/install.sh` 的网络环境。

如果系统自带 Node.js 版本太旧，例如 Node v12，或者全局 npm 目录没有权限，脚本会自动下载 Node.js 22 到 `~/.local/share/claude-code-mimo/node`，并用 `~/.local` 作为 npm 全局安装目录，避免写入 `/usr/local/lib/node_modules`。

## Windows 一键部署

Windows 会优先使用 Claude Code 官方 native installer，不需要提前安装 Node.js 或 npm。如果官方下载 native binary 时被网络中断，脚本会在检测到本机已有 npm 时自动 fallback 到 `npm install -g @anthropic-ai/claude-code --include=optional`，并验证 `claude --version` 是否真的可运行。

PowerShell Release 一键安装：

```powershell
irm https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/install.ps1 | iex
```

PowerShell 非交互式 Release 安装：

```powershell
$env:MIMO_API_KEY="<your-mimo-api-key>"
$env:DEEPSEEK_API_KEY="<your-deepseek-api-key>"
irm https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/install.ps1 | iex
```

PowerShell 交互式安装：

```powershell
.\install.ps1
```

PowerShell 非交互式安装：

```powershell
$env:MIMO_API_KEY="<your-mimo-api-key>"
.\install.ps1
```

同时保存 DeepSeek key：

```powershell
$env:MIMO_API_KEY="<your-mimo-api-key>"
$env:DEEPSEEK_API_KEY="<your-deepseek-api-key>"
.\install.ps1
```

也可以用 CMD：

```bat
set MIMO_API_KEY=<your-mimo-api-key>
set DEEPSEEK_API_KEY=<your-deepseek-api-key>
install.bat
```

如果 PowerShell 执行策略阻止脚本，可以临时允许当前进程执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

如果运行 `claude` 提示“16 位程序不能运行”或“The specified executable is not a valid application for this OS platform”，通常是 npm 全局安装留下了错误、占位或下载不完整的 Windows 入口。新版安装脚本会自动检测 `claude --version`，并在需要时重新下载官方 `@anthropic-ai/claude-code-win32-*` 原生包修复入口。

也可以先在 PowerShell 或 CMD 里清理旧包：

```powershell
npm uninstall -g @anthropic-ai/claude-code
```

如果没有 npm 或卸载失败，可以跳过清理步骤，然后重新运行本安装脚本。安装后重新打开终端，再执行：

```powershell
claude --version
claude
```

如果提示“无法将 claude 识别为 cmdlet、函数、脚本文件或可运行程序的名称”，说明 Claude Code 已安装但当前终端的 PATH 还没识别到。最新安装脚本会自动把常见安装目录加入用户 PATH，并额外安装一个 `~\.claude-provider\claude.cmd` 入口；重新打开 PowerShell/CMD 后再试。如果仍然不行，先用完整路径验证：

```powershell
& "$HOME\.local\bin\claude.exe" --version
& "$HOME\.claude-provider\claude.cmd" --version
```

如果 `claude.cmd` 能运行，把 `$HOME\.claude-provider` 加到用户 PATH 后重开终端；如果 `claude.exe` 能运行，把 `$HOME\.local\bin` 加到用户 PATH 后重开终端。

## 配置内容

脚本会按小米官方 Claude Code 接入文档写入 `~/.claude/settings.json`。`sk-...` 按量 API key 默认使用 `https://api.xiaomimimo.com/anthropic`；`tp-...` Token Plan key 默认使用 `https://token-plan-cn.xiaomimimo.com/anthropic`。如需使用专属 URL，可通过 `MIMO_ANTHROPIC_BASE_URL` 覆盖。

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.xiaomimimo.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "<your-mimo-api-key>",
    "ANTHROPIC_MODEL": "mimo-v2.5-pro",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "mimo-v2.5-pro",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "mimo-v2.5-pro",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "mimo-v2.5-pro"
  }
}
```

脚本也会写入 `~/.claude.json`：

```json
{
  "hasCompletedOnboarding": true
}
```

## 切换模型

MiMo 当前脚本内置快捷别名：

- `flash` -> `mimo-v2-flash`
- `pro` -> `mimo-v2.5-pro`
- `omni` -> `mimo-v2.5`

DeepSeek 当前脚本内置快捷别名：

- `flash` -> `deepseek-v4-flash`
- `pro` -> `deepseek-v4-pro`

不在快捷别名里的模型，也可以直接传完整模型名。

macOS / Linux：

```bash
claude-mimo flash
claude-mimo pro
claude-mimo omni
```

也可以用统一切换器切 provider 和模型：

```bash
claude-provider mimo flash
claude-provider mimo pro
claude-provider mimo omni
claude-provider deepseek pro
claude-provider deepseek flash
```

如果没有在安装时传入 DeepSeek key，第一次切 DeepSeek 时传一次即可，之后脚本会保存在本机 `~/.claude/provider-switch.json`：

```bash
DEEPSEEK_API_KEY="<your-deepseek-api-key>" claude-provider deepseek pro
```

也可以直接传完整模型名：

```bash
claude-provider mimo mimo-v2-flash
claude-provider mimo mimo-v2.5-pro
claude-provider mimo mimo-v2.5
claude-provider deepseek deepseek-v4-pro
```

如果终端找不到命令，使用完整路径：

```bash
~/.local/bin/claude-provider deepseek pro
```

Windows：

```powershell
claude-provider mimo flash
claude-provider mimo pro
claude-provider mimo omni
claude-provider deepseek pro
```

Windows 第一次写入 DeepSeek key：

```powershell
$env:DEEPSEEK_API_KEY="<your-deepseek-api-key>"
claude-provider deepseek pro
```

如果终端找不到 `claude-provider`，重新打开终端，或使用完整路径：

```powershell
& "$HOME\.claude-provider\claude-provider.cmd" deepseek pro
```

切换后重新运行：

```bash
claude
```

## 更换 API key

macOS / Linux：

```bash
claude-provider-key mimo
claude-provider-key deepseek
```

也可以直接传入：

```bash
claude-provider-key mimo "<new-mimo-api-key>"
DEEPSEEK_API_KEY="<new-deepseek-api-key>" claude-provider-key deepseek
```

Windows：

```powershell
claude-provider-key mimo
claude-provider-key deepseek
```

或者：

```powershell
$env:DEEPSEEK_API_KEY="<new-deepseek-api-key>"
claude-provider-key deepseek
```

如果正在使用对应 provider，更换 key 后会同时更新 `~/.claude/settings.json`；如果不是当前 provider，只会先保存，等你下次 `claude-provider deepseek pro` 或 `claude-provider mimo flash` 时生效。
