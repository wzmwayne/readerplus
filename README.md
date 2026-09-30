# 阅读

多平台小说阅读器，使用 Flutter 重写。Android 与 Linux 桌面共用一套自适应界面，
阅读器排版与交互尽量贴近原版体验，其余界面做简化还原。

## 功能状态

已实现：

- **书架**：网格 / 列表切换、每行列数、按最近阅读 / 书名 / 作者 / 加入时间排序、书名作者搜索、长按操作菜单
- **本地导入**：TXT 与 EPUB 2 / 3
  - TXT：UTF-8 / UTF-8 BOM / GBK 自动识别，按章节标题切分（会过滤正文中误匹配的句子），导入时按清理规则自动做格式清理
  - EPUB：解析 container.xml → OPF → spine，目录兼容 EPUB3 的 `nav.xhtml` 与 EPUB2 的 NCX，按 spine 顺序抽取正文并保留段落
- **TXT 格式清理**：内置规则参考 Legado 的替换净化（去 BOM/零宽字符、去行首行尾空白、合并连续空行、统一省略号、去除广告行、段落合并等），可在设置里逐条启停或恢复默认
- **导航**：标签页 + 内容。竖屏标签在底部（可切换图标 / 图标 + 文字，默认图标）；横屏标签在左侧，默认只显示图标，点左上角按钮展开为图标 + 文字
- **主题**：浅色 / 深色两套默认主题由品牌色生成（取自 https://wzml.cc.cd/logo 的前景颜色 `#76DFA1`），另保留默认 / 典雅蓝 / 黑白 / A屏黑
- **阅读器**：覆盖 / 滑动 / 滚动 / 无动画四种翻页方式；点击左右三分之一翻页、中间呼出菜单
- **排版**：字号、行距、字距、段距、加粗可按需调整；内置 6 套排版预设（数值取自原版默认数据）
- **阅读设置**：夜间模式、亮度调节、页眉页脚内容自由组合（无 / 书名 / 章节名 / 页码 / 进度 / 时间）
- **目录与进度**：左侧目录抽屉、章节滑块、阅读进度自动保存
- **整体配色**：默认 / 典雅蓝 / 黑白 / A屏黑 四套主题
- **数据备份**：导出为单个 zip 备份包、从备份包恢复
- **WebDAV 同步**：以单个备份包为同步单位，支持测试连接、上传、从云端恢复

暂未实现（后续里程碑）：

- 书源规则解析与在线搜索、下载（JS / CSS / XPath / JSONPath 规则引擎）
- 仿真翻页动画、朗读、RSS、字典查询、正文替换净化
- EPUB / UMD 等其它格式解析
- 页脚电量显示、屏幕常亮

## 数据格式

自定义格式，全部保存在应用私有目录（Linux 下为 `~/.local/share/wzmwayne.reader/reader`）：

```
library.json                    书架索引（含 format 与 version 字段）
settings.json                   应用设置
reader_settings.json            阅读设置
webdav.json                     WebDAV 配置
cleaning_rules.json             TXT 格式清理规则
books/<bookId>/chapters.json    章节目录（按字符区间定位）
books/<bookId>/content.txt      书籍正文
```

备份包为 zip，内含 `manifest.json` 与上述数据文件；WebDAV 密码不会写入备份。

## 构建

构建统一由 GitHub Actions 完成（`.github/workflows/ci.yml`，**仅手动触发**，在 Actions 页面
Run workflow 时选择目标）。依赖全部使用官方源，项目内不含任何镜像配置。产物在 Actions
运行页面的 Artifacts 中下载：

| 任务 | 产物 |
| --- | --- |
| `analyze` | `flutter analyze` + `flutter test` 门禁 |
| `android` | `readerplus-android-apk`（Release APK） |
| `linux` | `readerplus-linux-x64.tar.gz`、`readerplus-<版本>-x86_64.AppImage` |

为了兼容性与稳定性，构建环境与工具链全部固定，不使用 `*-latest` 与浮动版本：

| 项 | 固定值 |
| --- | --- |
| 构建环境 | Debian 12（bookworm）容器，系统包版本由发行版冻结；glibc 2.36 |
| 运行器 | `ubuntu-24.04` |
| Flutter | 3.47.0 |
| JDK | 17（Debian `openjdk-17-jdk-headless`） |
| Android 工具链 | cmdline-tools 13114758、platform 36、build-tools 36.0.0、NDK 28.2.13676358 |
| Gradle | 9.3.1（wrapper） |
| AppImage | appimagetool 1.9.1 |
| Actions | 全部固定到具体 release tag |

工作流缓存了 Flutter SDK、pub 依赖、Gradle 依赖与构建缓存、整个 Android SDK 目录
（含 NDK，首次约 1GB）以及 Gradle 发行包，二次编译无需重复下载。

本地构建（可选）需要 x86-64 主机：Android 工具链中的 `aapt2`、`cmake` 官方只提供
x86-64 版本，aarch64 主机需自行提供 binfmt/qemu 模拟。

环境要求：Flutter 3.47.0 stable、JDK 17+（CI 使用 21）；Linux 桌面另需 `clang cmake
ninja-build pkg-config libgtk-3-dev` 与中文字体（如 `fonts-noto-cjk`）；Android 需
SDK Platform 36、Build-Tools 36.0.0 与 NDK 28.2.13676358。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release      # Android，需 x86-64 主机
flutter build linux --release    # Linux 桌面
```

## 支持的平台

| 平台 | 最低版本 |
| --- | --- |
| Android | 7.0（API 24，取自 `flutter.minSdkVersion`；compileSdk / targetSdk 36） |
| Linux 桌面 | glibc ≥ 2.36（构建基线 Debian 12，兼容 Ubuntu 22.04+） |

## 目录结构

```
lib/
  main.dart                 应用入口与主题装配
  models/                   数据模型（书籍、章节、阅读设置、应用设置）
  services/                 存储、导入（TXT / EPUB）、文本清理、备份、WebDAV、同步
  state/                    全局状态（书架、设置、同步）
  reader/                   阅读器界面与分页引擎
  pages/                    应用外壳（标签页 + 内容）、书架页、设置页、WebDAV 页
  widgets/                  通用组件
  theme/                    主题配色与中文字形回退
test/                       单元测试（导入切分、分页、备份往返）
.github/workflows/ci.yml 分析与构建工作流（Android APK、Linux 桌面 + AppImage）
packaging/linux/             AppImage 打包脚本、桌面项与图标
packaging/icon/              图标生成脚本（极简黑白书本）
```

## 来源与致谢

本项目是独立仓库、独立历史的实现，**部分设计思路来自开源项目 Legado（开源阅读）**：
阅读器的排版预设数值（原 `readConfig`）、主题配色（原 `themeConfig`），以及页眉页脚、
翻页方式（覆盖 / 滑动 / 滚动 / 无动画）等交互设计，均参考了该项目的实现与默认数据。

Legado 以 GPL-3.0 发布，本项目沿用同一许可证，并保留其原始版权声明。

品牌色取自 https://wzml.cc.cd/logo 的前景颜色 `#76DFA1`，浅色与深色主题都由它生成。

## 许可证

GPL-3.0，详见 [LICENSE](LICENSE)。
