import DesertAnt
import Foundation
import Voz

// Leave reporting policy, identity, payload and transport to the unmodified SDK.
enum Telemetry {
    static var statusText: String {
        usageDisabled() ? "disabled by an external SDK setting" : "enabled (SDK default)"
    }

    // The SDK keeps a weak session hook; retain the model until flushing ends.
    static func flushPendingUsage(keeping model: Voz) async {
        await TelemetryDebug.shared.flushAndWait()
        withExtendedLifetime(model) {}
    }
}
