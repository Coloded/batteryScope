import Foundation

/// A predictable personal iCloud folder, never a same-named local Documents folder.
enum CloudFolder {
    static var drive: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    static func prepare() throws -> URL {
        guard (try? drive.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true else {
            throw ReaderError.message("iCloud Drive недоступен. Включите его в настройках Apple Account или выберите общую папку вручную.")
        }
        let folder = drive.appendingPathComponent("BatteryScope", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

struct SyncPeer: Codable, Identifiable {
    var id: String
    var name: String
    var lastExchange: Date
    var receivedBySource: [String: Int]
}

extension HistoryFolderSync {
    static func logicalURL(_ entry: URL) -> URL? {
        if entry.pathExtension == "json", !entry.lastPathComponent.hasPrefix(".") { return entry }
        let name = entry.lastPathComponent
        // Older iCloud Drive versions may enumerate evicted documents as placeholders.
        if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
            let logical = String(name.dropFirst().dropLast(".icloud".count))
            if UUID(uuidString: String(logical.dropLast(".json".count))) != nil {
                return entry.deletingLastPathComponent().appendingPathComponent(logical)
            }
        }
        return nil
    }
    static func exchangePeers(root: URL, macID: String, macName: String, samples: [Sample]) throws -> [SyncPeer] {
        let folder = root.appendingPathComponent("Peers", isDirectory: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        try coordinatedWrite(folder, coordinator: coordinator) { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        var counts: [String: Int] = [:]
        for sample in samples { counts[sample.sourceMacID ?? macID, default: 0] += 1 }
        let peer = SyncPeer(id: macID, name: macName, lastExchange: Date(), receivedBySource: counts)
        guard !macID.isEmpty, macID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { throw ReaderError.message("Некорректный идентификатор Mac.") }
        let data = try JSONEncoder().encode(peer)
        try coordinatedWrite(folder.appendingPathComponent(macID + ".json"), coordinator: coordinator) { try data.write(to: $0, options: .atomic) }
        var peers: [SyncPeer] = []
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey], options: [.skipsHiddenFiles]) where file.pathExtension == "json" {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus == .notDownloaded { try? FileManager.default.startDownloadingUbiquitousItem(at: file); continue }
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) < 1_048_576 else { continue }
            var coordinationError: NSError?
            coordinator.coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
                if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(SyncPeer.self, from: data), value.id != macID, value.lastExchange <= Date().addingTimeInterval(86400) { peers.append(value) }
            }
        }
        return peers.sorted { $0.lastExchange > $1.lastExchange }
    }
}
