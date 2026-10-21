import Foundation

/// Tiny in-app localization layer (no String Catalogs needed).
/// Views read `@AppStorage("uiLanguage")` so they re-render live when it changes,
/// then call `L10n.t(key, uiLanguage)`.
enum L10n {
    static let defaultsKey = "uiLanguage"   // "system" | "zh" | "en"

    static var currentPreference: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? "system"
    }

    static func resolved(_ pref: String) -> String {
        if pref == "zh" || pref == "en" { return pref }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? "zh" : "en"
    }

    static func t(_ key: String, _ pref: String = currentPreference) -> String {
        let table = resolved(pref) == "zh" ? zh : en
        return table[key] ?? en[key] ?? key
    }

    static func f(_ key: String, _ pref: String, _ args: CVarArg...) -> String {
        String(format: t(key, pref), arguments: args)
    }

    static let en: [String: String] = [
        "find": "Find…", "findReplace": "Find and Replace…", "findNext": "Find Next",
        "findPrev": "Find Previous", "useSelection": "Use Selection for Find",
        "softWrap": "Soft Wrap", "preview": "Preview", "sidebar": "Sidebar",
        "toggleSoftWrap": "Toggle Soft Wrap", "togglePreview": "Toggle Markdown Preview",
        "toggleSidebar": "Toggle Sidebar", "softWrapHelp": "Toggle soft wrap (⌥⌘W)",
        "previewHelp": "Toggle Markdown preview (⇧⌘P)", "sidebarHelp": "Toggle folder sidebar",
        "openFolder": "Open Folder…", "closeFolder": "Close Folder", "goToLine": "Go to Line…",
        "toggleComment": "Toggle Comment", "duplicateLine": "Duplicate Line",
        "moveUp": "Move Line Up", "moveDown": "Move Line Down", "exportHTML": "Export Markdown as HTML…",
        "lnCol": "Ln %ld, Col %ld", "counts": "%ld words, %ld chars", "wrap": "Wrap", "noWrap": "No Wrap",
        "autoDetect": "Auto Detect", "theme": "Theme", "themeAuto": "Automatic (One Dark / One Light)",
        "fontSize": "Font size: %ld pt", "tabWidth": "Tab width: %ld spaces",
        "softWrapDefault": "Soft wrap by default (new windows)",
        "autosave": "Auto-save edited files every 20 seconds", "uiLanguage": "Interface language",
        "langSystem": "Follow System", "cancel": "Cancel", "go": "Go",
        "goToLinePrompt": "Line number (1–%ld):", "exportFailed": "Export failed",
        "noFolder": "No folder open", "chooseFolder": "Open Folder…", "folderEmpty": "Empty folder",
        "workspace": "Workspace", "addFolder": "Add Folder to Workspace…", "removeFolder": "Remove Folder from Workspace",
        "revealInFinder": "Reveal in Finder", "refresh": "Refresh",
        "ok": "OK", "editor": "Editor", "general": "General",
        "encoding": "Encoding", "reopenWithEncoding": "Reopen with Encoding",
        "encUTF8": "UTF-8", "encGB18030": "GB18030", "encISO88591": "ISO-8859-1", "encUTF16": "UTF-16",
        "findInFiles": "Find in Files…", "searchPlaceholder": "Search in workspace folders",
        "search": "Search", "noResults": "No results", "resultsCount": "%ld results",
        "searching": "Searching…", "useRegex": "Regular Expression", "caseSensitive": "Case Sensitive",
        "outline": "Outline", "outlineHelp": "Toggle document outline", "outlineEmpty": "No symbols",
        "toggleOutline": "Toggle Outline",
        "selectNextOccurrence": "Select Next Occurrence",
        "addCursorBelow": "Add Cursor Below", "addCursorAbove": "Add Cursor Above",
        "fold": "Fold", "unfoldAll": "Unfold All",
        "toggleInvisibles": "Show Invisible Characters",
        "toggleIndentGuides": "Show Indent Guides",
        "indentGuides": "Indent guides", "invisibles": "Invisible characters",
        "findMatch": "%ld/%ld",
        "fileChangedTitle": "File Changed on Disk",
        "fileChangedBody": "“%@” was modified by another application. Reload from disk?",
        "reload": "Reload", "keepEditing": "Keep Editing",
    ]

    static let zh: [String: String] = [
        "find": "查找…", "findReplace": "查找和替换…", "findNext": "查找下一个",
        "findPrev": "查找上一个", "useSelection": "用所选内容查找",
        "softWrap": "自动换行", "preview": "预览", "sidebar": "侧边栏",
        "toggleSoftWrap": "切换自动换行", "togglePreview": "切换 Markdown 预览",
        "toggleSidebar": "切换侧边栏", "softWrapHelp": "切换自动换行（⌥⌘W）",
        "previewHelp": "切换 Markdown 预览（⇧⌘P）", "sidebarHelp": "切换文件夹侧边栏",
        "openFolder": "打开文件夹…", "closeFolder": "关闭文件夹", "goToLine": "跳转到行…",
        "toggleComment": "切换注释", "duplicateLine": "复制当前行",
        "moveUp": "上移行", "moveDown": "下移行", "exportHTML": "将 Markdown 导出为 HTML…",
        "lnCol": "行 %ld，列 %ld", "counts": "%ld 词，%ld 字符", "wrap": "自动换行", "noWrap": "不换行",
        "autoDetect": "自动检测", "theme": "主题", "themeAuto": "自动（One Dark / One Light）",
        "fontSize": "字号：%ld pt", "tabWidth": "Tab 宽度：%ld 个空格",
        "softWrapDefault": "新窗口默认自动换行",
        "autosave": "每 20 秒自动保存已修改的文件", "uiLanguage": "界面语言",
        "langSystem": "跟随系统", "cancel": "取消", "go": "跳转",
        "goToLinePrompt": "行号（1–%ld）：", "exportFailed": "导出失败",
        "noFolder": "未打开文件夹", "chooseFolder": "打开文件夹…", "folderEmpty": "空文件夹",
        "workspace": "工作区", "addFolder": "将文件夹添加到工作区…", "removeFolder": "从工作区移除文件夹",
        "revealInFinder": "在访达中显示", "refresh": "刷新",
        "ok": "好", "editor": "编辑器", "general": "通用",
        "encoding": "编码", "reopenWithEncoding": "以编码重新打开",
        "encUTF8": "UTF-8", "encGB18030": "GB18030", "encISO88591": "ISO-8859-1", "encUTF16": "UTF-16",
        "findInFiles": "在文件夹中查找…", "searchPlaceholder": "在工作区文件夹中搜索",
        "search": "搜索", "noResults": "无结果", "resultsCount": "%ld 条结果",
        "searching": "搜索中…", "useRegex": "正则表达式", "caseSensitive": "区分大小写",
        "outline": "大纲", "outlineHelp": "切换文档大纲", "outlineEmpty": "无符号",
        "toggleOutline": "切换大纲",
        "selectNextOccurrence": "选择下一个匹配项",
        "addCursorBelow": "在下方添加光标", "addCursorAbove": "在上方添加光标",
        "fold": "折叠", "unfoldAll": "全部展开",
        "toggleInvisibles": "显示不可见字符",
        "toggleIndentGuides": "显示缩进参考线",
        "indentGuides": "缩进参考线", "invisibles": "不可见字符",
        "findMatch": "%ld/%ld",
        "fileChangedTitle": "磁盘上的文件已更改",
        "fileChangedBody": "“%@”已被其他应用修改。要从磁盘重新加载吗？",
        "reload": "重新加载", "keepEditing": "继续编辑",
    ]
}
