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
                Section {
                    Toggle("同时备份 API Key", isOn: $includeKeys)
                    Button("导出到本地或 iCloud", systemImage: "square.and.arrow.up") {
                        do { document = BackupDocument(data: try store.backup(includeKeys: includeKeys)); exporting = true }
                        catch { report(error.localizedDescription) }
                    }.accessibilityIdentifier("backup-export")
                } footer: {
                    Text(includeKeys ? "包含 API Key 的备份请存放在你信任的位置。保存时可选择本机或 iCloud 云盘。" : "通过系统文件窗口，选择“我的 iPhone / iPad”或“iCloud 云盘”。API Key 默认不导出。")
                }
                Section {
                    Button("从本地或 iCloud 导入", systemImage: "square.and.arrow.down") { importing = true }
                        .accessibilityIdentifier("backup-import")
                } footer: { Text("导入会替换当前记录和配置；导入前会自动保留一份原始本地记录。不含 API Key 的备份需要在新设备上重新填写密钥。") }
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
    private func report(_ message: String) { status = message; showStatus = true }
}
