import AppKit

extension Store {
    func configurePolling() {
        guard !sleeping else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.scheduledRefresh() }
        }
        timer?.tolerance = 5
        powerMonitor = PowerEventMonitor { [weak self] in
            Task { @MainActor in
                guard let self, !self.sleeping else { return }
                await self.refreshMac()
            }
        }
        powerTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.sleeping else { return }
                let quiet = self.reducedPolling || !NSApp.windows.contains { $0.isVisible && $0.title == "BatteryScope" }
                if !quiet || Date().timeIntervalSince(self.lastMacRead) >= 30 { await self.refreshMac() }
            }
        }
        powerTimer?.tolerance = 1
    }
    func stopBackgroundWork() {
        timer?.invalidate(); timer = nil
        powerTimer?.invalidate(); powerTimer = nil
        powerMonitor = nil
        workGeneration = UUID()
        syncGeneration = UUID(); syncWorker?.cancel(); syncRestartRequested = false
        CommandActivity.shared.cancel(sleeping: sleeping)
    }
    func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSleeping(true) }
        })
        sleepObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSleeping(false) }
        })
    }
    func setSleeping(_ value: Bool) {
        sleeping = value
        stopBackgroundWork()
        // No refresh, sync, or new timer work is executed from the wake callback.
        // Timers start a fresh interval, without catching up missed ticks.
        if !value { configurePolling() }
    }
}
