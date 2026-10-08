import Foundation

enum Attribution {
    static let toolVersion = "0.3.0"
    static let sdkVersion = "desert-ant-core 3.5.0"
    static let modelRevision = "Voz v0.1.0"

    static var versionText: String {
        """
        hushpen \(toolVersion)
        Speech recognition: \(modelRevision) through \(sdkVersion)

        Powered by Desert Ant Labs — https://desertant.com
        The Voz model and its SDK use the Desert Ant Labs
        Source-Available License 1.0 (source-available, not open source):
        https://license.desertant.com/1.0
        """
    }
}
