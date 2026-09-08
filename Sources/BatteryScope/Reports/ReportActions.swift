import AppKit

extension Store {
    func exportCSV(all: Bool = false) { write(Export.csv(all ? history : samples), name: "BatteryScope-history.csv") }
    func exportReport() { if let b = current { write(Export.report(b, template: reportTemplate), name: "BatteryScope-report.html") } }
    func write(_ text: String, name: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url { do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription } }
    }
    func printReport() {
        guard let b = current else { return }
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        let html = Export.report(b, template: reportTemplate)
        if let attributed = try? NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) { view.textStorage?.setAttributedString(attributed) }
        else { view.string = b.name + "\n" + b.metrics.map { $0.0 + ": " + $0.1 }.joined(separator: "\n") }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo; info.isHorizontallyCentered = true; info.horizontalPagination = .fit
        NSPrintOperation(view: view, printInfo: info).run()
    }
}
