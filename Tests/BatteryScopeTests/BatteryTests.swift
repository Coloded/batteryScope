import Foundation

@main struct BatteryTests {
    static func main() throws {
        let suite = BatteryTests()
        try suite.testSleepCancelsCommandsAndRejectsStaleWork()
        suite.testModernMacDoesNotTreatPercentAsMilliampHours()
        suite.testLegacyMacCapacity()
        suite.testMissingAndZeroCapacityDoNotInventHealth()
        suite.testUnsignedNegativeCurrent()
        suite.testRawPercentAndNestedCapacity()
        suite.testUnknownTimeAndTemperature()
        suite.testCSVQuotesAndMissingValues()
        suite.testReportEscapesDeviceNames()
        try suite.testHistoryRoundTrip()
        suite.testLiveMacReadIsSafeWithoutBattery()
        suite.testMobileBasicSurvivesMissingDiagnostics()
        suite.testMobileRealisticDiagnostics()
        suite.testCachedAirPodsAreNotLive()
        suite.testHIDAddressMatching()
        suite.testComponentReport()
        try suite.testOldHistoryCompatibility()
        try suite.testSQLiteMigrationAndReopen()
        try suite.testSQLiteBadLegacyPreserved()
        try suite.testSQLiteTechnicalCache()
        suite.testTechnicalFieldsExcludeSubscriberData()
        suite.testRussianFieldLabelsAndSearch()
        suite.testLocalizedValuesPreserveAmbiguousUnits()
        suite.testUnknownFieldsAreNotGuessed()
        try suite.testTranslatedExportKeepsRawFields()
        try suite.testCloudHistorySeparatesMacsAndKeepsOrigin()
        try suite.testCloudHistoryRejectsFutureSchema()
        try suite.testCloudHistoryExchangeIsIdempotent()
        try suite.testBundledMobileHelpersAreDiscovered()
        suite.testChargingPowerDoesNotMixDifferentSources()
        suite.testPowerPreservesZeroAndRejectsBadCurrent()
        try suite.testPowerHistoryAndPeerReceipts()
        suite.testCloudPlaceholderResolution()
        print("PASS: 33 tests (battery, SQLite, technical data, Russian labels, units, exports)")
        if CommandLine.arguments.contains("--live-devices") {
            let phones = DeviceReader.mobile(network: true)
            XCTAssertTrue(phones.messages.isEmpty)
            XCTAssertTrue(phones.devices.contains { $0.model.hasPrefix("iPhone") && $0.percent != nil && $0.health != nil })
            XCTAssertEqual(Set(phones.devices.map(\.id)).count, phones.devices.count)
            for b in phones.devices { print("LIVE: \(b.model) \(b.connection), charge \(b.value(b.percent)), cycles \(b.value(b.cycles)), health \(b.value(b.health, digits: 1))") }
            if let phone = phones.devices.first(where: { $0.model.hasPrefix("iPhone") }) {
                let specs = TechnicalReader.read(phone)
                XCTAssertTrue(specs.sections["Аппаратная платформа, ОС и прошивки"]?.isEmpty == false)
                print("TECHNICAL: \(specs.sections.count) sections, \(specs.sections.values.reduce(0) { $0 + $1.count }) fields")
            }
            let peripherals = DeviceReader.accessories()
            XCTAssertTrue(peripherals.messages.isEmpty)
            for b in peripherals.devices { print("ACCESSORY: \(b.model), live \(b.isLive), charge \(b.value(b.percent))") }
        }
    }
    func testCloudHistorySeparatesMacsAndKeepsOrigin() throws {
        var battery = parse(["CurrentCapacity": 40, "MaxCapacity": 100])
        battery.details = ["SerialNumber": "private"]
        let sample = Sample(battery: battery)
        let envelope = HistoryEnvelope.outgoing(sample, macID: "mac-a", macName: "Mac A")
        let remote = try envelope.incoming(on: "mac-b")
        XCTAssertEqual(remote.battery.id, "mac:mac-a")
        XCTAssertEqual(remote.id, sample.id)
        XCTAssertTrue(remote.battery.details.isEmpty)
        XCTAssertEqual(remote.sourceMacName, "Mac A")
        let forwarded = HistoryEnvelope.outgoing(remote, macID: "mac-b", macName: "Mac B")
        XCTAssertEqual(forwarded.sample.sourceMacID, "mac-a")
        XCTAssertEqual(try forwarded.incoming(on: "mac-a").battery.id, "mac")
        var phone = battery; phone.id = "phone-udid"
        XCTAssertEqual(try HistoryEnvelope.outgoing(Sample(battery: phone), macID: "mac-a", macName: "Mac A").incoming(on: "mac-b").battery.id, "phone-udid")
    }
    func testCloudHistoryRejectsFutureSchema() throws {
        var envelope = HistoryEnvelope.outgoing(Sample(battery: parse([:])), macID: "mac-a", macName: "Mac A")
        envelope.schemaVersion = 999
        var rejected = false
        do { _ = try envelope.incoming(on: "mac-b") } catch { rejected = true }
        XCTAssertTrue(rejected)
    }
    func testCloudHistoryExchangeIsIdempotent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try HistoryDatabase(url: folder.appendingPathComponent("a.sqlite"))
        let b = try HistoryDatabase(url: folder.appendingPathComponent("b.sqlite"))
        let localA = Sample(battery: parse(["CurrentCapacity": 50, "MaxCapacity": 100]))
        let localB = Sample(battery: parse(["CurrentCapacity": 80, "MaxCapacity": 100]))
        try a.append(localA); try b.append(localB)
        _ = try HistoryFolderSync.exchange(folder: folder, samples: a.load(), macID: "a", macName: "Mac A")
        let received = try HistoryFolderSync.exchange(folder: folder, samples: b.load(), macID: "b", macName: "Mac B")
        try b.merge(received.incoming); try b.merge(received.incoming)
        XCTAssertEqual(try b.load().count, 2)
        XCTAssertEqual(Set(try b.load().map { $0.battery.id }), Set(["mac", "mac:a"]))
        let back = try HistoryFolderSync.exchange(folder: folder, samples: a.load(), macID: "a", macName: "Mac A")
        try a.merge(back.incoming)
        XCTAssertEqual(try a.load().count, 2)
        let again = try HistoryFolderSync.exchange(folder: folder, samples: b.load(), macID: "b", macName: "Mac B")
        XCTAssertEqual(again.written, 0); XCTAssertTrue(again.incoming.isEmpty)
        try Data("invalid JSON".utf8).write(to: folder.appendingPathComponent(HistoryFolderSync.subdirectory).appendingPathComponent("broken.json"))
        let damaged = try HistoryFolderSync.exchange(folder: folder, samples: b.load(), macID: "b", macName: "Mac B")
        XCTAssertEqual(damaged.issues.count, 1); XCTAssertEqual(try b.load().count, 2)
    }
    func testBundledMobileHelpersAreDiscovered() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        let helpers = bundle.appendingPathComponent("Contents/Helpers/MobileDevice")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let utility = helpers.appendingPathComponent("ideviceinfo")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: utility)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: utility.path)
        XCTAssertEqual(Command.bundledPath("ideviceinfo", bundleURL: bundle), utility.path)
        XCTAssertNil(Command.bundledPath("idevice_id", bundleURL: bundle))
        XCTAssertNil(Command.bundledPath("../../ideviceinfo", bundleURL: bundle))
    }
    func testChargingPowerDoesNotMixDifferentSources() {
        let b = parse(["Voltage": 12000, "Amperage": 1000, "InstantAmperage": 2000, "ExternalConnected": true,
                       "AdapterDetails": ["Watts": 96], "Other": ["Watts": 240],
                       "PowerTelemetryData": ["SystemPowerIn": 40000, "SystemLoad": 16000, "BatteryPower": 24000, "WallEnergyEstimate": 999999]])
        XCTAssertEqual(b.watts, 24)
        XCTAssertEqual(b.power?.inputWatts, 40)
        XCTAssertEqual(b.power?.systemWatts, 16)
        XCTAssertEqual(b.power?.adapterRatingWatts, 96)
        XCTAssertEqual(b.currentSource, "InstantAmperage")
        let disconnected = parse(["ExternalConnected": false, "PowerTelemetryData": ["SystemPowerIn": 40000]])
        XCTAssertNil(disconnected.power?.inputWatts)
    }
    func testPowerPreservesZeroAndRejectsBadCurrent() {
        let zero = parse(["Voltage": 12000, "InstantAmperage": 0, "Amperage": 500, "ExternalConnected": true, "PowerTelemetryData": ["SystemPowerIn": 0]])
        XCTAssertEqual(zero.watts, 0); XCTAssertEqual(zero.power?.inputWatts, 0)
        XCTAssertNil(parse([:]).power?.inputWatts)
        XCTAssertNil(parse(["Voltage": 12000, "Amperage": 999999]).watts)
        let fallback = parse(["Voltage": 12000, "InstantAmperage": 999999, "Amperage": -1000])
        XCTAssertEqual(fallback.watts, -12)
        let signed = parse(["PowerTelemetryData": ["BatteryPower": NSNumber(value: UInt64.max - 999)]])
        XCTAssertEqual(signed.power?.reportedBatteryWatts, -1)
    }
    func testCloudPlaceholderResolution() {
        let id = UUID().uuidString
        let parent = URL(fileURLWithPath: "/tmp")
        XCTAssertEqual(HistoryFolderSync.logicalURL(parent.appendingPathComponent("." + id + ".json.icloud"))?.lastPathComponent, id + ".json")
        XCTAssertNil(HistoryFolderSync.logicalURL(parent.appendingPathComponent(".unrelated.icloud")))
    }
    func testPowerHistoryAndPeerReceipts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var battery = parse(["Voltage": 12000, "Amperage": -1000, "ExternalConnected": true, "PowerTelemetryData": ["SystemPowerIn": 5000]])
        let db = try HistoryDatabase(url: root.appendingPathComponent("history.sqlite"))
        let sample = Sample(battery: battery, sourceMacID: "a", sourceMacName: "Synthetic A")
        try db.append(sample)
        XCTAssertEqual(try db.load().first?.battery.power?.inputWatts, 5)
        let imported = try HistoryEnvelope.outgoing(sample, macID: "a", macName: "Synthetic A").incoming(on: "b")
        _ = try HistoryFolderSync.exchangePeers(root: root, macID: "b", macName: "Synthetic B", samples: [imported])
        let peers = try HistoryFolderSync.exchangePeers(root: root, macID: "a", macName: "Synthetic A", samples: [sample])
        XCTAssertEqual(peers.first?.receivedBySource["a"], 1)
        battery.power = nil
        let data = try JSONEncoder().encode(Sample(battery: battery))
        let old = try JSONDecoder().decode(Sample.self, from: data)
        XCTAssertNil(old.battery.power)
    }
    func parse(_ values: [String: Any]) -> Battery { BatteryParser.parse(values, id: "mac", name: "Test", model: "MacBook", connection: "Этот Mac") }
    func testSleepCancelsCommandsAndRejectsStaleWork() throws {
        let gate = CommandActivity.shared
        let old = gate.generation
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["30"]
        try gate.start(process, generation: old)
        defer { gate.finish(process); gate.cancel(sleeping: false) }
        gate.cancel(sleeping: true)
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
        do { try gate.check(nil); preconditionFailure("Sleeping must reject new commands") } catch is CancellationError {}
        gate.cancel(sleeping: false)
        do { try gate.check(old); preconditionFailure("Wake must not revive cancelled work") } catch is CancellationError {}
        try gate.check(gate.generation)
        let data = try Command.$generation.withValue(gate.generation) { try Command.run("true", []) }
        XCTAssertTrue(data.isEmpty)
    }
    func testModernMacDoesNotTreatPercentAsMilliampHours() {
        let b = parse(["CurrentCapacity": 80, "MaxCapacity": 100, "AppleRawMaxCapacity": 4500, "DesignCapacity": 5000, "Temperature": 3012, "Voltage": 12000])
        XCTAssertEqual(b.percent, 80); XCTAssertEqual(b.health, 90); XCTAssertEqual(b.temperature, 30.12); XCTAssertEqual(b.voltage, 12)
    }
    func testLegacyMacCapacity() {
        let b = parse(["CurrentCapacity": 2000, "MaxCapacity": 4000, "DesignCapacity": 5000])
        XCTAssertEqual(b.percent, 50); XCTAssertEqual(b.full, 4000); XCTAssertEqual(b.health, 80)
    }
    func testMissingAndZeroCapacityDoNotInventHealth() {
        XCTAssertNil(parse([:]).health)
        XCTAssertNil(parse(["MaxCapacity": 100, "DesignCapacity": 5000]).health)
        let b = parse(["CurrentCapacity": 0, "MaxCapacity": 0, "DesignCapacity": 0])
        XCTAssertNil(b.percent); XCTAssertNil(b.health)
    }
    func testUnsignedNegativeCurrent() {
        XCTAssertEqual(BatteryParser.signedCurrent(NSNumber(value: UInt64.max - 499)), -500)
        let b = parse(["Amperage": NSNumber(value: UInt64.max - 499), "Voltage": 12000])
        XCTAssertEqual(b.watts, -6)
    }
    func testRawPercentAndNestedCapacity() {
        let b = parse(["AppleRawCurrentCapacity": 2000, "BatteryData": ["NominalChargeCapacity": 4000, "DesignCapacity": 5000, "CycleCount": 100]])
        XCTAssertEqual(b.percent, 50); XCTAssertEqual(b.health, 80); XCTAssertEqual(b.cycles, 100)
    }
    func testUnknownTimeAndTemperature() {
        let b = parse(["TimeRemaining": 65535, "Temperature": 0])
        XCTAssertNil(b.minutes); XCTAssertNil(b.temperature)
    }
    func testCSVQuotesAndMissingValues() {
        var b = parse([:]); b.name = "Mac, \"Work\"\nDesk"
        let csv = Export.csv([Sample(battery: b)])
        XCTAssertTrue(csv.contains("\"Mac, \"\"Work\"\"\nDesk\""))
        XCTAssertFalse(csv.contains("nan")); XCTAssertFalse(csv.contains("Optional"))
    }
    func testReportEscapesDeviceNames() {
        var b = parse([:]); b.name = "<script>alert(1)</script>"
        let report = Export.report(b, template: Export.template)
        XCTAssertTrue(report.contains("&lt;script&gt;")); XCTAssertFalse(report.contains("<script>")); XCTAssertFalse(report.contains("{{rows}}"))
    }
    func testHistoryRoundTrip() throws {
        let sample = Sample(battery: parse(["CycleCount": 99]))
        let decoded = try JSONDecoder().decode([Sample].self, from: JSONEncoder().encode([sample]))
        XCTAssertEqual(decoded.first?.battery.cycles, 99); XCTAssertEqual(decoded.first?.id, sample.id)
    }
    func testLiveMacReadIsSafeWithoutBattery() {
        let b = BatteryReader.mac()
        XCTAssertFalse(b.model.isEmpty)
        if b.full == nil || b.full == 0 { XCTAssertNil(b.percent); XCTAssertFalse(b.note.isEmpty) }
    }
    func testMobileBasicSurvivesMissingDiagnostics() {
        let b = DeviceParser.mobile(id: "test", info: ["ProductType": "iPad13,1"], basic: ["BatteryCurrentCapacity": 44, "BatteryIsCharging": true], diagnostics: [:], network: true)
        XCTAssertEqual(b.percent, 44); XCTAssertNil(b.health); XCTAssertTrue(b.charging == true); XCTAssertEqual(b.connection, "Wi-Fi")
    }
    func testMobileRealisticDiagnostics() {
        // Synthetic protocol fixture; no measurements or identifiers from a real device.
        let raw: [String: Any] = ["IORegistry": ["AppleRawMaxCapacity": 4200, "DesignCapacity": 5000, "CurrentCapacity": 60, "MaxCapacity": 100, "CycleCount": 100, "Temperature": 3000]]
        let b = DeviceParser.mobile(id: "test", info: ["ProductType": "iPhone99,1"], basic: ["BatteryCurrentCapacity": 60], diagnostics: raw, network: false)
        XCTAssertEqual(b.percent, 60); XCTAssertEqual(b.cycles, 100); XCTAssertEqual(b.full, 4200); XCTAssertEqual(b.temperature, 30)
    }
    func bluetoothFixture(live: Bool, name: String, type: String, fields: [String: Any] = [:]) -> [String: Any] {
        var d: [String: Any] = ["device_address": "AA:BB:CC:DD:EE:FF", "device_vendorID": "0x004C", "device_minorType": type]
        d.merge(fields, uniquingKeysWith: { _, new in new })
        return ["SPBluetoothDataType": [[live ? "device_connected" : "device_not_connected": [[name: d]]]]]
    }
    func testCachedAirPodsAreNotLive() {
        let json = bluetoothFixture(live: false, name: "AirPods", type: "Headphones", fields: ["device_batteryLevelCase": "18 %", "device_batteryLevelLeft": "100 %"])
        let b = DeviceParser.bluetooth(json, hid: []).first!
        XCTAssertFalse(b.isLive); XCTAssertNil(b.percent); XCTAssertEqual(b.components?["Футляр"], 18); XCTAssertEqual(b.state, "Нет свежих данных")
    }
    func testHIDAddressMatching() {
        let json = bluetoothFixture(live: true, name: "Magic Keyboard", type: "Keyboard")
        let b = DeviceParser.bluetooth(json, hid: [["DeviceAddress": "aa-bb-cc-dd-ee-ff", "BatteryPercent": 61]]).first!
        XCTAssertEqual(b.percent, 61); XCTAssertTrue(b.isLive); XCTAssertNil(b.health)
    }
    func testComponentReport() {
        var b = parse([:]); b.components = ["Футляр": 18]
        XCTAssertTrue(Export.report(b, template: Export.template).contains("Футляр"))
        XCTAssertTrue(Export.csv([Sample(battery: b)]).contains("18.0"))
    }
    func testOldHistoryCompatibility() throws {
        let original = Sample(battery: parse(["CycleCount": 3]))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        var battery = json["battery"] as! [String: Any]; battery.removeValue(forKey: "available"); battery.removeValue(forKey: "components"); json["battery"] = battery
        let restored = try JSONDecoder().decode(Sample.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(restored.battery.isLive); XCTAssertEqual(restored.battery.cycles, 3)
    }
    func testSQLiteMigrationAndReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent("history.json"), path = dir.appendingPathComponent("test.sqlite")
        let first = Sample(battery: parse(["CycleCount": 10])), next = Sample(battery: parse(["CycleCount": 11]))
        let original = try JSONEncoder().encode([first]); try original.write(to: legacy)
        do {
            let db = try HistoryDatabase(url: path, legacyURL: legacy)
            XCTAssertEqual(try db.load().count, 1)
            try db.append(next); try db.append(next)
            XCTAssertEqual(try db.load().count, 2)
        }
        let reopened = try HistoryDatabase(url: path, legacyURL: legacy)
        XCTAssertEqual(try reopened.load().count, 2)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        XCTAssertEqual(Set(try reopened.load().map(\.id)), Set([first.id, next.id]))
    }
    func testSQLiteBadLegacyPreserved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent("history.json")
        let invalid = Data("{broken".utf8); try invalid.write(to: legacy)
        var failed = false
        do { _ = try HistoryDatabase(url: dir.appendingPathComponent("test.sqlite"), legacyURL: legacy) } catch { failed = true }
        XCTAssertTrue(failed); XCTAssertEqual(try Data(contentsOf: legacy), invalid)
    }
    func testSQLiteTechnicalCache() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try HistoryDatabase(url: dir.appendingPathComponent("test.sqlite"))
        var record = TechnicalRecord(deviceID: "phone", sections: ["Hardware": ["CPU": "arm64"]])
        try db.saveTechnical(record)
        record.sections["Hardware"]?["CPU"] = "arm64e"; try db.saveTechnical(record)
        XCTAssertEqual(try db.loadTechnical("phone")?.sections["Hardware"]?["CPU"], "arm64e")
        XCTAssertNil(try db.loadTechnical("other"))
    }
    func testTechnicalFieldsExcludeSubscriberData() {
        let fields = TechnicalReader.hardwareFields(["CPUArchitecture": "arm64", "PhoneNumber": "private", "InternationalMobileSubscriberIdentity": "private", "BasebandMasterKeyHash": "private", "SerialNumber": "hardware-id"])
        XCTAssertEqual(fields["CPUArchitecture"], "arm64"); XCTAssertEqual(fields["SerialNumber"], "hardware-id")
        XCTAssertNil(fields["PhoneNumber"]); XCTAssertNil(fields["InternationalMobileSubscriberIdentity"]); XCTAssertNil(fields["BasebandMasterKeyHash"])
    }
    func testRussianFieldLabelsAndSearch() {
        XCTAssertEqual(FieldLabels.label("ProductType").title, "Идентификатор модели")
        let nested = FieldLabels.label("BatteryData.LifetimeData.CycleCount")
        XCTAssertTrue(nested.title.contains("Число циклов зарядки"))
        XCTAssertTrue(FieldLabels.matches("циклов", key: "CycleCount", raw: "100"))
        XCTAssertTrue(FieldLabels.matches("ProductType", key: "ProductType", raw: "iPhone99,1"))
        XCTAssertTrue(FieldLabels.label("IOReportLegend[0].IOReportChannels[12][2]").title.contains("[12][2]"))
    }
    func testLocalizedValuesPreserveAmbiguousUnits() {
        XCTAssertEqual(FieldLabels.value("true", for: "IsCharging"), "Да")
        XCTAssertEqual(FieldLabels.value("1", for: "ChipID"), "1")
        XCTAssertEqual(FieldLabels.value("256000000000", for: "TotalDiskCapacity"), "256,00 ГБ")
        XCTAssertEqual(FieldLabels.value("3909", for: "Temperature"), "39,09 °C")
        XCTAssertEqual(FieldLabels.value("3909", for: "BatteryData.LifetimeData.MaximumTemperature"), "3909")
        XCTAssertEqual(FieldLabels.value("100", for: "MaxCapacity"), "100")
        XCTAssertEqual(FieldLabels.value("12345", for: "BatteryData.ManufactureDate"), "12345")
    }
    func testUnknownFieldsAreNotGuessed() {
        let label = FieldLabels.label("BatteryData.UndocumentedNewFlag")
        XCTAssertFalse(label.known)
        XCTAssertTrue(label.explanation.contains("не подтверждены"))
        XCTAssertEqual(FieldLabels.value("128", for: "BatteryData.UndocumentedNewFlag"), "128")
    }
    func testTranslatedExportKeepsRawFields() throws {
        let record = TechnicalRecord(deviceID: "test", sections: ["ОС": ["ProductVersion": "26.6.1"]])
        let object = try JSONSerialization.jsonObject(with: FieldLabels.export(record)) as! [String: Any]
        let sections = object["sections"] as! [String: [String: String]]
        let labels = object["translations"] as! [String: [String: [String: String]]]
        XCTAssertEqual(sections["ОС"]?["ProductVersion"], "26.6.1")
        XCTAssertEqual(labels["ОС"]?["ProductVersion"]?["name_ru"], "Версия операционной системы")
    }
}

func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) { precondition(lhs == rhs, "Expected \(rhs), got \(lhs)", file: file, line: line) }
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, "Expected false", file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
