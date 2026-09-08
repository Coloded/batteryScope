import SwiftUI

extension Store {
    func readTechnical(force: Bool = false) async {
        guard let device = current, !technicalBusy.contains(device.id) else { return }
        if !force {
            if technical[device.id] != nil { return }
            do { if let record = try database?.loadTechnical(device.id) { technical[device.id] = record; return } }
            catch { self.error = error.localizedDescription }
        }
        technicalBusy.insert(device.id)
        let record = await Task.detached(priority: .utility) { TechnicalReader.read(device) }.value
        technical[device.id] = record; technicalBusy.remove(device.id)
        do { try database?.saveTechnical(record) } catch { self.error = error.localizedDescription }
    }
    func exportTechnical() {
        guard let record = technical[selected] else { return }
        do {
            write(String(decoding: try FieldLabels.export(record), as: UTF8.self), name: "BatteryScope-specifications.json")
        } catch { self.error = error.localizedDescription }
    }
    func readStorage() async {
        guard !storageBusy else { return }; storageBusy = true
        let text = await Task.detached(priority: .utility) {
            do { return String(decoding: try Command.run("system_profiler", ["SPNVMeDataType", "SPSerialATADataType"], timeout: 30), as: UTF8.self) }
            catch { return error.localizedDescription }
        }.value
        storageDetails = text.isEmpty ? "Система не предоставила сведения о накопителе." : text; storageBusy = false
    }
}
