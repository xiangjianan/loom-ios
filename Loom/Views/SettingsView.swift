import SwiftUI

struct SettingsView: View {
    @Bindable var store: LoomStore
    @Environment(\.dismiss) private var dismiss
    @State private var showBackup = false
    @State private var clearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.configurations) { configuration in
                        HStack {
                            NavigationLink {
                                ModelEditor(store: store, configuration: configuration)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkle").foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(configuration.name)
                                        Text(configuration.model.isEmpty ? "尚未配置" : configuration.model)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !store.key(for: configuration.id).isEmpty { Image(systemName: "key.fill").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            Toggle("启用模型：\(configuration.name)", isOn: Binding(
                                get: { store.isModelEnabled(configuration.id) },
                                set: { store.setModelEnabled(configuration.id, enabled: $0) }
                            ))
                            .labelsHidden()
                            .accessibilityLabel("启用模型：\(configuration.name)")
                            .accessibilityIdentifier("model-enabled-\(configuration.id)")
                        }
                    }
                    if store.configurations.count < 5 {
                        NavigationLink {
                            ModelEditor(store: store, configuration: ModelConfiguration(name: "", endpoint: "https://api.openai.com/v1", model: ""))
                        } label: { Label("添加模型", systemImage: "plus") }
                    }
                } header: { Text("模型 · 最多 5 个") } footer: {
                    Text("关闭模型后，不发送新消息并隐藏其对话页面；重新开启会恢复显示，历史记录不会删除。生成中暂不能切换。API Key 存在系统钥匙串，修改模型接口或型号后请新建对话。")
                }.disabled(store.isWorking)
                Section("连接") {
                    Label("直接连接模型服务商", systemImage: "network")
                    Text("API Key、对话上下文及引用直接发送至你配置的模型接口，不经过 Loom 后端。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Picker("句子快捷高亮", selection: $store.singleTapHighlight) {
                        Text("双击句子").tag(false)
                        Text("单击句子").tag(true)
                    }.pickerStyle(.menu).accessibilityIdentifier("sentence-highlight-mode").onChange(of: store.singleTapHighlight) { _, _ in store.save() }
                    Button("清除当前对话的所有高亮", role: .destructive) { clearConfirmation = true }
                } header: { Text("阅读") } footer: { Text("默认单击一句即可高亮，再单击同一句取消；也可改为双击。长按使用系统选区菜单，拖动手柄可精确选择多行。移除引用标签也会取消对应高亮。") }
                Section("数据") {
                    Button { showBackup = true } label: {
                        Label("备份与恢复", systemImage: "externaldrive")
                    }.accessibilityIdentifier("settings-backup")
                }
                Section {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Text("Loom 让多个模型的观点交织，帮助你继续思考。对话与高亮保存在本地，暂不与网页或其他设备同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("参与共建", destination: URL(string: "https://github.com/xiangjianan/loom-ios")!)
                    Text("共享源码，欢迎贡献想法与代码。").font(.caption).foregroundStyle(.secondary)
                } header: { Text("关于") }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showBackup) { BackupView(store: store) }
            .confirmationDialog("清除所有高亮与待发送引用？", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("清除高亮", role: .destructive) { store.clearHighlights() }
            }
        }
    }
}

struct ModelEditor: View {
    var store: LoomStore
    @State var configuration: ModelConfiguration
    @State private var providerID: String
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var models: [AvailableModel] = []
    @State private var loading = false
    @State private var error: String?
    @State private var deleteConfirmation = false
    @State private var refreshID = 0

    init(store: LoomStore, configuration: ModelConfiguration) {
        self.store = store
        _configuration = State(initialValue: configuration)
        _providerID = State(initialValue: ProviderPreset.matching(configuration)?.id ?? "custom")
    }
    private var discoveryInput: ModelDiscoveryInput {
        ModelDiscoveryInput(endpoint: configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                            protocolKind: configuration.protocolKind.rawValue,
                            key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                            relay: nil)
    }
    var body: some View {
        Form {
            Section {
                Picker("模型厂商", selection: $providerID) {
                    ForEach(ProviderPreset.all) { Text($0.title).tag($0.id) }
                    Text("自定义 / OpenAI 兼容").tag("custom")
                }.accessibilityIdentifier("provider-picker")
                TextField("显示名称", text: $configuration.name).accessibilityIdentifier("model-name")
                SecureField("API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("api-key")
            } header: { Text("服务商") } footer: { Text("选择厂商后自动填入接口地址。输入 Key 后自动获取账号可用的模型。") }
            Section {
                if !models.isEmpty {
                    Picker("在线型号", selection: $configuration.model) {
                        if !models.contains(where: { $0.id == configuration.model }) {
                            Text(configuration.model.isEmpty ? "请选择" : configuration.model).tag(configuration.model)
                        }
                        ForEach(models) { model in Text(model.name ?? model.id).tag(model.id) }
                    }.accessibilityIdentifier("online-model-picker")
                }
                TextField("模型型号（也可手动输入）", text: $configuration.model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("model-id")
                Button { refreshID += 1 } label: {
                    HStack {
                        Text(loading ? "正在获取在线型号…" : "刷新在线型号")
                        Spacer()
                        if loading { ProgressView() }
                    }
                }.disabled(loading || !discoveryInput.valid)
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("模型") } footer: { Text("列表以账号权限为准。不支持列表接口时，可手动输入型号。") }
            Section {
                TextField("API 接入地址", text: $configuration.endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityIdentifier("model-endpoint")
                Picker("接口协议", selection: $configuration.protocolKind) {
                    ForEach(ModelConfiguration.APIProtocol.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: { Text("接口") } footer: { Text("预设地址可以修改。中国内地和国际站的 Key 及接口可能不同。") }
            if store.configurations.contains(where: { $0.id == configuration.id }), store.configurations.count > 1 {
                Section { Button("移除此模型", role: .destructive) { deleteConfirmation = true } }
            }
        }
        .navigationTitle(configuration.name.isEmpty ? "添加模型" : configuration.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    configuration.name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    configuration.endpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                    configuration.model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
                    do { try store.saveConfiguration(configuration, key: key.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.disabled(store.isWorking)
            }
        }
        .onAppear {
            key = store.key(for: configuration.id)
            if configuration.name.isEmpty, let preset = ProviderPreset.matching(configuration) { configuration.name = preset.name }
        }
        .onChange(of: providerID) { _, id in
            guard let preset = ProviderPreset.all.first(where: { $0.id == id }) else { return }
            key = ""; models = []; error = nil
            preset.apply(to: &configuration)
        }
        .task(id: DiscoveryRequest(input: discoveryInput, revision: refreshID)) { await discover() }
        .confirmationDialog("从新对话的模型列表中移除？已有对话会保留。", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                do { try store.removeConfiguration(configuration.id); dismiss() } catch { self.error = error.localizedDescription }
            }
        }
    }
    private func discover(debounce: Bool = true) async {
        let input = discoveryInput
        models = []; loading = false; error = nil
        guard input.valid else { return }
        if debounce { try? await Task.sleep(for: .milliseconds(800)) }
        guard !Task.isCancelled else { return }
        loading = true
        do {
            var snapshot = configuration
            snapshot.endpoint = input.endpoint
            let result = try await store.discoverModels(configuration: snapshot, key: input.key)
            try Task.checkCancellation()
            guard input == discoveryInput else { return }
            models = result
            if configuration.model.isEmpty, let first = result.first { configuration.model = first.id }
            if result.isEmpty { error = "服务商未返回模型，可手动输入型号。" }
        } catch {
            if !Task.isCancelled, input == discoveryInput { self.error = "未能获取在线列表：" + error.localizedDescription }
        }
        if !Task.isCancelled, input == discoveryInput { loading = false }
    }
}

private struct DiscoveryRequest: Hashable {
    let input: ModelDiscoveryInput
    let revision: Int
}
