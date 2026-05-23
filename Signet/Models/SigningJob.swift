import Foundation

struct SigningJob: Identifiable, Codable {
    var id: UUID = UUID()
    var ipaID: UUID
    var certificateID: UUID
    var ipaName: String
    var certificateName: String
    var status: Status
    var progress: Double
    var dateCreated: Date
    var dateCompleted: Date?
    var outputFileName: String?
    var errorMessage: String?

    enum Status: String, Codable, CaseIterable {
        case queued = "Queued"
        case signing = "Signing"
        case completed = "Completed"
        case failed = "Failed"
        case installing = "Installing"

        var systemImage: String {
            switch self {
            case .queued:     return "clock"
            case .signing:    return "signature"
            case .completed:  return "checkmark.circle.fill"
            case .failed:     return "xmark.circle.fill"
            case .installing: return "arrow.down.circle.fill"
            }
        }
    }

    func outputURL(in directory: URL) -> URL? {
        guard let name = outputFileName else { return nil }
        return directory.appendingPathComponent(name)
    }
}
