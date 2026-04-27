# EazyHermes

EazyHermes 将 `hermes-webui` 和 `hermes-agent` 合并为一个可分发项目，面向内网 Windows 电脑提供一键启动。

当前集成版本：

- `hermes-webui`: `69bf2878bcd727a951e64677499ab4381f169c3f`
- `hermes-agent`: `cebf95854bf5ee577930a7566a1dc07968821d72`

## 已包含能力

- WebUI 已包含中文语言：简体中文 `zh` 和繁体中文 `zh-Hant`。
- 设置页语言下拉框会自动列出可用语言。
- 登录页中文文案已由服务端支持。
- Windows 启动脚本会固定使用项目目录内的数据、工作区和运行时路径，适合内网分发。

## 推荐启动方式

使用 GitHub Actions 生成的便携 Python 离线包。内网 Windows 电脑不需要 Docker、WSL、Node 或预装 Python，解压后双击 `start.bat` 即可启动。

## 目录

```text
EazyHermes/
  hermes-agent/                 # Hermes Agent 源码
  hermes-webui/                 # Hermes WebUI 源码
  packages/
    python/                     # Windows embeddable Python 与 get-pip.py
    wheelhouse/                 # Windows 离线 Python wheel 包
  runtime/                      # 首次启动时解压生成，不提交
  data/                         # 本机运行数据，不提交
  workspace/                    # 默认工作区，不提交
  scripts/
    start-eazyhermes.ps1        # Windows 启动器
    prepare-offline-bundle.ps1  # 有网环境生成离线包
  .github/workflows/
    offline-package.yml         # GitHub Actions 离线打包
  start.bat                     # Windows 双击启动
```

## GitHub Actions 离线打包

推荐由 GitHub 生成离线包：

1. 打开仓库的 **Actions**。
2. 选择 **Build Offline Packages**。
3. 点击 **Run workflow**。
4. 构建完成后在本次 workflow run 的 **Artifacts** 下载：
   - `EazyHermes-windows-offline`：便携 Python 离线 zip

推送 `v*` tag 时也会自动构建离线包。

## 内网 Windows 启动

把 `EazyHermes-windows-offline` artifact 下载到内网 Windows 电脑并解压后，双击：

```bat
start.bat
```

脚本会：

1. 解压 `packages/python/` 下的 Windows Python 到 `runtime/python/`。
2. 从 `packages/wheelhouse/` 离线安装 WebUI 和 Agent 所需依赖。
3. 设置本地 `HERMES_HOME`、WebUI 状态目录和默认工作区。
4. 启动 WebUI 并打开 `http://127.0.0.1:8787`。

后续再次启动会复用已经准备好的运行时。

## 生成便携 Python 离线包

在有网络的 Windows 机器上执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-offline-bundle.ps1
```

生成结果位于：

```text
dist/EazyHermes-windows-offline.zip
```

把这个 zip 拷贝到内网 Windows 电脑，解压后双击 `start.bat` 即可。

## 配置模型

首次打开 WebUI 后按引导配置模型供应商/API Key。也可以把已有 Hermes 配置放入：

```text
data/.hermes/
```

内网环境若使用本地模型服务，请在 WebUI 引导或设置页中配置本地 OpenAI-compatible base URL。
