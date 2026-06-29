# WallPaper Gallery

WallPaper Gallery 是一个围绕 Wallpaper Engine 壁纸库构建的跨端工具集。当前仓库包含：

- macOS 原生 SwiftUI 应用：扫描本机壁纸库、管理标签/收藏/分级、解包 `.pkg`、设置图片/视频/场景壁纸。
- Windows Server Demo：在 Windows 电脑上扫描 Wallpaper Engine 创意工坊目录，生成缩略图和 `library.json`，并通过 API 提供给 macOS/iOS 访问。
- iOS/iPadOS Demo：连接 Windows Server，浏览远程壁纸、预览视频、触发远程解包、保存或分享媒体文件。

典型使用方式是：Windows 电脑存放 Steam Wallpaper Engine 资源并运行服务端；macOS 或 iOS 设备通过局域网或 Tailscale 连接服务端。

## 目录

- [Windows Server 端](#windows-server-端)
- [macOS 端](#macos-端)
- [iOS 端](#ios-端)
- [项目架构](#项目架构)
- [开源组件](#开源组件)
- [许可证](#许可证)

## Windows Server 端

Windows Server Demo 位于：

```text
Apps/WindowsServerDemo
```

它提供一个 Streamlit 控制面板，用来配置壁纸库路径、RePKG、缩略图生成和 API 服务。

### 依赖

必需：

- Windows 10/11
- Python 3.10 或更新版本
- Wallpaper Engine 本地创意工坊目录，通常类似：

```text
D:\SteamLibrary\steamapps\workshop\content\431960
```

- RePKG Windows 可执行文件：`RePKG.exe`

Python 依赖见 `Apps/WindowsServerDemo/requirements.txt`：

```text
fastapi
uvicorn[standard]
streamlit
pillow
```

可选但推荐：

- `ffmpeg.exe`：用于没有 `preview.jpg/png/gif/webp` 的视频壁纸生成缩略图。
- `miniserve.exe`：仅用于 Windows 本机调试静态文件访问；正常 macOS/iOS 连接不需要。
- Tailscale：不在同一局域网时推荐使用。

### 安装 Python 依赖

在 PowerShell 中执行：

```powershell
cd Apps\WindowsServerDemo
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### 运行控制面板

```powershell
streamlit run wallpaper_server_demo\streamlit_app.py
```

打开 Streamlit 页面后按顺序设置：

1. `Wallpaper library root`：选择 Wallpaper Engine 创意工坊目录，例如 `...\workshop\content\431960`。
2. `RePKG executable`：选择 `RePKG.exe`，或确保它已在 `PATH` 中。
3. `ffmpeg executable`：可选，选择 `ffmpeg.exe`。
4. `API host`：通常保持 `0.0.0.0`，表示允许局域网设备访问。
5. `API port`：默认 `8090`。
6. `API username` / `API password`：可选。任一字段非空时，API 会启用 Basic Auth。
7. `Public API base URL`：远程访问时可填写外部可访问地址；局域网或 Tailscale 场景可使用页面显示的 URL。
8. `Public static base URL`：正常 iOS/macOS 工作流建议留空。

然后点击：

```text
Generate thumbnails + manifest
Start API server
```

服务启动后，客户端一般使用如下地址连接：

```text
http://<Windows电脑IP>:8090
```

如果使用 Tailscale，通常类似：

```text
http://100.x.y.z:8090
```

### 壁纸目录要求

服务端扫描库根目录下的直接子目录。一般情况下的壁纸目录为：

```text
D:\SteamLibrary\steamapps\workshop\content\431960
```

服务端会读取 `project.json` 中的 `title`、`type`、`file`、`preview_tagger`、`repkgcollection` 等信息，生成 manifest 并发布以下 API：

```text
GET  /api/status
GET  /library.json
GET  /api/library
GET  /api/wallpapers
GET  /api/wallpapers/{id}
POST /api/wallpapers/{id}/unpack
GET  /api/jobs/{jobId}
POST /api/library/rescan
GET  /files/{relative_path}
GET  /api/wallpapers/{id}/download
```

`/files/...` 只允许访问已经写入 `library.json` 的文件，不会开放整个壁纸目录。

### 防火墙和网络

- 第一次启动 API 时，Windows 可能弹出防火墙提示，需要允许 Python/uvicorn 访问专用网络。
- 如果手机和 Windows 不在同一个 Wi-Fi 下，建议使用 Tailscale。
- `miniserve` 当前默认绑定 `127.0.0.1`，主要用于 Windows 本机调试，不是正常客户端连接路径。

## macOS 端

目标系统：

- macOS 26+

### 打包


构建 `.app`：

```bash
make app
```

构建 `.dmg`：

```bash
make dmg
```

也可以使用脚本：

```bash
./scripts/build.sh
./scripts/build.sh dmg
```

生成的 app 通常位于：

```text
release/macos/WallPaper Gallery.app
```

### macOS 依赖文件

`resources/` 目录不再由 Git 跟踪。构建 macOS 应用前，请先从 GitHub 下载或手动准备资源压缩包，并将其解压到项目根目录，确保最终路径类似：

```text
WallPaper Gallery/
├── README.md
├── Sources/
└── resources/
```

打包时需要以下资源存在：

```text
resources/osx-arm64/RePKG
resources/osx-arm64/*.dll
resources/osx-arm64/*.json
resources/osx-arm64/*.dylib
resources/osx-arm64/*.pdb
resources/bin/WallpaperPlayer
resources/bin/wallpaper-wgpu
resources/assets/
resources/dxc
resources/lib/libdxcompiler.dylib
```

用途：

- `RePKG` 和 .NET runtime：解包 Wallpaper Engine `.pkg`。
- `WallpaperPlayer`：播放视频壁纸。
- `wallpaper-wgpu`、`resources/assets/`、`dxc`、`libdxcompiler.dylib`：实时渲染 scene 壁纸。
- `ffmpeg`：可选，生成缩略图。

开发时可以用环境变量覆盖默认路径：

```bash
export REPKG_PATH="/path/to/RePKG"
export WALLPAPER_WGPU_PATH="/path/to/wallpaper-wgpu"
export WALLPAPER_WGPU_ASSETS_PATH="/path/to/assets"
```

### Library 设置

打开 macOS 应用后进入 Settings -> Library。

`Library Mode`：

- `Local`：扫描本机文件夹。
- `Remote`：连接 Windows Server，浏览远程库。远程壁纸会先下载原始源文件夹，再走本地设置壁纸流程。

本地模式：

- `Open Folder`：选择本机 Wallpaper Engine 库或其他壁纸目录。
- `Default Scan Mode`：
  - `Subdir`：按 Wallpaper Engine workshop 子目录扫描，适合 `project.json + preview + pkg/媒体文件` 结构。
  - `Flat`：递归扫描图片/视频文件，适合普通文件夹。
- `Output`：RePKG 解包输出目录。
- `RePKG Binary`：默认使用内置 RePKG；如需调试或替换版本，可手动选择。

远程模式：

- `Server URL`：Windows Server API 地址，例如 `http://192.168.1.20:8090` 或 Tailscale 地址。
- `Username` / `Password`：与 Windows Streamlit 页面里设置的 Basic Auth 一致；服务端未设置认证时可留空。
- `Download Folder`：远程壁纸下载到 Mac 上的位置。
- `Connect`：拉取远程 `library.json` 并显示远程壁纸库。

远程卡片状态：

- `未下载`：右键菜单中主要是 `Download`。
- `已下载`：行为接近本地壁纸，可设置壁纸、解包、打开 Finder、编辑元数据等。

远程下载完成后，应用会在下载目录写入：

```text
.wallpaper-remote-downloads.json
```

它用于记录远程 ID 和本地文件夹名的映射，下次启动可以恢复下载状态。

### Wallpaper 设置

Settings -> Wallpaper：

- `Restore wallpaper on launch`：应用启动时恢复上一次设置的壁纸。
- `Mute video wallpaper`：视频壁纸静音播放。
- `Auto-replace static wallpaper with first frame`：设置视频壁纸时抓取首帧作为静态桌面回退图，方便空间切换或登录界面显示。
- `MetalFX upscaling for scene wallpapers`：scene 壁纸低分辨率渲染后通过 MetalFX 放大，降低 GPU 压力。
- `Render scale`：scene 内部渲染比例。
- `Scene FPS limit`：scene 壁纸帧率上限，会与显示器刷新率取较低值。
- `Save & Reapply`：保存 scene 渲染设置，并重新应用当前 scene 壁纸。

### Extraction 设置

Settings -> Extraction：

- `Ignore extensions (-i)`：解包时忽略指定扩展名，例如 `.png,.jpg`。
- `Only extensions (-e)`：只解包指定扩展名。
- `Convert TEX files (-t)`：转换 `.tex` 贴图。
- `No TEX conversion`：禁用 TEX 转换。
- `Single directory (-s)`：输出到单层目录。
- `Recursive (-r)`：递归处理。
- `Copy project.json (-c)`：解包时复制 `project.json`。
- `Use name (-n)`：使用项目名称作为输出名。
- `Overwrite existing`：覆盖已有文件。
- `Debug info (-d)`：输出调试信息。
- `Copy only (skip extraction)`：仅复制，不执行解包。

这些设置会作为 RePKG 默认参数参与单个或批量解包。

### 连接 Windows Server

1. 先在 Windows 上启动 Streamlit 控制面板。
2. 生成 thumbnails 和 `library.json`。
3. 点击 `Start API server`。
4. 在 macOS Settings -> Library 中切换到 `Remote`。
5. 填入 `Server URL`、`Username`、`Password`。
6. 选择 `Download Folder`。
7. 点击 `Connect`。
8. 远程壁纸出现后，右键未下载壁纸选择 `Download`。
9. 下载完成后即可像本地壁纸一样设置。

## iOS 端

iOS Demo 位于：

```text
Apps/iOSDemo
```

当前是一个远程浏览/预览/保存 demo，不会设置 iOS 系统壁纸。

### 安装和运行

要求：

- Xcode
- iOS/iPadOS 模拟器或真机
- 如果使用真机，需要在 Xcode 中设置自己的 Team 签名

运行步骤：

1. 打开工程：

```bash
Apps/iOSDemo/WallpaperGalleryiOSDemo.xcodeproj
```

2. 在 Xcode 中选择 `WallpaperGalleryiOSDemo` scheme。
3. 选择 iPhone/iPad 模拟器或真机。
4. 点击 Run。

应用首次启动会加载内置示例 manifest。连接真实 Windows 库：

1. 启动 Windows Server Demo。
2. 在 Streamlit 中设置认证信息。
3. 点击 `Generate thumbnails + manifest`。
4. 点击 `Start API server`。
5. 复制 Streamlit 页面显示的 `iOS Settings URL`。
6. 在 iOS app 的 Settings tab 中填写 Server URL、Username、Password。
7. 返回 Library 页面浏览远程壁纸。

### iOS 功能

- 读取 `library.json`。
- 支持 Basic Auth。
- 支持搜索、收藏、标签、类型标记。
- 加载远程缩略图。
- 对视频资源使用 `AVPlayer` 流式预览。
- 对 `.pkg` 壁纸可触发服务端 `POST /api/wallpapers/{id}/unpack`。
- 支持 `ShareLink` 导出远程 URL。
- 支持 Save to Photos：下载选中的媒体文件并保存到系统相册。

建议：

- 同一局域网下直接使用 Windows IP。
- 不在同一网络时使用 Tailscale。

## 项目架构

整体结构：

```text
Sources/                  macOS SwiftUI app
Apps/iOSDemo/             iOS/iPadOS remote client demo
Apps/WindowsServerDemo/   Windows Streamlit + FastAPI server demo
docs/                     跨平台远程库设计文档
resources/                macOS 运行时资源和渲染资源
scripts/                  打包脚本
```


## 开源组件

本项目使用或集成了以下开源组件：

- [notscuffed/repkg](https://github.com/notscuffed/repkg)：用于解包 Wallpaper Engine `.pkg` 文件。macOS 端内置 arm64 运行时资源，Windows Server 端需要配置 `RePKG.exe`。
- [jipika/WaifuX](https://github.com/jipika/WaifuX)：用于 Wallpaper Engine scene 渲染相关能力的参考/集成基础，项目中的 `wallpaper-wgpu`、scene 资源和渲染管线围绕该方向工作。


## 许可证

本项目以 GNU General Public License v3.0 授权发布，详见 [LICENSE](LICENSE)。
