# EazyHermes

EazyHermes 是一个面向内网 Windows 电脑的一键启动版 Hermes。它把 `hermes-agent` 的 Agent 能力和 `hermes-webui` 的浏览器界面整合在同一个项目里，并通过 GitHub Actions 生成可离线分发的 Windows 压缩包。

目标很直接：在有网络的地方完成依赖下载和打包，然后把一个 zip 从 GitHub Releases 下载并拷贝到内网 Windows 电脑，解压后双击 `start.bat` 即可运行，不要求内网机器安装 Docker、WSL、Node.js 或 Python。

## 项目组成

- `hermes-agent`：核心 Agent，负责模型调用、工具调用、会话、技能、记忆、计划任务等能力。
- `hermes-webui`：浏览器界面，提供聊天、会话管理、工作区文件浏览、设置、模型配置等功能。
- `start.bat` / `scripts/start-eazyhermes.ps1`：Windows 一键启动脚本。
- `packages/python`：Windows embeddable Python 和 `get-pip.py`。
- `packages/node`：Windows portable Node.js。
- `packages/wheelhouse`：Windows 离线 Python wheel 依赖包。
- `.github/workflows/offline-package.yml`：GitHub Actions 离线打包流程。

当前集成版本：

- `hermes-webui`: `69bf2878bcd727a951e64677499ab4381f169c3f`
- `hermes-agent`: `cebf95854bf5ee577930a7566a1dc07968821d72`

## 已包含能力

- 中文界面：WebUI 已包含简体中文 `zh` 和繁体中文 `zh-Hant`。
- 离线启动：运行包内置 Python、Node.js、Python wheels、Node modules 和 WebUI 静态资源，内网 Windows 解压即用。
- 本地数据隔离：运行数据默认写入项目目录下的 `data/`，默认工作区为 `workspace/`。
- 浏览器 WebUI：默认打开 `http://127.0.0.1:8787`。
- 模型可配置：支持在 WebUI 引导或设置页中配置云端 API 或本地 OpenAI-compatible 模型服务。

## 目录结构

```text
EazyHermes/
  hermes-agent/                 # Hermes Agent 源码
  hermes-webui/                 # Hermes WebUI 源码
  packages/
    python/                     # Windows embeddable Python 与 get-pip.py
    node/                       # Windows portable Node.js zip
    wheelhouse/                 # Windows 离线 Python wheel 包
  runtime/                      # 首次启动时解压生成，不提交
  data/                         # 本机运行数据，不提交
  workspace/                    # 默认工作区，不提交
  packaging/windows/
    requirements-windows.txt    # Windows 离线依赖清单
  scripts/
    start-eazyhermes.ps1        # Windows 启动器
    prepare-offline-bundle.ps1  # 本地生成离线包的辅助脚本
  .github/workflows/
    offline-package.yml         # GitHub Actions 手动离线打包
  start.bat                     # Windows 双击启动入口
```

## GitHub 手动离线打包

离线包不再自动构建。需要打包时，在 GitHub Actions 页面手动输入 tag 触发。

### 1. 准备 tag

先为要打包的版本创建并推送 tag，例如：

```bash
git tag -a v0.1.2 -m "EazyHermes v0.1.2"
git push origin v0.1.2
```

也可以复用已经存在的 tag，例如 `v0.1.1`。

### 2. 在 GitHub Actions 手动运行

1. 打开仓库的 **Actions** 页面。
2. 选择 **Build Offline Packages**。
3. 点击 **Run workflow**。
4. 填写 `package_tag`，例如 `v0.1.2`。
5. 保持默认 `python_version=3.11.9` 和 `node_version=20.11.1`，除非确实要升级内置运行时。
6. 点击 **Run workflow** 开始打包。

Workflow 会 checkout 到你输入的 tag，然后在 GitHub 的 Windows runner 上完成：

- 下载 Windows embeddable Python。
- 下载 Windows portable Node.js。
- 下载 `requirements-windows.txt` 中声明的 Windows wheel 依赖，覆盖 `hermes-agent[all]` 在 Windows 上可用的运行依赖。
- 安装并打包 `hermes-agent` 根目录 Node 依赖，包括 `agent-browser`。
- 安装并打包 WhatsApp bridge 的 Node 依赖。
- 下载 WebUI 需要的 KaTeX、Prism、Mermaid 本地静态资源。
- 预装运行时依赖。
- 生成 `dist/EazyHermes-windows-offline.zip`。
- 上传 workflow artifact。
- 创建或更新对应 tag 的 GitHub Release，并把 zip 与 sha256 校验文件上传到 Releases。

### 3. 下载产物

构建完成后，打开仓库的 **Releases** 页面，进入对应 tag，例如 `v0.1.2`，下载：

```text
EazyHermes-windows-offline.zip
EazyHermes-windows-offline.zip.sha256
```

workflow run 的 **Artifacts** 区域也会保留一份相同产物，方便临时排查；正式分发建议使用 Releases。

可选校验：

```powershell
Get-FileHash .\EazyHermes-windows-offline.zip -Algorithm SHA256
```

把这个 zip 拷贝到内网 Windows 电脑即可。

## 内网 Windows 启动

在内网 Windows 电脑上：

1. 解压 `EazyHermes-windows-offline.zip`。
2. 进入解压后的 `EazyHermes` 目录。
3. 双击 `start.bat`。

首次启动会自动执行：

1. 解压 `packages/python/` 下的 Windows Python 到 `runtime/python/`。
2. 解压 `packages/node/` 下的 Windows Node.js 到 `runtime/node/`。
3. 从 `packages/wheelhouse/` 离线安装 WebUI 和 Agent 所需依赖。
4. 将内置 Node.js、`agent-browser` 和 WhatsApp bridge 加入当前启动进程的 `PATH`。
5. 创建本地 `data/`、`data/.hermes/`、`data/webui/` 和 `workspace/`。
6. 设置 `HERMES_HOME`、WebUI 状态目录、默认工作区和 Agent 源码路径。
7. 启动 WebUI 并打开 `http://127.0.0.1:8787`。

后续再次启动会复用 `runtime/`，速度会更快。

## 配置模型

首次打开 WebUI 后按引导配置模型供应商/API Key。也可以把已有 Hermes 配置放入：

```text
data/.hermes/
```

内网环境常见做法是配置本地模型服务，例如 Ollama、LM Studio、vLLM 或其他 OpenAI-compatible endpoint。只要服务能提供兼容 OpenAI 的 API，就可以在 WebUI 的模型/提供商设置中填写对应的 Base URL 和模型名。

如果内网机器无法访问外部模型 API，请不要选择依赖公网的 OpenAI、Anthropic、OpenRouter 等云模型，除非你已经在内网配置了代理或私有转发。

## 数据与安全

- 会话、设置、技能、记忆等数据默认保存在 `data/`。
- 默认工作区是 `workspace/`，WebUI 可以浏览和编辑该目录内的文件。
- 默认只监听本机 `127.0.0.1:8787`。
- 如果后续要改成内网其他电脑可访问，请务必设置访问密码，避免把文件浏览和 Agent 能力直接暴露给局域网。

## 本地生成离线包

通常推荐使用 GitHub Actions 打包。如果确实要在有网络的 Windows 机器本地生成，可以执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-offline-bundle.ps1
```

生成结果位于：

```text
dist/EazyHermes-windows-offline.zip
```

## 注意事项

- 本项目当前只面向 Windows 便携离线包，不提供 Docker 镜像包。
- 离线包会发布到对应 tag 的 GitHub Release；workflow artifact 仍默认保留 14 天。
- 如果修改了依赖清单，请重新打 tag 并用该 tag 手动打包。
- 便携包包含 Windows 可用的 `hermes-agent[all]` Python 依赖、`agent-browser`、WhatsApp bridge Node 依赖，以及 WebUI 的本地静态资源。
- `rl`、`yc-bench` 等 git-sourced 实验/训练 extras 不属于当前 Windows 一键运行包；它们依赖外部仓库和特定训练环境。
- 模型服务本身不包含在离线包内。内网使用时请配置本地 OpenAI-compatible 服务，或确保内网能访问你选择的云模型 API。
