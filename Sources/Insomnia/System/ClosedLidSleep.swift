import Foundation
import IOKit
import IOKit.pwr_mgt

/// Puts a closed Mac to sleep after a timer or floor-rule end (spec section 6).
protocol ClosedLidSleeping: Sendable {
    /// False with an external display in clamshell mode, nil when it
    /// cannot be read.
    func lidCloseCausesSleep() -> Bool?
    /// `IOPMSleepSystem`. No root needed. macOS refuses it while sleep is
    /// disabled.
    func requestSleep() throws
}

struct ClosedLidSleepError: Error, LocalizedError {
    let call: String
    let code: IOReturn

    var errorDescription: String? {
        "\(call) returned \(String(format: "0x%08x", UInt32(bitPattern: code)))"
    }
}

struct IOKitClosedLidSleep: ClosedLidSleeping {
    // The display list, not `AppleClamshellCausesSleep`: that key
    // read No on a lid-open Mac with no external display, so its meaning
    // here is unverified.
    func lidCloseCausesSleep() -> Bool? {
        !LidObserver.hasActiveExternalDisplay()
    }

    func requestSleep() throws {
        let connect = IOPMFindPowerManagement(kIOMainPortDefault)
        guard connect != 0 else {
            throw ClosedLidSleepError(call: "IOPMFindPowerManagement", code: kIOReturnNotFound)
        }
        defer { IOServiceClose(connect) }
        let result = IOPMSleepSystem(connect)
        guard result == kIOReturnSuccess else {
            throw ClosedLidSleepError(call: "IOPMSleepSystem", code: result)
        }
    }
}

struct NoopClosedLidSleep: ClosedLidSleeping {
    func lidCloseCausesSleep() -> Bool? { nil }
    func requestSleep() throws {}
}
