import DesertAnt
import Foundation
import Voz

// Leave license identity, payload, retries and transport to the unmodified SDK.
enum Telemetry {
    static var statusText: String { "enabled (SDK default)" }

    // The SDK queues license work at model load. Await in-flight requests on exit.
    static func flushPendingLicense(keeping model: Voz) async {
        await TelemetryDebug.shared.flushAndWait()
        withExtendedLifetime(model) {}
    }
}
