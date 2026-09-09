import Foundation

enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum Command {
    static func bundledPath(_ name: String, bundleURL: URL = Bundle.main.bundleURL) -> String? {
        guard ["idevice_id", "ideviceinfo", "idevicediagnostics"].contains(name) else { return nil }
        let file = bundleURL.appendingPathComponent("Contents/Helpers/MobileDevice").appendingPathComponent(name)
        return FileManager.default.isExecutableFile(atPath: file.path) ? file.path : nil
    }
    static func path(_ name: String) -> String? {
        if let bundled = bundledPath(name) { return bundled }
        return ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/", "/usr/sbin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    @TaskLocal static var generation: UInt64?
    static func run(_ name: String, _ args: [String], timeout: TimeInterval = 12) throws -> Data {
        guard let path = path(name) else { throw ReaderError.message("Не найдена системная утилита \(name).") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = args
        process.standardOutput = handle; process.standardError = handle
        try CommandActivity.shared.start(process, generation: generation)
        defer { CommandActivity.shared.finish(process) }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try CommandActivity.shared.check(generation)
            Thread.sleep(forTimeInterval: 0.05)
        }
        try CommandActivity.shared.check(generation)
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw ReaderError.message("\(name): устройство не ответило за \(Int(timeout)) с")
        }
        let data = try Data(contentsOf: url)
        guard process.terminationStatus == 0 else { throw ReaderError.message(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Ошибка \(name)") }
        return data
    }
    static func plist(_ name: String, _ args: [String]) throws -> Any {
        var data = try run(name, args)
        if let range = data.range(of: Data("<?xml".utf8)) { data = data.subdata(in: range.lowerBound..<data.endIndex) }
        return try PropertyListSerialization.propertyList(from: data, format: nil)
    }

}

/// Serializes process start against sleep/cancellation; never waits for exit on the UI thread.
final class CommandActivity: @unchecked Sendable {
    static let shared = CommandActivity()
    private let lock = NSLock()
    private var epoch: UInt64 = 0
    private var sleeping = false
    private var processes: [ObjectIdentifier: Process] = [:]
    var generation: UInt64 { lock.lock(); defer { lock.unlock() }; return epoch }
    func check(_ generation: UInt64?) throws {
        lock.lock(); defer { lock.unlock() }
        if sleeping || (generation != nil && generation != epoch) { throw CancellationError() }
    }
    func start(_ process: Process, generation: UInt64?) throws {
        lock.lock(); defer { lock.unlock() }
        if sleeping || (generation != nil && generation != epoch) { throw CancellationError() }
        try process.run()
        processes[ObjectIdentifier(process)] = process
    }
    func finish(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes.removeValue(forKey: ObjectIdentifier(process))
    }
    func cancel(sleeping: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.sleeping = sleeping; epoch &+= 1
        for process in processes.values where process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
