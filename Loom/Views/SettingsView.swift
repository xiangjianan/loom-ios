import SwiftUI

struct SettingsView: View {
    @Bindable var store: LoomStore
    @Environment(\.dismiss) private var dismiss
    @State private var relay = ""
    @State private var error: String?
    @State private var clearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.configurations) { configuration in
                        NavigationLink {
                            ModelEditor(store: store, configuration: configuration)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkle").foregroundStyle(.indigo)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(configuration.name)
                                    Text(configuration.model.isEmpty ? "尚未配置" : configuration.model)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !store.key(for: configuration.id).isEmpty { Image(systemName: "key.fill").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if store.configurations.count < 5 {
                        NavigationLink {
                            ModelEditor(store: store, configuration: ModelConfiguration(name: "", endpoint: "https://api.openai.com/v1", model: ""))
                        } label: { Label("添加模型", systemImage: "plus") }
                    }
                } header: { Text("模型 · 最多 5 个") } footer: {
                    Text("API Key 仅存放在此设备的系统钥匙串。修改已有对话使用的模型后，新配置会在新对话中生效。")
                }.disabled(store.isWorking)
                Section {
                    Toggle("使用转发服务", isOn: $store.useRelay)
                        .disabled(store.isWorking).onChange(of: store.useRelay) { _, _ in store.save() }
                    if store.useRelay {
                    TextField("HTTPS 转发服务地址", text: $relay).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("保存服务地址") {
                        do { try store.updateRelay(relay); error = nil } catch { self.error = error.localizedDescription }
                    }.disabled(store.isWorking)
                    }
                } header: { Text("连接") } footer: {
                    Text(store.useRelay ? "模型请求包含 API Key、对话上下文和引用，经转发服务发送给所选服务商。请使用可信任的转发服务。" : "默认直接连接模型服务商，不经过 Loom 后端。API Key、对话上下文和引用会发送给你配置的服务商。")
                }
                Section {
                    Button("清除当前对话的所有高亮", role: .destructive) { clearConfirmation = true }
                } header: { Text("阅读") }
                Section {
                    LabeledContent("版本", value: "1.0.0")
                    Text("Loom 让多个模型的观点交织，帮助你继续思考。对话与高亮保存在本地，暂不与网页或其他设备同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("项目源码", destination: URL(string: "https://github.com/xiangjianan/loom-ios")!)
                } header: { Text("关于") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { relay = store.relayURL }
            .confirmationDialog("清除所有高亮与待发送引用？", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("清除高亮", role: .destructive) { store.clearHighlights() }
            }
        }
    }
}

struct ModelEditor: View {
    var store: LoomStore
    @State var configuration: ModelConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var models: [AvailableModel] = []
    @State private var loading = false
    @State private var error: String?
    @State private var deleteConfirmation = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("显示名称") { TextField("例如 OpenAI、Claude、DeepSeek", text: $configuration.name) }
            Section {
                Picker("接口协议", selection: $configuration.protocolKind) {
                    ForEach(ModelConfiguration.APIProtocol.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("接入地址（以 /v1 结尾）", text: $configuration.endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("服务商") } footer: { Text("接入地址应为 API 基础地址，不包含 /chat/completions 或 /messages。") }
            Section {
                TextField("模型型号", text: $configuration.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    loadTask?.cancel()
                    loading = true; error = nil; models = []
                    let snapshot = configuration
                    let snapshotKey = key
                    loadTask = Task {
                        defer { loading = false }
                        do {
                            let result: [AvailableModel]
                            if store.useRelay { result = try await RelayClient(baseURL: store.relayURL).models(configuration: snapshot, key: snapshotKey) }
                            else { result = try await ProviderClient().models(configuration: snapshot, key: snapshotKey) }
                            try Task.checkCancellation()
                            models = result
                            if result.isEmpty { error = "服务商未返回模型，可手动输入型号。" }
                        } catch {
                            if !Task.isCancelled { self.error = error.localizedDescription }
                        }
                    }
                } label: { HStack { Text("获取在线模型列表"); Spacer(); if loading { ProgressView() } } }
                    .disabled(loading || key.isEmpty)
                if !models.isEmpty {
                    Picker("选择在线模型", selection: $configuration.model) {
                        Text("手动输入 / 当前型号").tag(configuration.model)
                        ForEach(models.filter { $0.id != configuration.model }) { model in Text(model.name ?? model.id).tag(model.id) }
                    }
                }
            } header: { Text("模型") } footer: { Text("在线列表以当前账号权限为准。不支持列表接口的服务商，可以手动输入型号。") }
            if let error { Section { Text(error).foregroundStyle(.red) } }
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
        .onAppear { key = store.key(for: configuration.id) }
        .onDisappear { loadTask?.cancel() }
        .confirmationDialog("从新对话的模型列表中移除？已有对话会保留。", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                do { try store.removeConfiguration(configuration.id); dismiss() } catch { self.error = error.localizedDescription }
            }
        }
    }
}
