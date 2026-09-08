import Foundation
import CryptoKit
import IOKit

enum LocalMacIdentity {
    static let id: String = {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { if entry != 0 { IOObjectRelease(entry) } }
        if entry != 0, let uuid = IORegistryEntryCreateCFProperty(entry, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return SHA256.hash(data: Data(uuid.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: "historySyncMacID") { return stored }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: "historySyncMacID")
        return generated
    }()
    static var name: String { Host.current().localizedName ?? "Mac" }
}

struct HistoryEnvelope: Codable {
    var schemaVersion = 1
    var sample: Sample

    static func outgoing(_ sample: Sample, macID: String, macName: String) -> HistoryEnvelope {
        var copy = sample
        copy.sourceMacID = copy.sourceMacID ?? macID
        copy.sourceMacName = copy.sourceMacName ?? macName
        if copy.battery.id == "mac" {
            copy.battery.id = "mac:" + macID
            copy.battery.name = macName
        }
        // Sync measurements only, not diagnostic dumps or hardware serial-number fields.
        copy.battery.details = [:]
        copy.battery.note = ""
        return HistoryEnvelope(sample: copy)
    }
    func incoming(on macID: String) throws -> Sample {
        guard schemaVersion == 1, let source = sample.sourceMacID, !source.isEmpty,
              !sample.battery.id.isEmpty, sample.battery.id != "mac",
              sample.battery.date.timeIntervalSince1970.isFinite,
              sample.battery.date <= Date().addingTimeInterval(86400) else {
            throw ReaderError.message("Неизвестный или некорректный формат снимка истории.")
        }
        var copy = sample
        if copy.battery.id == "mac:" + macID { copy.battery.id = "mac" }
        copy.battery.details = [:]
        return copy
    }
}

struct HistorySyncResult {
    var incoming: [Sample] = []
    var written = 0
    var waiting = 0
    var issues: [String] = []
}

enum HistoryFolderSync {
    static let subdirectory = "BatteryScope-History-v1"
    static func exchange(folder: URL, samples: [Sample], macID: String, macName: String) throws -> HistorySyncResult {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue else {
            throw ReaderError.message("Папка истории недоступна. Проверьте iCloud Drive или выберите папку заново.")
        }
        let root = folder.appendingPathComponent(subdirectory, isDirectory: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        try coordinatedWrite(root, coordinator: coordinator) { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        var result = HistorySyncResult()
        for sample in samples {
            try Task.checkCancellation()
            let file = root.appendingPathComponent(sample.id.uuidString + ".json")
            // Immutable files avoid competing read/modify/write operations on different Macs.
            if FileManager.default.fileExists(atPath: file.path) { continue }
            let envelope = HistoryEnvelope.outgoing(sample, macID: macID, macName: macName)
            let data = try encoder.encode(envelope)
            try coordinatedWrite(file, coordinator: coordinator) { url in
                if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic); result.written += 1 }
            }
        }
        let known = Set(samples.map(\.id))
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey], options: [.skipsHiddenFiles])
        var seen = known
        for file in files where file.pathExtension == "json" {
            try Task.checkCancellation()
            do {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey])
                guard values.isSymbolicLink != true else { continue }
                if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                    try FileManager.default.startDownloadingUbiquitousItem(at: file)
                    result.waiting += 1; continue
                }
                guard values.isRegularFile == true, (values.fileSize ?? 0) <= 1_048_576 else {
                    result.issues.append("Пропущен слишком большой или неподдерживаемый файл: " + file.lastPathComponent); continue
                }
                // UUID filenames already in SQLite need no repeated decoding.
                if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), known.contains(id) { continue }
                var readError: Error?
                var coordinationError: NSError?
                var incoming: Sample?
                coordinator.coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
                    do { incoming = try decoder.decode(HistoryEnvelope.self, from: Data(contentsOf: url)).incoming(on: macID) }
                    catch { readError = error }
                }
                if let coordinationError { throw coordinationError }
                if let readError { throw readError }
                if let incoming, seen.insert(incoming.id).inserted { result.incoming.append(incoming) }
            } catch { result.issues.append("\(file.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }
    private static func coordinatedWrite(_ url: URL, coordinator: NSFileCoordinator, action: (URL) throws -> Void) throws {
        var operationError: Error?
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinated in
            do { try action(coordinated) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }
}
