import Foundation
import Security

class CertificateService {
    static let shared = CertificateService()

    func importCertificate(
        p12URL: URL,
        password: String,
        profileURL: URL?,
        store: AppStore
    ) async throws -> Certificate {
        let p12Data = try Data(contentsOf: p12URL)

        let identity = try extractIdentity(from: p12Data, password: password)
        let certInfo = try extractCertificateInfo(from: identity)

        let p12FileName = "\(certInfo.teamID)_\(UUID().uuidString).p12"
        let destP12 = store.certsDirectory.appendingPathComponent(p12FileName)
        try p12Data.write(to: destP12)

        var profileFileName: String? = nil
        var profileDataRef: String? = nil

        if let profileURL = profileURL {
            let profileData = try Data(contentsOf: profileURL)
            let pFileName = "\(certInfo.teamID)_\(UUID().uuidString).mobileprovision"
            let destProfile = store.certsDirectory.appendingPathComponent(pFileName)
            try profileData.write(to: destProfile)
            profileFileName = pFileName
            profileDataRef = pFileName
        }

        let cert = Certificate(
            name: certInfo.name,
            teamName: certInfo.teamName,
            teamID: certInfo.teamID,
            serialNumber: certInfo.serialNumber,
            expiryDate: certInfo.expiryDate,
            creationDate: certInfo.creationDate,
            p12FileName: p12FileName,
            profileFileName: profileFileName,
            p12DataRef: p12FileName,
            profileDataRef: profileDataRef,
            password: password
        )

        return cert
    }

    func loadIdentity(for certificate: Certificate, store: AppStore) throws -> SecIdentity {
        let p12URL = store.certsDirectory.appendingPathComponent(certificate.p12FileName)
        let p12Data = try Data(contentsOf: p12URL)
        return try extractIdentity(from: p12Data, password: certificate.password)
    }

    func loadProfileData(for certificate: Certificate, store: AppStore) throws -> Data? {
        guard let profileFileName = certificate.profileFileName else { return nil }
        let profileURL = store.certsDirectory.appendingPathComponent(profileFileName)
        return try? Data(contentsOf: profileURL)
    }

    private func extractIdentity(from p12Data: Data, password: String) throws -> SecIdentity {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess,
              let itemArray = items as? [[String: Any]],
              let firstItem = itemArray.first,
              let identity = firstItem[kSecImportItemIdentity as String] as? SecIdentity
        else {
            throw SignetError.invalidCertificate("Failed to import P12. Check password.")
        }
        return identity
    }

    private func extractCertificateInfo(from identity: SecIdentity) throws -> (
        name: String, teamName: String, teamID: String,
        serialNumber: String, expiryDate: Date, creationDate: Date
    ) {
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certRef)
        guard let cert = certRef else {
            throw SignetError.invalidCertificate("Cannot extract certificate from identity.")
        }

        let name = SecCertificateCopySubjectSummary(cert) as String? ?? "Unknown"

        guard let certData = SecCertificateCopyData(cert) as Data?,
              let certDict = SecCertificateCopyValues(cert, nil, nil) as? [String: Any]
        else {
            return (name: name, teamName: "Unknown", teamID: "Unknown",
                    serialNumber: "Unknown", expiryDate: Date(), creationDate: Date())
        }

        var teamName = "Unknown"
        var teamID = "Unknown"
        var expiryDate = Date().addingTimeInterval(365 * 24 * 3600)
        var creationDate = Date()
        var serialNumber = "Unknown"

        if let subjectAlt = certDict["2.5.29.17"] as? [String: Any],
           let values = subjectAlt["value"] as? [[String: Any]] {
            for val in values {
                if let label = val["label"] as? String,
                   let content = val["value"] as? String {
                    if label.contains("UID") { teamID = content }
                    if label.contains("O") && !label.contains("CN") { teamName = content }
                }
            }
        }

        if let serialObj = certDict[kSecOIDSerialNumber as String] as? [String: Any],
           let serial = serialObj["value"] as? String {
            serialNumber = serial
        }

        if let validityDict = certDict["2.5.29.32"] as? [String: Any] {
            _ = validityDict
        }

        let subjectDict = SecCertificateCopyValues(cert, [kSecOIDX509V1SubjectName as AnyObject] as CFArray, nil) as? [String: Any]
        if let subjectArray = (subjectDict?[kSecOIDX509V1SubjectName as String] as? [String: Any])?["value"] as? [[String: Any]] {
            for item in subjectArray {
                if let label = item["label"] as? String, let val = item["value"] as? String {
                    if label == (kSecOIDOrganizationalUnitName as String) { teamID = val }
                    if label == (kSecOIDOrganizationName as String) { teamName = val }
                }
            }
        }

        return (
            name: name,
            teamName: teamName,
            teamID: teamID,
            serialNumber: serialNumber,
            expiryDate: expiryDate,
            creationDate: creationDate
        )
    }
}

enum SignetError: LocalizedError {
    case invalidCertificate(String)
    case invalidIPA(String)
    case signingFailed(String)
    case serverError(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidCertificate(let msg): return "Certificate Error: \(msg)"
        case .invalidIPA(let msg): return "IPA Error: \(msg)"
        case .signingFailed(let msg): return "Signing Failed: \(msg)"
        case .serverError(let msg): return "Server Error: \(msg)"
        case .fileNotFound(let msg): return "File Not Found: \(msg)"
        }
    }
}
