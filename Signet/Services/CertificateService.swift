import Foundation
import Security

class CertificateService {
    static let shared = CertificateService()

    @MainActor
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

    @MainActor
    func loadIdentity(for certificate: Certificate, store: AppStore) throws -> SecIdentity {
        let p12URL = store.certsDirectory.appendingPathComponent(certificate.p12FileName)
        let p12Data = try Data(contentsOf: p12URL)
        return try extractIdentity(from: p12Data, password: certificate.password)
    }

    @MainActor
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
              let identityAny = firstItem[kSecImportItemIdentity as String]
        else {
            throw SignetError.invalidCertificate("Failed to import P12. Check password.")
        }
        return identityAny as! SecIdentity
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
        let (teamName, teamID) = extractTeamInfo(from: name)

        var serialNumber = "Unknown"
        if let serialData = SecCertificateCopySerialNumberData(cert, nil) as Data? {
            serialNumber = serialData.map { String(format: "%02X", $0) }.joined(separator: ":")
        }

        let certData = SecCertificateCopyData(cert) as Data
        let dates = Self.parseValidityDates(from: certData)
        let expiryDate   = dates?.notAfter  ?? Date().addingTimeInterval(365 * 24 * 3600)
        let creationDate = dates?.notBefore ?? Date()

        return (name: name, teamName: teamName, teamID: teamID,
                serialNumber: serialNumber, expiryDate: expiryDate, creationDate: creationDate)
    }

    private func extractTeamInfo(from subjectSummary: String) -> (teamName: String, teamID: String) {
        var teamID = "Unknown"
        var teamName = "Unknown"

        if let parenStart = subjectSummary.lastIndex(of: "("),
           let parenEnd = subjectSummary.lastIndex(of: ")"),
           parenStart < parenEnd {
            let idStart = subjectSummary.index(after: parenStart)
            teamID = String(subjectSummary[idStart..<parenEnd])

            if let colonRange = subjectSummary.range(of: ": ") {
                let nameStart = colonRange.upperBound
                let nameEnd   = parenStart == subjectSummary.startIndex
                    ? parenStart
                    : subjectSummary.index(before: parenStart)
                if nameStart <= nameEnd {
                    teamName = String(subjectSummary[nameStart...nameEnd])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        } else if let colonRange = subjectSummary.range(of: ": ") {
            teamName = String(subjectSummary[colonRange.upperBound...])
        }

        return (teamName, teamID)
    }

    private static func parseValidityDates(from certData: Data) -> (notBefore: Date, notAfter: Date)? {
        let bytes = [UInt8](certData)
        var pos = 0

        func readByte() -> UInt8? {
            guard pos < bytes.count else { return nil }
            let b = bytes[pos]; pos += 1; return b
        }
        func readLen() -> Int? {
            guard let b = readByte() else { return nil }
            if b & 0x80 == 0 { return Int(b) }
            let n = Int(b & 0x7F)
            guard n > 0, n <= 4 else { return nil }
            var l = 0
            for _ in 0..<n {
                guard let b2 = readByte() else { return nil }
                l = (l << 8) | Int(b2)
            }
            return l
        }
        func skipValue() {
            guard readByte() != nil, let l = readLen() else { return }
            pos += min(l, bytes.count - pos)
        }

        guard readByte() == 0x30, readLen() != nil else { return nil }
        guard readByte() == 0x30, readLen() != nil else { return nil }
        if pos < bytes.count && bytes[pos] == 0xA0 { skipValue() }
        skipValue()
        skipValue()
        skipValue()
        guard readByte() == 0x30, readLen() != nil else { return nil }

        func readTime() -> Date? {
            guard let tag = readByte(), let len = readLen(), pos + len <= bytes.count else { return nil }
            let s = String(bytes: bytes[pos..<pos+len], encoding: .ascii) ?? ""
            pos += len
            let df = DateFormatter()
            df.locale = TimeZone(identifier: "UTC").map { _ in Locale(identifier: "en_US_POSIX") }
                ?? Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "UTC")
            df.dateFormat = (tag == 0x17) ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
            return df.date(from: s)
        }

        guard let notBefore = readTime(), let notAfter = readTime() else { return nil }
        return (notBefore, notAfter)
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
