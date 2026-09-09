import SwiftUI

extension Store {
    func readTechnical(force: Bool = false) async {
        guard !sleeping, var device = current, !technicalBusy.contains(device.id) else { return }
        if device.id.hasPrefix("bt:") {
            let id = device.id
            if force {
                await refresh()
                guard !sleeping, let fresh = devices.first(where: { $0.id == id }) else { return }
                device = fresh
            }
            // Current macOS data wins over the separate persisted technical snapshot.
            if devices.contains(where: { $0.id == device.id }) {
                storeAccessoryTechnical(device)
                return
            }
        }
        if !device.isLive && !device.isAccessory {
            technical[device.id] = TechnicalReader.read(device)
            return
        }
        if !force {
            if technical[device.id] != nil { return }
            do { if let record = try database?.loadTechnical(device.id) { technical[device.id] = record; return } }
            catch { self.error = error.localizedDescription }
        }
        technicalBusy.insert(device.id)
        defer { technicalBusy.remove(device.id) }
        let generation = CommandActivity.shared.generation
        let record = await Task.detached(priority: .utility) {
            Command.$generation.withValue(generation) { TechnicalReader.read(device) }
        }.value
        guard !sleeping, generation == CommandActivity.shared.generation else { return }
        technical[device.id] = record
        do { try database?.saveTechnical(record) } catch { self.error = error.localizedDescription }
    }
    func storeAccessoryTechnical(_ device: Battery) {
        let record = TechnicalReader.read(device)
        let previous = technical[device.id]
        technical[device.id] = record
        // Avoid a SQLite write every poll when only the read time has changed.
        if previous?.sections != record.sections || previous?.notes != record.notes {
            do { try database?.saveTechnical(record) } catch { self.error = error.localizedDescription }
        }
    }
    func updateAccessoryTechnicalRecords() {
        for device in devices where device.id.hasPrefix("bt:") { storeAccessoryTechnical(device) }
    }
    func exportTechnical() {
        guard let record = technical[selected] else { return }
        do {
            write(String(decoding: try FieldLabels.export(record), as: UTF8.self), name: "BatteryScope-specifications.json")
        } catch { self.error = error.localizedDescription }
    }
    func readStorage() async {
        guard !sleeping, !storageBusy else { return }; storageBusy = true
        defer { storageBusy = false }
        let generation = CommandActivity.shared.generation
        let text = await Task.detached(priority: .utility) {
            do { return try Command.$generation.withValue(generation) { String(decoding: try Command.run("system_profiler", ["SPNVMeDataType", "SPSerialATADataType"], timeout: 30), as: UTF8.self) } }
            catch { return error.localizedDescription }
        }.value
        guard !sleeping, generation == CommandActivity.shared.generation else { return }
        storageDetails = text.isEmpty ? "Система не предоставила сведения о накопителе." : text; storageBusy = false
    }
}
