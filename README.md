# Phantasmoon 桌宠

以 Phantasmoon（ファンタズムーン）第一再临形象制作的非官方 Q 版桌宠，供支持自定义 **v2 Pets** 的桌面客户端使用。

当前版本：**v1.0.0 · 美术修订 R17**。包含轻快眨眼、左右移动、全身配合的挥手、失落表情、等待 wink，以及三种不同的魔法效果。

<img src="previews/idle.gif" alt="待机与轻快眨眼" width="280">

[查看全部动作 GIF](previews/all-states.gif) · [下载动作预览 MP4](previews/all-states.mp4) · [精灵图](pet/phantasmoon/spritesheet.png)

## 安装前

- 先安装并运行一次桌面客户端，确认「设置 → Pets」可用，并支持自定义 v2 宠物。
- **Codex Pro** 与普通 **Codex** 的数据目录可能不同。以下主命令使用 `pro`，对应用户目录下的 `.codex-pro`；普通 Codex 请改成 `codex`，对应 `.codex`。
- 本包安装的是本地宠物，不需要 Pets 插件、Git、Python 或管理员权限。安装后需要在设置里手动选择一次。

## 一键在线安装

**发布地址预留：`OWNER/REPO`。当前本地仓库尚未上传，以下在线命令须在发布后，将 `OWNER/REPO` 换成真实的“GitHub 用户名/仓库名”才能使用。** 命令固定下载 `v1.0.0` 标签，发布时请同时推送该标签。

### macOS

在「终端」粘贴一行：

```bash
REPO='OWNER/REPO'; curl -fsSL "https://raw.githubusercontent.com/$REPO/v1.0.0/install.sh" | bash -s -- --app pro --repository "$REPO" --ref v1.0.0
```

### Windows

在 **Windows PowerShell 5.1 或 PowerShell 7** 粘贴一行：

```powershell
$repo='OWNER/REPO'; & ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$repo/v1.0.0/install.ps1").Content)) -App pro -Repository $repo -Ref 'v1.0.0'
```

这两条命令会执行仓库中的安装脚本。可先阅读 [macOS 脚本](install.sh) 或 [Windows 脚本](install.ps1)。Windows 命令不修改系统的脚本执行策略。

## 下载 ZIP 后离线安装

下载并解压完整仓库，在解压目录打开终端。这里的“离线”指素材安装过程无需联网；桌面客户端本身仍需事先安装。

**macOS：**

```bash
bash ./install.sh --app pro
```

**Windows PowerShell：**

```powershell
& ([scriptblock]::Create((Get-Content -LiteralPath .\install.ps1 -Raw))) -App pro -AssetRoot (Join-Path $PWD 'pet\phantasmoon')
```

Windows 也可直接运行 `./install.ps1 -App pro`，前提是本机已允许执行下载的脚本。上面的命令适用于保持默认执行策略的环境；若组织策略禁止脚本运行，请使用下方手动安装方式。

### 完成后显示桌宠

打开桌面应用的「设置 → Pets」，刷新或重新打开设置，选择 **Phantasmoon**。若已通过在线 Pets 库添加过同名宠物，列表中可能同时存在云端版本与本地版本；本包的本地 ID 是 `custom:phantasmoon`。

安装脚本不会改变当前选中的宠物，也不会修改 `config.toml`。无需重装客户端。

## 目录选择与手动安装

| 客户端/位置 | macOS | Windows 原生客户端 |
| --- | --- | --- |
| Codex Pro 常用目录 | `~/.codex-pro/pets/phantasmoon/` | `%USERPROFILE%\.codex-pro\pets\phantasmoon\` |
| 普通 Codex 默认目录 | `~/.codex/pets/phantasmoon/` | `%USERPROFILE%\.codex\pets\phantasmoon\` |
| 自定义数据目录 | `<实际 CODEX_HOME>/pets/phantasmoon/` | `<实际 CODEX_HOME>\pets\phantasmoon\` |

`pro` 是本脚本对 `.codex-pro` 目录的简称，不是订阅套餐判断。不同客户端或定制发行版可能采用其他目录。**以桌面应用实际使用的目录为准**；终端里的 `CODEX_HOME` 不一定与桌面应用相同。Windows 原生应用也可能与 WSL 使用不同目录。

指定实际目录（优先级最高，目录需已存在）：

```bash
bash ./install.sh --codex-home "$HOME/path/to/app-state"
```

```powershell
& ([scriptblock]::Create((Get-Content -LiteralPath .\install.ps1 -Raw))) -CodexHome 'D:\App State' -AssetRoot (Join-Path $PWD 'pet\phantasmoon')
```

省略 `--app` / `-App` 时采用 `auto`：先读取当前环境的 `CODEX_HOME`，再寻找 `.codex-pro`，最后寻找 `.codex`。若两者同时存在，建议显式指定客户端。

手动安装只需把 [`pet/phantasmoon/`](pet/phantasmoon) 整个文件夹复制到实际数据目录的 `pets` 下，保留 `pet.json` 和 `spritesheet.png` 在同一层。不要把整个仓库复制进去。

普通 Codex 的默认目录与 `CODEX_HOME` 约定参考 [OpenAI 环境变量文档](https://learn.chatgpt.com/docs/config-file/environment-variables)；Windows 客户端与 WSL 的差异参考 [官方 Windows 文档](https://learn.chatgpt.com/docs/windows/windows-app)。本包的 Pro 路径来自制作环境中的实际配置，不代表所有发行版的通用约定。

## 更新、备份与排查

- 安装前校验两个素材文件的 SHA-256，并核对 PNG 尺寸。校验失败会停止，不替换已安装的宠物。
- 重复安装相同版本会直接跳过。替换旧版时，旧文件夹完整保留在 `<实际 CODEX_HOME>/pet-backups/phantasmoon/<时间-随机标识>/`，避免在 Pets 列表中产生备份副本。
- 恢复旧版时，先将当前 `pets/phantasmoon` 移到其他位置，再把所需备份文件夹复制回 `pets/phantasmoon`。刷新设置后重新选择。
- 仅查看计划：macOS 加 `--dry-run`；Windows 加 `-DryRun`。此模式不会联网或写文件。
- 找不到宠物：确认安装输出中的 `Target` 与桌面应用实际数据目录一致，确认版本支持 v2，再重新打开 Pets 设置。仅 CLI 安装完成并不等于已安装支持 Pets 的桌面客户端。
- 提示安装锁存在：先确认没有另一个安装进程；若上次被强制终止，可删除实际数据目录中的 `.phantasmoon-install.lock` 后再试。

## 动作与格式

包含九个动画状态和十六个注视方向，透明 RGBA 精灵图为 **1536 × 2288**，8 列 × 11 行，每格 192 × 208。详细帧布局见 [格式说明](docs/format.md)。

三种魔法分别放在 `running`、`jumping`、`review` 状态中。具体触发、重复次数、播放速度与状态优先级由宿主应用控制；本素材包不会给客户端新增随机触发接口，也不能保证每次任务状态变化都会切换动作。预览中的顺序播放用于展示全部动作。

## 验证状态

- R17 素材沿用制作时已通过验证的最终精灵图；发布包使用固定校验值。
- macOS 安装器已在隔离的模拟数据目录中验证安装、重复安装、备份、校验失败保护和目录选择。
- Windows 安装器附带相同的自动化测试；**尚未在真实 Windows 桌面客户端中验证显示效果**。仓库附带的 CI 会在上传 GitHub 后运行 Windows 和 macOS 安装测试。

开发者可用 Python 3 运行 `python3 -m unittest discover -s tests -v`。Windows 测试会调用 Windows PowerShell；macOS 测试使用系统 Bash 3.2。最终用户安装无需 Python。

## 发布到 GitHub

1. 创建空的公开仓库，将本文中的 `OWNER/REPO` 替换为真实地址。
2. 在当前本地仓库提交 README 修改，并将发布标签移到该提交：

```bash
git add README.md
git commit -m "Set GitHub repository address"
git tag -f v1.0.0
git remote add origin https://github.com/OWNER/REPO.git
git push -u origin main
git push origin v1.0.0
```

如果发布地址是在本地 ZIP 安装之后填写，也不影响离线安装。上传后可在 GitHub 的 Releases 中创建 `v1.0.0` 发布，用户即可下载源码 ZIP。

## 许可与来源

角色与设定来自 TYPE-MOON / Fate 相关作品，本项目为非官方同人制作，图像经过 AI 辅助生成及多轮人工指导修订。

安装脚本、测试及辅助代码采用 [MIT License](LICENSE)。角色图像、动画及预览不包含在代码的 MIT 授权内，相关说明见 [ASSET_NOTICE.md](ASSET_NOTICE.md)。
