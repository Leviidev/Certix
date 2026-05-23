import Foundation
import Security

struct Certificate: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var teamName: String
    var teamID: String
    var serialNumber: String
    var expiryDate: Date
    var creationDate: Date
    var p12FileName: String
    var profileFileName: String?
    var p12DataRef: String
    var profileDataRef: String?
    var password: String

    var isExpired: Bool {
        expiryDate < Date()
    }

    var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
    }

    var expiryStatus: ExpiryStatus {
        if isExpired { return .expired }
        if daysUntilExpiry <= 30 { return .expiringSoon }
        return .valid
    }

    enum ExpiryStatus {
        case valid, expiringSoon, expired

        var label: String {
            switch self {
            case .valid: return "Valid"
            case .expiringSoon: return "Expiring Soon"
            case .expired: return "Expired"
            }
        }
    }
}
