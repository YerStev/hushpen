enum ExitCode: Int32 {
    case success = 0
    case failure = 1
    case usage = 2
    case modelMissing = 3
    case modelDigestMismatch = 4
    case recordingState = 5
    case transcription = 6
    case microphone = 7
}

struct ToolError: Error {
    let code: ExitCode
    let message: String

    init(_ code: ExitCode, _ message: String) {
        self.code = code
        self.message = message
    }
}
