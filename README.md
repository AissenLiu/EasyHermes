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

优先使用 Docker 离线镜像方式。上游 `hermes-agent` 和 `hermes-webui` 都不把原生 Windows 作为主支持路径，Docker 方式最适合内网机器：构建机一次性把 Python、系统包和依赖烘进镜像，内网机器只需要 `docker load` 后启动。

项目同时保留 `start.bat` 便携 Python 启动方式，作为没有 Docker 时的轻量备选。

## 目录

```text
EazyHermes/
  hermes-agent/                 # Hermes Agent 源码
  hermes-webui/                 # Hermes WebUI 源码
  deploy/docker/                # 推荐：Docker 离线镜像运行方案
  offline/images/               # 推荐：docker save 生成的镜像 tar
  packages/
    python/                     # Windows embeddable Python 与 get-pip.py
    wheelhouse/                 # Windows 离线 Python wheel 包
  runtime/                      # 首次启动时解压生成，不提交
  data/                         # 本机运行数据，不提交
  workspace/                    # 默认工作区，不提交
  scripts/
    start-eazyhermes.ps1        # Windows 启动器
    prepare-offline-bundle.ps1  # 有网环境生成离线包
  start-docker.bat              # 推荐：Docker 双击启动
  start.bat                     # 备选：便携 Python 双击启动
```

## 内网 Windows 启动（推荐 Docker）

在有网络的构建机上生成离线镜像：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-docker-offline.ps1
```

生成结果：

```text
offline/images/eazyhermes-amd64.tar
```

把整个项目目录拷贝到内网 Windows 电脑，双击：

```bat
start-docker.bat
```

脚本会自动执行：

1. 检查 Docker Desktop / Docker Engine。
2. 如果本机没有 `eazyhermes:local` 镜像，则从 `offline/images/eazyhermes-amd64.tar` 导入。
3. 创建 `data/` 和 `workspace/`。
4. 启动容器并等待 `http://127.0.0.1:8787/health`。
5. 打开 `http://127.0.0.1:8787`。

默认只绑定本机 `127.0.0.1:8787`。如果要暴露给内网其他电脑，请先设置 `HERMES_WEBUI_PASSWORD`，再修改 `deploy/docker/compose.yml` 的端口绑定。

## 内网 Windows 启动（备选便携 Python）

在 Windows 上解压项目后，双击：

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
