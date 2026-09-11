# 教材查看器 · tchmaterial-quick-viewer

> [!WARNING]
> **This project is 100% written by AI, use at your own risk**
>
> 本项目（含全部源码、注释、测试与文档）完全由 AI 生成，未经人工逐行审阅。请自行
> 评估后再使用，尤其注意：
> - 登录凭据（Cookie / `access_token` / `mac_key`）由你自行提供，请先确认代码如何
>   处理它们；
> - 自动下载可能与平台服务条款冲突，后果自负；
> - 不提供任何形式的担保，详见 [LICENSE](LICENSE)。

国家中小学智慧教育平台（[basic.smartedu.cn](https://basic.smartedu.cn/)）**电子课本浏览器**，Flutter 编写，桌面端与移动端通用。

数据接口与 `X-ND-AUTH` 签名规则参考开源项目 [happycola233/tchMaterial-parser](https://github.com/happycola233/tchMaterial-parser)，本仓库是其 Flutter 重写 + 图形化浏览实现。

---

## ✨ 功能

| 功能 | 说明 |
|---|---|
| 🌳 **完整分类树** | 解析平台 `tch_material_tag.json`，还原「教材 → 学段 → 学科 → 版本 → 年级 → 册次」六层结构，支持任意层级的展开/收起与逐级计数 |
| 📚 **全库浏览** | 一次拉取全部 **3,574 本**教材（4 个分片，约 40 MB），磁盘缓存 + 平台版本号失效判断 |
| 🔍 **多词检索** | 书名 / 学科 / 版本 / 年级跨字段 AND 搜索 |
| 🖼️ **封面墙** | 从 `custom_properties.preview` 取首页缩略图作封面（92% 的教材有封面） |
| 📖 **内置阅读器** | 基于 pdfrx/pdfium 的 PDF 阅读，带**可逐级展开的目录**（合并 `ebook_mapping` 页码与章节树，缺失时回退到 PDF 自带书签），**默认只展开第一级**；目录显示**书上印刷的页码** |
| ⬇️ **下载与离线** | 流式下载、进度显示、中断不留残文件（先写 `.part` 再改名）；教材直接存到 **`下载/tchMaterial/`**，文件管理器里能直接找到 |
| 📤 **外部打开与分享** | 详情页 / 阅读器 / 书架都能「用系统程序打开」和「分享」。Android 走自建 FileProvider + `ACTION_VIEW`（**不引入多余权限**），桌面端走 `url_launcher`，分享走 `share_plus` |
| 🔑 **凭据管理** | 支持直接粘贴浏览器 Cookie（自动解出 `access_token` / `mac_key` / `diff`）或纯 JSON |
| 🌗 **明暗主题** | Material 3，跟随系统 / 手动切换 |

## 🚀 平台支持与构建

| 平台 | 状态 | 产物 |
|---|---|---|
| **Linux** x64 | ✅ 已验证 | `tchmaterial-quick-viewer-linux-x64.tar.gz` |
| **Windows** x64 | ✅ CI 构建 | `tchmaterial-quick-viewer-windows-x64.zip` |
| **macOS** | ✅ CI 构建 | `tchmaterial-quick-viewer-macos.zip` |
| **Android** | ✅ 已验证 | `app-arm64-v8a-release.apk` 等（按 ABI 拆分） |
| **iOS** | ⚠️ CI 出未签名包 | `tchmaterial-quick-viewer-ios-unsigned.zip`（需自行侧载） |
| **Web** | ❌ 不支持 | —— |

推送 `main` 或提 PR 会触发 [`.github/workflows/build.yml`](.github/workflows/build.yml)
构建全平台产物；打 `v*` tag 会走
[`.github/workflows/release.yml`](.github/workflows/release.yml) 自动发布 Release 并附上所有产物。

### 为什么 Web 不支持

`path_provider` **没有 web 实现**（依赖里只有 android / foundation / linux / windows），
而本应用靠它拿到应用目录来缓存教材。所以 `flutter build web` 能编译通过，但一打开
`main()` 里的存储初始化就抛异常 —— 属于「能构建、跑不起来」的假产物，因此没有纳入 CI。

`main()` 里加了兜底：存储初始化失败时会渲染一个说明页面（而不是留一片白屏），
所以真有人自己 build web，看到的也是「Web 平台不受支持，请改用桌面端或 Android」
而不是空白页。要真正支持 Web，得把本地存储换成 IndexedDB、并把 PDF 阅读改为
浏览器原生的 blob 方案，工作量不小。

### 本地构建

```bash
flutter pub get

# Linux 桌面（需要 GTK 开发库）
sudo apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev
flutter build linux --release
./build/linux/x64/release/bundle/tchmaterial_quick_viewer

# Android（按 ABI 拆分，体积小很多）
flutter build apk --release --split-per-abi

# Windows / macOS / iOS
flutter build windows --release
flutter build macos   --release
flutter build ios     --release --no-codesign   # 未签名，需自行侧载
```

> **Android 构建必须用 JDK 17–21。** JDK 22+ 会让 AGP 9.x 的 `JdkImageTransform`
> 调用 `jlink` 失败，报 `Could not resolve all files for configuration
> ':jni:androidJdkImage'` —— Flutter 自己的提示会误导你去升级 AGP，其实与 AGP
> 版本无关。CI 里已固定 `java-version: '21'`。

## 🧪 测试

```bash
flutter test     # 112 个用例
```

分七组：

- `nd_auth_test.dart` —— 签名算法。期望值由参考项目的 Python 实现生成，逐字节比对
- `catalog_index_test.dart` —— 分类树解析与归属，含平台复用 `tag_id` 的回归用例
- `credentials_test.dart` —— Cookie / JSON / 裸 token 三种粘贴形式的解析
- `anonymous_access_test.dart` —— 用 `MockClient` **拦截真实发出的请求头**，
  约束「匿名就是真匿名」「公开接口不泄露凭据」
- `real_catalog_test.dart` —— 用**真实平台缓存**校验结构不变量：父子计数、教材总数、
  以及「落点必须是 `tag_paths` 那一支的后代」（无缓存时自动跳过；可用环境变量
  `TCHVIEWER_CATALOG` 指定缓存路径）
- `outline_panel_test.dart` —— 目录面板：默认只展开第一级、逐级展开/收起、无「全部展开」入口
- `category_tree_panel_test.dart` —— 分类树：默认不递归展开、共享 `tag_id` 的两个节点能独立收起
- `controller_test.dart` —— 三个控制器的通知路径与 dispose 守卫
- `widget_test.dart` —— 分类树面板与书卡渲染

## 🏗️ 结构

```
lib/src/
  core/
    nd_auth.dart            X-ND-AUTH HMAC-SHA256 签名（auth.py 的 Dart 移植）
    api_client.dart         平台端点 + 带签名的 HTTP 客户端
    platform_support.dart   平台能力判定
  models/                   分类、教材、凭据
  data/
    catalog_index.dart      纯逻辑：分类树解析 + 索引构建（可脱离网络测试）
    catalog_repository.dart 拉取 / 缓存 / 详情解析 / 下载
    local_store.dart        偏好与磁盘缓存
  state/                    ChangeNotifier 控制器
  ui/                       Material 3 界面
```

签名要点（与参考实现一致，改动前请先看 `nd_auth.dart` 的注释）：

```
nonce = (Date.now() + diff) + ":" + 8 位 [0-9A-Z]
原文  = "{nonce}\n{METHOD}\n{百分号解码后的 path}{?query}\n{hostname}\n"   ← 末尾必须有空行
mac   = Base64(HMAC-SHA256(mac_key, 原文))
头    = MAC id="{access_token}",nonce="{nonce}",mac="{mac}"
```

中文文件名**必须先 `unquote` 再签名**，`query` 原样保留，`hostname` 不含端口。

## ⚠️ 实测结论与已知限制

以下数字来自对平台真实数据的抽样，不是估计：

- **分类树会复用 `tag_id`。** 全部 80 个「一年级」节点共用同一个 `tag_id`，
  56 个版本节点、28 个学科节点同样如此。因此教材归并**必须按节点路径**而不是节点
  id，否则兄弟分支会互相污染 —— 表现为「统编版 104 本」下面挂着「一年级 150 本」。
  代码里用 `CategoryNode.uniqueKey` 处理，并有用例守着 —— 索引层和 UI 层
  （分类树的收起状态）都踩过这个坑。
- **目录页码要用 `front_page` 换算，不能直接显示 PDF 页号。** 平台的
  `ebook_mapping` 顶层有个 `front_page` 字段（前置页数：封面、目录等），
  `page_number = 印刷页码 + front_page`。实测某教材 `front_page=5`：目录页印着
  「第一单元 / 1」，映射给的却是 `6`，差值恒为 5。直接显示 `P6` 会让用户对着书
  核对时认为导航不准 —— 跳转本身是准的，不准的是那个数字。
  另外已确认 `page_number` 是 **1-based 绝对 PDF 页索引**（和
  `PdfViewerController.goToPage` 的语义一致），不存在差一页的问题。
- **这些教材 PDF 没有自带书签。** 两份样本的 `/Outlines`、`/Dest` 全为 0，所以
  「回退到 PDF 书签」这条路径对平台教材基本不会触发。代码里仍然实现了它，并且
  会用 `PdfDest` 的 `command`/`params` 还原**页内纵向偏移**（`xyz` 是
  `[left, top, zoom]`，`fitH`/`fitBH` 是 `[top]`），交给 pdfrx 的 `goToDest`
  按 PDF 规范换算 —— 只取页码会把本该落在标题处的跳转丢到页顶。
- **18% 的教材没有分类信息。** 654 本「课程教学指南」类资源的 `tag_list` 是空数组，
  会归入「未分类」而不是被丢弃。
- **约 19% 的教材平台未开放直链。** 随机抽样 160 本：`81.2%` 可正常解析并下载，
  `18.8%` 返回 403，主要是「体育与健康教师用书」一类教师用书。
  **实测这类资源即使带上有效 Cookie 也仍然 403**（对多个端点、串行/并发、匿名/登录
  都验证过），属于平台策略，与凭据无关。
- **「匿名」是真的匿名。** 未配置凭据时请求头只有固定占位值
  `Authorization: Bearer 0` 与 `X-ND-AUTH: MAC id="0",nonce="0",mac="0"`，不含
  access_token、mac_key、账号 id 或 Cookie（`anonymous_access_test.dart` 会把这条
  约束钉住）。公开元数据接口即使已配置凭据也仍走占位头，不会泄露 token。
- **pdfium 没有 GPU 光栅化后端。** 把某一页画成位图这一步永远在 CPU 上；GPU
  （Impeller）负责的只是把已光栅化的页位图合成上屏。所以「卡」基本来自
  「频繁重新光栅化」或「每帧做多余的活」，而不是「没开 GPU」。阅读器据此关掉了
  文本选择层、去掉了页投影、把预渲染范围收到半屏，并启用低分辨率预览与按需测页。
  实测：打开 70 页教材首屏 10 ms，连续滚动 25 页日志零异常。
  > 特别地，pdfrx 默认开启的文本选择层会在绘制每页时调用
  > `enumerateFragmentBoundingRects()`；扫描件的文本片段下标容易越界，会导致每帧抛
  > `RangeError: Invalid value: Not in inclusive range 0..24: -1` 刷屏。本项目已关闭该层。
- 移动端不提供「用系统程序打开」：Android 从 API 24 起禁止跨应用传 `file://`
  （需要自建 FileProvider），而内置阅读器已经够用。
- **目录默认只展开第一级，全仓不做递归展平。** 目录的用途是定位，一次性把整棵树
  铺开会铺出上百条记录，既难找又卡；`Chapter` 上刻意不提供 `flatten()` 之类的
  工具，分类树的层级提示也改成有界下钻（O(深度)）而不是遍历整棵子树。
  目录面板在宽度 ≥ 900 时是侧栏，窄屏/手机上是底部弹层 —— 早期版本把面板写成
  `showOutline && width >= 1000`，窄屏下按钮照样在切换状态却什么都不发生，
  手机上等于完全打不开。

## 📜 免责声明

本项目只读取国家中小学智慧教育平台已公开的教材文件，不存储、不传播、不修改任何
内容，也不绕过任何付费或权限机制。请遵守平台的服务条款，仅将下载内容用于个人学习。
教材版权归各出版单位所有。

## 📄 许可证

MIT
