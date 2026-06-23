import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var effectiveLanguage: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    func displayName(in language: AppLanguage) -> String {
        let effective = language.effectiveLanguage
        switch (self, effective) {
        case (.system, .simplifiedChinese): return "跟随系统"
        case (.english, .simplifiedChinese): return "English"
        case (.simplifiedChinese, .simplifiedChinese): return "简体中文"
        case (.system, _): return "System"
        case (.english, _): return "English"
        case (.simplifiedChinese, _): return "Simplified Chinese"
        }
    }
}

enum L10n {
    static func t(_ key: String, _ language: AppLanguage) -> String {
        guard language.effectiveLanguage == .simplifiedChinese else { return key }
        return zhHans[key] ?? key
    }

    static func wallpaperType(_ type: String, _ language: AppLanguage) -> String {
        switch type.lowercased() {
        case "video": return t("Video", language)
        case "image": return t("Image", language)
        case "scene": return t("Scene", language)
        case "web": return t("Web", language)
        case "application": return t("App", language)
        default: return t("Unknown", language)
        }
    }

    static func contentRating(_ rating: String, _ language: AppLanguage) -> String {
        switch rating {
        case "Everyone": return t("Everyone", language)
        case "Questionable": return t("Questionable", language)
        case "Mature": return t("Mature", language)
        default: return rating
        }
    }

    static func itemCount(_ count: Int, _ singularKey: String, _ pluralKey: String, _ language: AppLanguage) -> String {
        let key = count == 1 ? singularKey : pluralKey
        return String(format: t(key, language), count)
    }

    private static let zhHans: [String: String] = [
        "Ready": "就绪",
        "Scanning...": "正在扫描...",
        "Connecting...": "正在连接...",
        "Connecting to remote library...": "正在连接远程图库...",
        "Connected": "已连接",
        "Disconnected": "未连接",
        "Slow connection": "连接速度低",
        "Speed": "速度",
        "Remote mode selected": "已选择远程模式",
        "Remote mode selected. Connect to load the Windows library.": "已选择远程模式。连接后加载 Windows 图库。",
        "Another remote download is already running": "已有另一个远程下载正在进行",
        "Remote is disconnected": "远程连接已断开",
        "Remote unavailable. No saved wallpapers found": "远程不可用，未找到已保存的壁纸",
        "%d saved remote wallpapers loaded": "已加载 %d 个已保存的远程壁纸",
        "Remote item is no longer available": "远程项目已不可用",
        "Content rating updated": "分级已更新",
        "Extraction complete": "解包完成",
        "Extraction stopped": "解包已停止",
        "Extracting all...": "正在全部解包...",
        "Select wallpapers and an output directory first": "请先选择壁纸和输出目录",
        "Select input and output directories": "请选择输入和输出目录",
        "No media files found in extracted output": "解包输出中未找到媒体文件",
        "No scene wallpaper to reapply": "没有可重新应用的 scene 壁纸",
        "Scene wallpaper no longer exists": "scene 壁纸已不存在",
        "Scene rendering settings applied": "scene 渲染设置已应用",
        "Restore wallpaper failed": "恢复壁纸失败",
        "Library": "图库",
        "Wallpaper": "壁纸",
        "Extraction": "解包",
        "Language": "语言",
        "Library Mode": "图库模式",
        "Local": "本地",
        "Remote": "远程",
        "Local mode scans a folder on this Mac. Remote mode downloads original wallpaper folders before using the same local pipeline.": "本地模式扫描这台 Mac 上的文件夹。远程模式会先下载原始壁纸文件夹，再使用同一套本地处理流程。",
        "Default Scan Mode": "默认扫描模式",
        "Subdirectories": "子目录",
        "Flat files": "扁平文件",
        "Scanning": "扫描",
        "Output": "输出",
        "Output Directory": "输出目录",
        "No output directory selected": "未选择输出目录",
        "RePKG Binary": "RePKG 可执行文件",
        "Select RePKG binary": "选择 RePKG 可执行文件",
        "Default bundled RePKG": "默认内置 RePKG",
        "Browse": "浏览",
        "Use Bundled": "使用内置",
        "Directories": "目录",
        "The bundled RePKG binary is used when no override path is set.": "未设置覆盖路径时会使用内置 RePKG。",
        "Status": "状态",
        "Actions": "操作",
        "Open Folder": "打开文件夹",
        "Refresh": "刷新",
        "Server URL": "服务器 URL",
        "Username": "用户名",
        "Password": "密码",
        "Download Folder": "下载文件夹",
        "No download folder selected": "未选择下载文件夹",
        "Connect": "连接",
        "Change...": "更改...",
        "Playback": "播放",
        "Restore wallpaper on launch": "启动时恢复壁纸",
        "Mute video wallpaper": "视频壁纸静音",
        "Auto-replace static wallpaper with first frame": "自动用首帧替换静态壁纸",
        "Restore reapplies the last wallpaper on launch. Static replacement captures the first video frame as a fallback for spaces and login screen.": "恢复会在启动时重新应用上次的壁纸。静态替换会捕获视频首帧，作为空间和登录界面的回退图。",
        "Gallery Background": "图库背景",
        "Accent source": "取色来源",
        "Automatic": "自动",
        "Custom": "自定义",
        "Accent color": "强调色",
        "Automatic follows the selected wallpaper type. Custom keeps the gallery background on your chosen color.": "自动会跟随选中壁纸的类型取色；自定义会让图库背景固定为你选择的颜色。",
        "MetalFX upscaling for scene wallpapers": "scene 壁纸启用 MetalFX 放大",
        "Render scale": "渲染比例",
        "Scene FPS limit": "scene 帧率上限",
        "Save & Reapply": "保存并重新应用",
        "Scene Rendering": "scene 渲染",
        "Scene wallpapers use the lower of this FPS limit and the display refresh rate. MetalFX renders at a lower internal resolution, then upscales to reduce GPU load.": "scene 壁纸会使用此帧率上限和显示器刷新率中的较低值。MetalFX 会以较低内部分辨率渲染，再放大以降低 GPU 负载。",
        "Extraction Filters": "解包过滤",
        "Extensions to ignore (-i) or include (-e) when extracting packages.": "解包时忽略 (-i) 或仅包含 (-e) 的扩展名。",
        "Convert TEX files (-t)": "转换 TEX 文件 (-t)",
        "No TEX conversion": "不转换 TEX",
        "Single directory (-s)": "单目录 (-s)",
        "Recursive (-r)": "递归 (-r)",
        "Copy project.json (-c)": "复制 project.json (-c)",
        "Use name (-n)": "使用名称 (-n)",
        "Overwrite existing": "覆盖已有文件",
        "Debug info (-d)": "调试信息 (-d)",
        "Copy only (skip extraction)": "仅复制（跳过解包）",
        "Default Extraction Options": "默认解包选项",
        "Ignore extensions": "忽略扩展名",
        "Only extensions": "仅包含扩展名",
        "Open Directory...": "打开目录...",
        "Open Directory": "打开目录",
        "Select All": "全选",
        "Deselect All": "取消全选",
        "Search wallpapers...": "搜索壁纸...",
        "Type": "类型",
        "Filter by type": "按类型筛选",
        "All": "全部",
        "Video": "视频",
        "Image": "图片",
        "Scene": "场景",
        "Web": "网页",
        "App": "应用",
        "Unknown": "未知",
        "Rating": "分级",
        "Filter by rating": "按分级筛选",
        "Everyone": "全年龄",
        "Questionable": "可疑",
        "Mature": "成人",
        "Mature Content": "成人内容",
        "Cancel": "取消",
        "Show Mature Content": "显示成人内容",
        "This will display content marked as Mature. Are you sure?": "这会显示标记为成人的内容。确定继续吗？",
        "Collections": "收藏集",
        "Filter by collection": "按收藏集筛选",
        "Scene Properties": "scene 属性",
        "%d wallpaper": "%d 个壁纸",
        "%d wallpapers": "%d 个壁纸",
        "%d selected": "已选择 %d 项",
        "Deselect": "取消选择",
        "Add to Collection": "添加到收藏集",
        "New Collection...": "新建收藏集...",
        "Remove from Collection": "从收藏集中移除",
        "Delete": "删除",
        "Delete Selected Wallpapers?": "删除选中的壁纸？",
        "This removes %d selected wallpapers from disk.": "这会从磁盘删除选中的 %d 个壁纸。",
        "No wallpapers loaded": "未加载壁纸",
        "Open a directory containing Wallpaper Engine wallpapers": "打开包含 Wallpaper Engine 壁纸的目录",
        "Download": "下载",
        "Set as Wallpaper": "设为壁纸",
        "Set as Wallpaper...": "设为壁纸...",
        "Set on All Screens": "设为所有屏幕壁纸",
        "Set on All Screens...": "设为所有屏幕壁纸...",
        "Extract to Disk...": "解包到磁盘...",
        "Change Rating": "更改分级",
        "Show in Finder": "在 Finder 中显示",
        "Delete Wallpaper?": "删除壁纸？",
        "This removes the wallpaper from disk.": "这会从磁盘删除该壁纸。",
        "Press to deselect": "按下以取消选择",
        "Press to select": "按下以选择",
        "Extract Wallpapers": "解包壁纸",
        "Close": "关闭",
        "Stop": "停止",
        "Copy Selected": "复制选中项",
        "Extract Selected": "解包选中项",
        "Extract All": "全部解包",
        "%d wallpapers selected": "已选择 %d 个壁纸",
        "Input: %@": "输入：%@",
        "Not set": "未设置",
        "Choose...": "选择...",
        "Options": "选项",
        "Copy only": "仅复制",
        "Use name for output (-n)": "使用名称作为输出 (-n)",
        "Convert TEX (-t)": "转换 TEX (-t)",
        "No TEX convert": "不转换 TEX",
        "Ignore extensions (-i):": "忽略扩展名 (-i)：",
        "Only extensions (-e):": "仅包含扩展名 (-e)：",
        "Ready...": "就绪...",
        "Select Wallpaper Asset": "选择壁纸资源",
        "No media files found": "未找到媒体文件",
        "Extract the wallpaper first to find video/image files.": "请先解包壁纸以查找视频/图片文件。",
        "Extract the wallpaper first to find video/image/web files.": "请先解包壁纸以查找视频/图片/Web 文件。",
        "%d files found": "找到 %d 个文件",
        "Render Scene Directly": "直接渲染 scene",
        "Use wallpaper-wgpu to render this scene as a live wallpaper.": "使用 wallpaper-wgpu 将此 scene 渲染为动态壁纸。",
        "Render scene directly": "直接渲染 scene",
        "Set this scene wallpaper through the realtime renderer": "通过实时渲染器设置此 scene 壁纸",
        "Render Scene to Video": "渲染 scene 为视频",
        "Use Baked Scene Video": "使用已烘焙 scene 视频",
        "Render scene to video": "渲染 scene 为视频",
        "Use baked scene video": "使用已烘焙 scene 视频",
        "Set existing baked video: %@": "设置已有烘焙视频：%@",
        "Delete Baked Video": "删除已烘焙视频",
        "Delete baked video": "删除已烘焙视频",
        "Render again with new settings": "使用新设置重新渲染",
        "Rendering video... %d%%": "正在渲染视频... %d%%",
        "Bake with wallpaper-wgpu at %@, then set it as a video wallpaper.": "使用 wallpaper-wgpu 按 %@ 烘焙，然后设为视频壁纸。",
        "FPS": "帧率",
        "Duration": "时长",
        "Extract and List Media Files": "解包并列出媒体文件",
        "Extract and list media files": "解包并列出媒体文件",
        "Unpack this wallpaper package, then show its video, image, and web files.": "解包此壁纸包，然后显示其中的视频、图片和 Web 文件。",
        "Render Web Directly": "直接渲染 Web",
        "Use WebKit to render this web wallpaper on the desktop.": "使用 WebKit 在桌面渲染此 Web 壁纸。",
        "Render web directly": "直接渲染 Web",
        "Set this web wallpaper through the WebKit renderer": "通过 WebKit 渲染器设置此 Web 壁纸",
        "Double-tap to set as wallpaper": "双击以设为壁纸",
        "Loading...": "加载中...",
        "Set Frame": "设置当前帧",
        "New Collection": "新建收藏集",
        "Collection name": "收藏集名称",
        "Create": "创建",
        "Loading properties...": "正在加载属性...",
        "No editable scene properties": "没有可编辑的 scene 属性",
        "This wallpaper does not declare configurable properties in project.json.": "此壁纸未在 project.json 中声明可配置属性。",
        "Reset": "重置",
        "Reset All": "全部重置",
        "Done": "完成",
        "Choose file": "选择文件"
    ]
}
