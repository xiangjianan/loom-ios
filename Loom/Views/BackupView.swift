import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupView: View {
    var store: LoomStore
    @Environment(\.dismiss) private var dismiss
    @State private var includeKeys = false
    @State private var document = BackupDocument(data: Data())
    @State private var cloudBusy = false
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: LoomBackup?
    @State private var confirming = false
    @State private var status: String?
    @State private var showStatus = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("对话记录", value: "\(store.conversations.count) 条")
                    LabeledContent("模型配置", value: "\(store.configurations.count) 个")
                } footer: { Text("包含完整对话、高亮、引用和模型配置，以及高亮手势等偏好设置。") }
                Section { Toggle("同时备份 API Key", isOn: $includeKeys) } footer: {
                    Text("API Key 默认不包含在备份中；开启后，文件和云端备份都会包含密钥。")
                }
                Section {
                    Button("导出到文件", systemImage: "square.and.arrow.up") {
                        do { document = BackupDocument(data: try store.backup(includeKeys: includeKeys)); exporting = true }
                        catch { report(error.localizedDescription) }
                    }.accessibilityIdentifier("backup-export")
                    Button("从文件导入", systemImage: "square.and.arrow.down") { importing = true }
                        .accessibilityIdentifier("backup-import")
                } header: { Text("导出到文件") } footer: { Text("通过系统文件窗口保存或选择备份文件。导入会替换当前记录和配置，导入前会自动保留原始本地记录。") }
                Section {
                    Button("备份到 iCloud", systemImage: "icloud.and.arrow.up") { cloudOperation(restoring: false) }
                        .accessibilityIdentifier("backup-cloud-save")
                    Button("从 iCloud 恢复", systemImage: "icloud.and.arrow.down") { cloudOperation(restoring: true) }
                        .accessibilityIdentifier("backup-cloud-restore")
                    if cloudBusy { ProgressView("正在连接 iCloud…") }
                } header: { Text("iCloud 原生备份") } footer: {
                    Text(CloudBackup.isEnabled ? "直接保存到你的私有 iCloud 空间，无需选择文件；再次备份会更新云端记录。恢复需要确认后才会替换本机记录。" : "当前签名未开通 iCloud 权限，原生云备份暂不可用。文件备份可正常使用。")
                }.disabled(cloudBusy)

            }
            .navigationTitle("备份")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Loom-\(Date().formatted(.iso8601.year().month().day()))") { result in
                switch result {
                case .success: report("备份已保存。")
                case .failure(let error): report(error.localizedDescription)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 128 * 1024 * 1024 else { throw RelayClient.ClientError(message: "备份文件过大，请选择小于 128 MB 的文件。") }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                    let archive = try JSONDecoder().decode(LoomBackup.self, from: data)
                    try archive.validate()
                    pending = archive
                    confirming = true
                } catch { report(error.localizedDescription) }
            }
            .alert("导入备份？", isPresented: $confirming) {
                Button("取消", role: .cancel) { pending = nil }
                Button("导入", role: .destructive) {
                    guard let pending else { return }
                    do { try store.restore(pending); self.pending = nil; report("备份已导入。") }
                    catch { report(error.localizedDescription) }
                }
            } message: { Text("将替换为备份中的 \(pending?.state.conversations.count ?? 0) 条对话和 \(pending?.state.configurations.count ?? 0) 个模型配置。") }
            .alert("备份", isPresented: $showStatus) { Button("好", role: .cancel) {} } message: { Text(status ?? "") }
        }
    }
    private func cloudOperation(restoring: Bool) {
        cloudBusy = true
        Task {
            defer { cloudBusy = false }
            do {
                if restoring {
                    let data = try await CloudBackup.shared.load()
                    let archive = try JSONDecoder().decode(LoomBackup.self, from: data)
                    try archive.validate()
                    pending = archive
                    confirming = true
                } else {
                    let data = try store.backup(includeKeys: includeKeys)
                    _ = try await CloudBackup.shared.save(data)
                    report("已备份到 iCloud。")
                }
            } catch { report(error.localizedDescription) }
        }
    }
    private func report(_ message: String) { status = message; showStatus = true }
}
