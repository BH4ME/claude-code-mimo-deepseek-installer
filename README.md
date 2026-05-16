# Claude Code MiMo / DeepSeek Installer

一键安装 Claude Code，并配置 Xiaomi MiMo 或 DeepSeek 的 Anthropic-compatible API。API key 只保存在本机，不会上传到 GitHub。

## 快速安装

macOS / Linux:

```bash
curl -fsSL https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/install.sh | bash
```

Windows PowerShell:

```powershell
irm https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/install.ps1 | iex
```

非交互安装:

```bash
MIMO_API_KEY="sk-or-tp-..." DEEPSEEK_API_KEY="sk-..." ./install.sh
```

PowerShell:

```powershell
$env:MIMO_API_KEY="sk-or-tp-..."
$env:DEEPSEEK_API_KEY="sk-..."
.\install.ps1
```

只安装 Claude Code 和切换命令，暂不写 key:

```bash
./install.sh --skip-api-key
```

默认 MiMo 模型是 `mimo-v2.5-pro`。可以用 `MIMO_MODEL` 覆盖。

## 切换

MiMo:

```bash
claude-provider mimo flash
claude-provider mimo pro
claude-provider mimo omni
```

DeepSeek:

```bash
DEEPSEEK_API_KEY="sk-..." claude-provider deepseek pro
claude-provider deepseek flash
```

也可以直接用完整模型名:

```bash
claude-provider mimo mimo-v2.5-pro
claude-provider deepseek deepseek-v4-pro
```

快捷别名:

| Provider | Alias | Model |
| --- | --- | --- |
| MiMo | `flash` | `mimo-v2-flash` |
| MiMo | `pro` | `mimo-v2.5-pro` |
| MiMo | `omni` | `mimo-v2.5` |
| DeepSeek | `flash` | `deepseek-v4-flash` |
| DeepSeek | `pro` | `deepseek-v4-pro` |

切换后重新运行:

```bash
claude
```

## API Key

保存或更换 key:

```bash
claude-provider-key mimo "sk-or-tp-..."
claude-provider-key deepseek "sk-..."
```

如果当前 provider 正在使用这个 key，脚本会同步更新 `~/.claude/settings.json`。否则会先保存在 `~/.claude/provider-switch.json`，下次切换时生效。

MiMo base URL 会按 key 自动判断:

| Key | Base URL |
| --- | --- |
| `sk-...` | `https://api.xiaomimimo.com/anthropic` |
| `tp-...` | `https://token-plan-cn.xiaomimimo.com/anthropic` |

需要专属 URL 时设置 `MIMO_ANTHROPIC_BASE_URL`。

## 写入内容

脚本会写入:

- `~/.claude/settings.json`: Claude Code 实际读取的 API 配置。
- `~/.claude/provider-switch.json`: 每个 provider 的 key 和 base URL。
- `~/.claude.json`: 标记 Claude Code 已完成 onboarding。

## 常见问题

如果提示 `command not found: claude-provider`，先打开新终端再试。macOS / Linux 安装脚本会把 `~/.local/bin` 写入 shell profile；仍不生效时可临时运行:

```bash
export PATH="$HOME/.local/bin:$PATH"
~/.local/bin/claude-provider mimo pro
```

如果提示 `Missing API key for mimo`:

```bash
claude-provider-key mimo "sk-or-tp-..."
claude-provider mimo pro
```

如果 Claude Code 卡在 `Retrying in ... attempt .../10`:

```bash
Ctrl+C
claude-provider-key mimo "sk-or-tp-..."
claude-provider mimo pro
cat ~/.claude/settings.json
```

确认 `settings.json` 里已经有:

- `ANTHROPIC_API_KEY`
- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_MODEL`

然后重新运行:

```bash
claude
```

如果启动页仍然显示官方 `pro / API Usage Billing`，通常说明 Claude 还在用旧会话。先退出旧进程再重开:

```bash
pkill -f claude
claude
```

Windows 如果 `claude` 无法识别，重开 PowerShell/CMD。仍不行时检查:

```powershell
& "$HOME\.claude-provider\claude.cmd" --version
& "$HOME\.local\bin\claude.exe" --version
```

Linux 如果官方安装脚本被拦截，本安装器会自动尝试 npm fallback；Node/npm 不可用时会尝试系统包管理器或用户本地 Node.js。
