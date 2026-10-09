# Loom for iOS

[English](README.md) | **简体中文**

原生 SwiftUI 多模型并行对话工作台，支持 **iPhone 和 iPad**。使用系统原生 Liquid Glass，最低需要 **iOS / iPadOS 26**。

## 功能

- **自适应阅读**：窄窗口使用模型标签与左右滑动切换；窗口宽度达到 700 pt 时并排显示回答，各列独立滚动。iPhone 仅支持竖屏，iPad 支持横竖屏。切换布局时保留当前模型、草稿和引用。
- **1–5 个模型**：支持 OpenAI 兼容接口与 Anthropic，内置 OpenAI、Claude、Gemini、DeepSeek、千问、Kimi、GLM、Grok 预设。输入 API Key 后获取在线型号，也可手动填写型号。在设置中拖动排序；关闭模型不会删除历史或密钥。
- **高亮与追问**：单击一句快捷高亮，或长按选择文字后使用系统菜单中的“高亮”。设置可改为双击。相邻高亮自动合并，删除引用同步取消原文高亮。所有启用模型收到相同问题与引用，各自保留独立对话上下文。
- **丰富回答**：原生 Markdown、代码块、基础表格、链接与内嵌 SVG。SVG 周围文字仍可选择，SVG 的 JavaScript 和外部资源加载关闭。
- **会话抽屉**：点击左上角按钮或从左边缘拖动，创建、搜索和切换会话。长按会话可删除，并需确认。抽屉底部进入设置，设置中进入备份。
- **阅读控制**：通过左侧轮次标记跳转，每个模型和会话保留独立阅读位置，支持复制提问和分享回答。
- **本地保存与备份**：会话、草稿、高亮、模型配置及偏好保存在本地。通过系统“文件”导出和导入，包括 iCloud 云盘；API Key 默认不导出。
- **请求控制**：向启用模型并行发送、停止生成、重试失败回答。切换会话会取消当前请求。输入框支持多行，并随键盘抬升。

App 界面目前为简体中文，支持系统深色模式、动态字体与 VoiceOver。双语文档不会改变 App 界面语言。

## 预览

使用 `--demo` 启动参数显示本地示例回答，不调用模型服务，也不写入真实会话历史。

| iPhone | iPad |
| --- | --- |
| ![iPhone](docs/iphone.jpg) | ![iPad](docs/ipad.jpg) |

## 在 Xcode 中运行

1. 用 **Xcode 26 或更高版本** 打开 `Loom.xcodeproj`。
2. 选择 `Loom` scheme 和 iPhone / iPad 模拟器，运行。
3. 打开会话抽屉 → 设置，选择厂商、输入 API Key、选择型号并保存。
4. 输入问题，发送给所有启用模型。

真机运行时，在 **Signing & Capabilities** 中选择自己的开发团队。仓库不包含签名证书、描述文件或开发团队 ID。

项目没有第三方运行时依赖。项目配置由 `project.yml` 管理；修改目标或构建设置后重新生成：

```sh
brew install xcodegen
xcodegen generate
```

## 数据与网络

对话与在线型号请求均**直接连接配置的模型服务商**。旧文件和备份中的转发配置可用于迁移读取，但不会恢复转发请求。

- API Key 保存在系统钥匙串（`WhenUnlockedThisDeviceOnly`），不写入日常会话 JSON。只有显式开启相应选项，备份才包含密钥。
- 服务商接收配置的 API Key、会话上下文和高亮引用。连接是否成功取决于服务商接口与设备网络。
- 本地状态位于 App 沙盒的 `Application Support/Loom/state.json`，使用原子写入和系统文件保护。损坏记录会保留，不直接覆盖。
- 文件备份支持手动迁移；没有账号系统、自动跨设备同步或网页历史迁移。
- 回答完整返回后显示，暂不支持流式输出。后台完成没有保证；中断请求在下次启动时变为可重试。
- 删除 App 会删除本地会话；钥匙串凭据可能保留。

## 可选的 iCloud 原生备份

导出至 iCloud 云盘使用系统“文件”选择器。直接云端备份是另一项可选的 CloudKit 功能，使用私有数据库，保留一个可替换的最新归档。

需要在开发者账户配置容器 `iCloud.online.minidesk.loom`、CloudKit 服务及匹配描述文件。使用 `Configuration/iCloud.entitlements`，构建时设置 `CODE_SIGN_ENTITLEMENTS=Configuration/iCloud.entitlements` 和 `SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG LOOM_ICLOUD'`（Release 使用 `LOOM_ICLOUD`）。

发布前，在 CloudKit Console 将 `LoomBackup` 类型及其 `archive`（Asset）、`createdAt`（Date/Time）字段部署至生产环境。开发环境保存可创建 schema，生产环境不能自动创建。没有相应权限时，App 明确提示原生 iCloud 备份不可用。真实云端备份与恢复仍需使用具备权限的构建和已登录的测试账户验证。

## 验证

近期检查使用 Xcode 27 / iOS 27 模拟器，部署目标仍为 iOS 26。

- 36 项单元测试通过，覆盖持久化、备份、高亮、模型启用、请求取消、失败隔离和密钥处理。
- iPhone 旋转检查通过：设备向左右横置时，界面保持竖屏，模型选择与草稿保留。
- iPad mini 旋转与并排阅读检查通过。真机签名构建已安装并启动于 iPhone 15 Pro。
- 网络测试使用模拟服务，不消耗真实模型额度。真实服务商回答需配置自己的密钥并验证网络。
- 当前 Xcode 未提供 iPhone Duo 模拟器，内外屏折叠切换仍需 Duo 设备或对应模拟器验证。触觉反馈及长会话性能需真机评估。

运行测试（替换为本机可用模拟器名称）：

```sh
xcodebuild test -project Loom.xcodeproj -scheme Loom \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO
```

演示预览：在 scheme 的 Run → Arguments 中加入 `--demo`。

## 参与共建与更新记录

欢迎通过 [GitHub Issues](https://github.com/xiangjianan/loom-ios/issues) 和 Pull Request 提交想法、问题与代码。

历次功能、截图与验证记录见[中文更新记录](docs/CHANGELOG.zh-CN.md)。App Store 发布还需准备隐私政策、隐私披露、签名与真实服务商测试。
