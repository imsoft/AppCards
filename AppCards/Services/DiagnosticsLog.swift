import Foundation
import os

/// Registro de eventos para diagnosticar en un iPhone real.
/// Se guarda en Documents/diagnostics.log (se puede bajar con `devicectl device copy from`).
enum DiagnosticsLog {
    private static let logger = Logger(subsystem: "com.imsoft.appcards", category: "diagnostics")
    private static let queue = DispatchQueue(label: "com.imsoft.appcards.diagnostics")

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("diagnostics.log")
    }

    static func event(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message)\n"
        queue.async {
            let url = fileURL
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
