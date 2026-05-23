import Foundation

struct ProvisioningProfile: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var uuid: String
    var teamID: String
    var teamName: String
    var bundleID: String
    var expiryDate: Date
    var creationDate: Date
    var isWildcard: Bool
    var entitlements: [String: String]
    var certificateSerials: [String]

    var isExpired: Bool { expiryDate < Date() }

    var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
    }

    static func parse(from data: Data) -> ProvisioningProfile? {
        guard let plistStart = data.range(of: Data("<?xml".utf8)),
              let plistEnd = data.range(of: Data("</plist>".utf8)) else { return nil }

        let plistRange = plistStart.lowerBound ..< data.index(plistEnd.upperBound, offsetBy: 0)
        let plistData = data[plistRange]

        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }

        let name = plist["Name"] as? String ?? "Unknown"
        let uuid = plist["UUID"] as? String ?? UUID().uuidString
        let teamID = (plist["TeamIdentifier"] as? [String])?.first ?? ""
        let teamName = plist["TeamName"] as? String ?? ""
        let bundleID = (plist["Entitlements"] as? [String: Any])?["application-identifier"] as? String ?? ""
        let expiryDate = plist["ExpirationDate"] as? Date ?? Date()
        let creationDate = plist["CreationDate"] as? Date ?? Date()
        let isWildcard = bundleID.hasSuffix(".*")

        var entitlements: [String: String] = [:]
        if let ents = plist["Entitlements"] as? [String: Any] {
            for (key, val) in ents {
                entitlements[key] = "\(val)"
            }
        }

        return ProvisioningProfile(
            name: name,
            uuid: uuid,
            teamID: teamID,
            teamName: teamName,
            bundleID: bundleID,
            expiryDate: expiryDate,
            creationDate: creationDate,
            isWildcard: isWildcard,
            entitlements: entitlements,
            certificateSerials: []
        )
    }
}
