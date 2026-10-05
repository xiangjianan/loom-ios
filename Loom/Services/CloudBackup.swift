import Foundation
#if LOOM_ICLOUD
import CloudKit
#endif

/// One replaceable archive in the user's private CloudKit database.
/// The entitlement and compilation flag must be enabled together for a provisioned team.
actor CloudBackup {
    static let shared = CloudBackup()
    static var isEnabled: Bool {
        #if LOOM_ICLOUD
        true
        #else
        false
        #endif
    }

    func save(_ data: Data) async throws -> Date {
        #if LOOM_ICLOUD
        let container = CKContainer(identifier: "iCloud.online.minidesk.loom")
        guard try await container.accountStatus() == .available else {
            throw RelayClient.ClientError(message: "请先在系统设置中登录 iCloud，并允许 Loom 使用 iCloud。")
        }
        let database = container.privateCloudDatabase
        let id = CKRecord.ID(recordName: "latest-backup")
        let record: CKRecord
        do { record = try await database.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "LoomBackup", recordID: id) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try data.write(to: temporary, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: temporary) }
        record["archive"] = CKAsset(fileURL: temporary)
        let date = Date()
        record["createdAt"] = date as NSDate
        _ = try await database.save(record)
        return date
        #else
        throw Self.unavailable
        #endif
    }

    func load() async throws -> Data {
        #if LOOM_ICLOUD
        let container = CKContainer(identifier: "iCloud.online.minidesk.loom")
        guard try await container.accountStatus() == .available else {
            throw RelayClient.ClientError(message: "请先在系统设置中登录 iCloud，并允许 Loom 使用 iCloud。")
        }
        let record: CKRecord
        do { record = try await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: "latest-backup")) }
        catch let error as CKError where error.code == .unknownItem {
            throw RelayClient.ClientError(message: "这个 iCloud 账户还没有 Loom 备份。")
        }
        guard let asset = record["archive"] as? CKAsset, let url = asset.fileURL else { throw CocoaError(.fileReadCorruptFile) }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: url)
        guard data.count <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return data
        #else
        throw Self.unavailable
        #endif
    }

    private static var unavailable: RelayClient.ClientError {
        .init(message: "当前安装版本尚未获得 Apple 的 iCloud 权限。启用原生云备份需要支持 iCloud 的开发者签名；你仍可使用文件导入导出。")
    }
}
