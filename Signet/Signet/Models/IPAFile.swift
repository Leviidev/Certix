import Foundation
import SwiftUI

struct IPAFile: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var bundleID: String
    var version: String
    var buildNumber: String
    var minimumOSVersion: String
    var fileName: String
    var fileSize: Int64
    var dateAdded: Date
    var iconDataRef: String?

    var fileSizeFormatted: String {
        let bytes = Double(fileSize)
        if bytes < 1024 { return "\(fileSize) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", bytes / 1024) }
        return String(format: "%.1f MB", bytes / (1024 * 1024))
    }

    func storedURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }
}
