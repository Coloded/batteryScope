import AppKit
import Combine
import Sparkle

@MainActor final class UpdateController: ObservableObject {
    static let shared = UpdateController()
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    @Published var automaticChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticChecks }
    }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
    }
    func check() { controller.checkForUpdates(nil) }
}
