# Loom for iOS

原生 SwiftUI 多模型并行对话工作台，支持 **iPhone 和 iPad**。使用系统原生 Liquid Glass，最低需要 **iOS / iPadOS 26**。

## 两种阅读方式

- **iPhone**：单列回答，顶部玻璃模型标签；点击标签或左右滑动切换，底部输入框固定在阅读区下方，并随键盘抬升。
- **iPad**：宽窗口并排阅读模型回答，各列独立滚动；列数多时支持横向滚动。窗口宽度小于 700 pt 时自动使用单列标签布局。
- **自动高亮**：长按选中文字，选区稳定 650 ms 后自动高亮，并加入下一轮引用。扩大选区会替换重叠引用，避免重复。
- **引用追问**：所有模型收到相同的问题和带来源、型号、轮次的高亮引用；各自保留独立对话上下文。
- **1–5 个模型**：支持 OpenAI 兼容接口与 Anthropic，提供在线模型列表和手动型号输入。
- **历史对话**：本地保存对话、草稿、引用和高亮，支持搜索、删除、轮次跳转和分享回答。
- **请求控制**：并行请求、停止生成、单列失败重试；切换对话会先取消当前请求。

## 预览

截图使用 `--demo` 启动参数，回答为本地示例，不会调用真实模型。

| iPhone | iPad |
| --- | --- |
| ![iPhone](docs/iphone.jpg) | ![iPad](docs/ipad.jpg) |

## 在 Xcode 中运行

1. 用 **Xcode 26 或更高版本** 打开 `Loom.xcodeproj`。
2. 选择 `Loom` scheme 和 iPhone / iPad 模拟器，运行。
3. 点右上角模型设置，为每个模型填写接入地址、API Key 和型号，保存。
4. 同时向所有配置模型发送问题；只需要一个模型时，可以在设置中移除另一个。

真机运行时，在 `Signing & Capabilities` 中选择自己的开发团队。仓库不包含签名证书、描述文件或开发团队 ID。

项目配置由 `project.yml` 管理；修改目标或构建设置后可重新生成：

```sh
brew install xcodegen
xcodegen generate
```

项目没有第三方运行时依赖。默认界面为中文，支持系统深色模式、动态字体和 VoiceOver。原生玻璃效果由 `glassEffect`、`GlassEffectContainer`、玻璃按钮样式和系统工具栏提供。

## 后端与数据

默认**直接连接模型服务商**，不依赖 Loom 后端。在设置中开启「使用转发服务」后，可复用网页后端。预填转发服务：`https://relay.minidesk.online:8443/loom`，兼容网页 Loom 的 `/api/chat` 与 `/api/models`。可在设置中更换 HTTPS 转发服务。

- API Key 保存在系统钥匙串（`WhenUnlockedThisDeviceOnly`），不写入对话 JSON，不提交到仓库。
- 直连模式仅向配置的服务商发送 API Key、对话上下文和高亮引用；转发模式还会经过所配置的转发服务。请使用可信任的转发服务，并查看对应提供商的数据政策。
- 对话存于 App 沙盒的 `Application Support/Loom/state.json`，使用原子写入和系统文件保护。
- 本地记录损坏时保留原文件并显示提示，不覆盖原记录。
- 本版本不提供账号、跨设备同步或网页历史迁移。
- 本版本使用完整响应接口，回答完成后显示；暂不支持流式输出。
- 后台运行并无完成保证。应用被结束后，再次打开会将未完成请求标为可重试。

删除 App 会删除本地对话；钥匙串凭据可能被系统保留。正式发布前需要准备隐私政策、App Store 隐私披露、签名和真实服务商联调。

## 验证

本地使用 Xcode 27 / iOS 27 模拟器验证，部署目标仍为 iOS 26。

- iPhone：12 项单元测试和 2 项界面测试通过，覆盖标签点击、左右滑动、输入框、设置和自动高亮。
- iPad：自动高亮测试通过；并排阅读、固定输入框及横竖屏切换测试通过。
- 共 12 项单元测试、3 项设备对应的界面测试已通过；iPhone / iPad 专属布局测试在另一种设备上会跳过。
- 单元测试覆盖 Unicode 选区、引用去重与展开、草稿与历史恢复、损坏文件保护、请求中断恢复、请求取消隔离、并行失败隔离、重试和 Key 错误信息脱敏。
- OpenAI 兼容、Anthropic 直连以及转发模式均有模拟网络测试。现有转发服务在开发环境的 HTTPS 健康检查未连通，因此默认使用直连。
- 网络测试使用模拟服务，没有使用真实 API Key 或产生模型费用。真实模型回答仍需用户配置账号后验证。

运行测试（替换为本机模拟器名称）：

```sh
xcodebuild test -project Loom.xcodeproj -scheme Loom \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO
```

演示预览：在 scheme 的 Run → Arguments 中加入 `--demo`。演示数据不会写入真实历史。
