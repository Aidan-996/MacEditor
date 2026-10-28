# MacEditor

原生 macOS 轻量代码 / Markdown 编辑器（Swift + SwiftUI + AppKit），支持 macOS 13+。
**只需 Command Line Tools 就能构建，不需要 Xcode**。代码里没有用任何 SwiftUI 宏（`@State`、`@Observable`、`#Preview`、`@Entry`），也没有用 String Catalog。

## 功能

### 文档与窗口
- 基于 `DocumentGroup`：新建、打开、保存、另存为、**打开最近使用**（系统标准菜单）、未保存标记、关闭时提示保存。
- 原生窗口标签页（窗口 → 合并所有窗口）。工具栏是紧凑统一样式，标题栏透明、跟随主题配色。
- 双击标题栏、工具栏空白处，或侧边栏的标题区和空白区域，可以让窗口铺满屏幕，再次双击恢复。会遵循系统设置中“连按窗口标题栏”的行为（缩放 / 最小化 / 无操作）。
- 拖拽打开：把文件拖到 Dock 图标或编辑区就会打开。
- **多根工作区侧边栏**（类似 VS Code）：用 文件 → 打开文件夹…（⇧⌘O，可多选）或侧边栏顶部的 “+” 添加文件夹。每个根文件夹是一个可折叠的分组；悬停可以刷新或移除，右键可以在访达中显示、刷新、移除。根文件夹列表会保存，所有窗口共享，下次启动时恢复（已不存在的路径会跳过）。默认忽略 .git、.build、node_modules、.DS_Store。点击文件会作为文档打开。用工具栏按钮或 ⌃⌘S 显示/隐藏。侧边栏用 **FSEvents** 监听根目录变化并自动刷新。**在文件夹中查找**（⇧⌘F 或侧边栏放大镜）可搜索工作区内的文本文件。
- **自动保存**：NSDocument 自带“原位自动保存”。偏好设置里还可以开启“每 20 秒自动保存已修改的文件”。
- **导出 HTML**：Markdown 文档可以通过 文件 → 将 Markdown 导出为 HTML… 导出。

### 编辑
- 撤销 / 重做（每个文档独立）、换行时自动缩进、Tab 插入空格。
- 查找替换：使用系统查找栏，支持增量搜索和正则（在放大镜菜单里设置）。快捷键：⌘F、⌥⌘F、⌘G、⇧⌘G、⌘E。
- **跳转到行**（⌘L）、**切换注释**（⌘/，按语言使用 `//`、`#`、`<!-- -->` 或 `/* */`）、**复制当前行**（⇧⌘D）、**上移 / 下移行**（⌥⌘↑ / ⌥⌘↓）。
- 括号匹配高亮、当前行高亮。
- 自动换行切换（⌥⌘W）。
- **多光标 / 列选择**：⌥点击添加光标，⌥拖拽列选，⌃⇧↑/↓ 在上下行加光标，⌘D 选择下一处相同文本；输入与退格会作用到所有光标。
- **缩进折叠**：行号栏折叠标记（▾/▸），⌥⌘[ 折叠当前块，⌥⌘] 全部展开。
- **不可见字符**（⌥⌘I）与 **缩进参考线**（偏好设置 / 菜单可关）。
- 系统查找栏旁显示匹配计数（如 `2/5`，基于查找剪贴板）。

### 外观
- 内置主题：One Dark、One Light、Tokyo Night、GitHub Light。“自动”模式会跟随系统深浅色。
- 编辑区背景、行号栏、当前行、选区、光标、状态栏全部由主题统一配色。
- 默认字体为 SF Mono 13pt，行高 1.4，内边距 12×10。
- 行号栏：右对齐、次要行号偏暗、当前行号高亮。软换行时，行号与每个逻辑行的第一视觉行对齐。

### 语言与高亮
- 正则语法高亮，支持 Swift、Python、JavaScript、TypeScript、JSON、Markdown、C、C++/ObjC、Go、Rust、HTML/XML（包括内嵌的 `<style>` CSS 和 `<script>` JS）、CSS、Shell。
- 输入时增量加防抖：先立即重新着色当前行，0.3 秒后再做一次全量着色。
- **按内容识别语言**：无扩展名或未命名文档会按内容嗅探（HTML、JSON、shebang、Python、Markdown 等），内容变化后防抖重新检测。状态栏的语言菜单可以手动指定语言。

### 其他
- 编码检测：识别 UTF-8 / UTF-16 BOM；严格 UTF-8，失败则试 GB18030；两者都合法时用 GBK 字节密度与乱码启发式（**绝不**走有损 UTF-8 回退）。状态栏编码可点选 UTF-8 / GB18030 / ISO-8859-1 / UTF-16 重新解码。保存时保留原编码和原换行符。
- 状态栏显示：行 / 列（光标移动和编辑时实时更新）、词数 / 字符数（每个中日韩字符算 1 个词，连续的英文字母或数字算 1 个词；字符数为 Character 个数，含换行）、换行模式、**可切换的**编码、LF/CRLF、语言。
- Markdown 实时分栏预览（WKWebView，配色跟随主题），⇧⌘P 切换。
- **大纲**（⇧⌘B / 工具栏）：Markdown 标题或代码中的函数/类型符号，点击跳转。
- **磁盘变更提示**：已打开文件被其他应用修改时询问是否重新加载。
- **在文件夹中查找**支持正则、区分大小写，点击结果打开并跳到对应行。
- **界面语言可切换为中文或英文**（偏好设置 → 界面语言，默认跟随系统），切换后菜单、工具栏、状态栏、偏好设置、对话框立即更新。系统自带的标准菜单项（如“文件”“编辑”）由 macOS 本地化。
- 偏好设置（⌘,）：界面语言、主题、字号、Tab 宽度、默认自动换行、自动保存。

## 构建

需要 macOS 13+，以及 Command Line Tools（Swift 5.9+）或 Xcode。

```bash
swift run                 # 直接运行（调试用，没有 .app 包）
swift test                # 跑单元测试（Swift Testing，覆盖折叠/大纲/编码探测等纯逻辑）
./build_app.sh            # 生成 build/MacEditor.app（含 Info.plist、图标、ad-hoc 签名）
./build_dmg.sh            # 生成 dist/MacEditor-1.0.0.dmg（能做通用二进制就做，否则构建本机架构）
open Package.swift        # 如果装了 Xcode，也可以用 Xcode 打开
```

图标由 `Resources/AppIcon.png` 通过 `sips` 和 `iconutil` 生成。这一步失败也不影响构建。

## 安装

1. 打开 `MacEditor-1.0.0.dmg`，把 MacEditor 拖到 “Applications”。
2. 应用只做了 ad-hoc 签名，没有经过 Apple 公证。第一次启动时请在 Finder 中**右键点击 → 打开**，或者执行：
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacEditor.app
   ```

## 项目结构

```
MacEditor/
├── Package.swift / build_app.sh / build_dmg.sh
├── Resources/Info.plist, AppIcon.png
├── Tests/MacEditorTests/     # Swift Testing（折叠/大纲/编码探测/字数统计等纯逻辑）
└── Sources/MacEditor/
    ├── MacEditorApp.swift        # 入口、DocumentGroup、AppDelegate（标签页、自动保存）
    ├── Commands.swift            # 菜单命令（FocusedValue）
    ├── L10n.swift                # 中英文字符串表
    ├── EditorUIState.swift       # 每个窗口的 ObservableObject 状态（侧边栏、跳转、导出、统计）
    ├── ContentView.swift         # 布局、工具栏、状态栏、跳转到行面板、窗口样式
    ├── FileTreeView.swift        # 文件夹树
    ├── EditorTextView.swift      # 用 NSViewRepresentable 包装 NSTextView（TextKit 1）
    ├── CodeTextView.swift        # 缩进、注释、复制/移动行、括号匹配、当前行
    ├── LineNumberRulerView.swift # 行号栏
    ├── Highlighter.swift / Theme.swift / Language.swift
    ├── MarkdownPreview.swift     # 预览 + Markdown→HTML
    ├── TextDocument.swift        # 编码与换行符
    ├── EditorFeatures.swift     # 折叠 / 大纲 / 查找计数 / 文件监视
    └── PreferencesView.swift
```

## 路线图

- [x] 文件树侧边栏（基础版）
- [x] 多光标 / 列编辑
- [x] 代码折叠（按缩进）
- [ ] 内置终端
- [ ] Git 集成
- [ ] LSP（补全、跳转、诊断）
- [ ] 插件系统
- [ ] 大文件优化（只高亮可见区域、后台高亮、TextKit 2）
- [ ] tree-sitter 高亮、更多主题
- [x] 侧边栏文件监听、搜索整个文件夹
