import Foundation
import CryptoKit

struct DER {
    static func integer(_ data: Data) -> Data {
        var content = data
        if let first = content.first, first & 0x80 != 0 {
            content.insert(0x00, at: content.startIndex)
        }
        return tag(0x02, content)
    }

    static func octetString(_ data: Data) -> Data { tag(0x04, data) }
    static func utf8String(_ str: String) -> Data { tag(0x0C, Data(str.utf8)) }

    static func oid(_ components: [UInt64]) -> Data {
        var content = Data()
        guard components.count >= 2 else { return Data() }
        content.append(UInt8(components[0] * 40 + components[1]))
        for comp in components.dropFirst(2) {
            var val = comp
            var bytes: [UInt8] = []
            bytes.append(UInt8(val & 0x7F))
            val >>= 7
            while val > 0 {
                bytes.append(UInt8((val & 0x7F) | 0x80))
                val >>= 7
            }
            content.append(contentsOf: bytes.reversed())
        }
        return tag(0x06, content)
    }

    static func sequence(_ content: Data) -> Data { tag(0x30, content) }
    static func set(_ content: Data) -> Data { tag(0x31, content) }

    static func contextTag(_ n: UInt8, explicit: Bool = true, _ content: Data) -> Data {
        tag(explicit ? (0xA0 | n) : (0x80 | n), content)
    }

    static func null() -> Data { Data([0x05, 0x00]) }

    static func utcTime(_ date: Date) -> Data {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyMMddHHmmss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return tag(0x17, Data(fmt.string(from: date).utf8))
    }

    static func tag(_ t: UInt8, _ content: Data) -> Data {
        var result = Data([t])
        result.append(encodeLength(content.count))
        result.append(content)
        return result
    }

    static func encodeLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        } else if length < 0x100 {
            return Data([0x81, UInt8(length)])
        } else if length < 0x10000 {
            return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
        } else {
            return Data([0x83, UInt8(length >> 16), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
        }
    }
}

struct OID {
    static let rsaEncryption           = DER.oid([1,2,840,113549,1,1,1])
    static let sha256WithRSAEncryption = DER.oid([1,2,840,113549,1,1,11])
    static let ecPublicKey             = DER.oid([1,2,840,10045,2,1])
    static let ecdsaWithSHA256         = DER.oid([1,2,840,10045,4,3,2])
    static let sha256                  = DER.oid([2,16,840,1,101,3,4,2,1])
    static let pkcs7Data               = DER.oid([1,2,840,113549,1,7,1])
    static let pkcs7SignedData         = DER.oid([1,2,840,113549,1,7,2])
    static let contentType             = DER.oid([1,2,840,113549,1,9,3])
    static let messageDigest           = DER.oid([1,2,840,113549,1,9,4])
    static let signingTime             = DER.oid([1,2,840,113549,1,9,5])
    static let commonName              = DER.oid([2,5,4,3])
    static let organizationName        = DER.oid([2,5,4,10])
    static let organizationalUnit      = DER.oid([2,5,4,11])
    static let countryName             = DER.oid([2,5,4,6])
}

struct CMSBuilder {

    static func buildSignedData(
        codeDirectory: Data,
        identity: SecIdentity
    ) throws -> Data {
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certRef)
        guard let cert = certRef else {
            throw SignetError.signingFailed("Cannot get certificate from identity")
        }

        var privateKey: SecKey?
        SecIdentityCopyPrivateKey(identity, &privateKey)
        guard let privKey = privateKey else {
            throw SignetError.signingFailed("Cannot get private key from identity")
        }

        let certData = SecCertificateCopyData(cert) as Data
        let digestOfCD = Data(SHA256.hash(data: codeDirectory))

        let contentTypeAttr = DER.sequence(OID.contentType + DER.set(OID.pkcs7Data))
        let signingTimeAttr = DER.sequence(OID.signingTime + DER.set(DER.utcTime(Date())))
        let messageDigestAttr = DER.sequence(OID.messageDigest + DER.set(DER.octetString(digestOfCD)))

        let authAttrsContent = contentTypeAttr + signingTimeAttr + messageDigestAttr
        let authAttrsSet = DER.tag(0x31, authAttrsContent)

        let isRSA = SecKeyGetBlockSize(privKey) > 48
        let sigAlgOID: Data
        let signAlgorithm: SecKeyAlgorithm

        if isRSA {
            sigAlgOID = OID.sha256WithRSAEncryption
            signAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
        } else {
            sigAlgOID = OID.ecdsaWithSHA256
            signAlgorithm = .ecdsaSignatureMessageX962SHA256
        }

        var signError: Unmanaged<CFError>?
        guard let sigData = SecKeyCreateSignature(privKey, signAlgorithm, authAttrsSet as CFData, &signError) as Data? else {
            throw SignetError.signingFailed("Signature creation failed: \(signError?.takeRetainedValue().localizedDescription ?? "unknown")")
        }

        let issuerAndSerial = buildIssuerAndSerial(from: certData)
        let digestAlgorithmDER = DER.sequence(OID.sha256 + DER.null())

        let signerInfo = DER.sequence(
            DER.integer(Data([0x01])) +
            issuerAndSerial +
            digestAlgorithmDER +
            authAttrsSet +
            DER.sequence(sigAlgOID + DER.null()) +
            DER.octetString(sigData)
        )

        let signedData = DER.sequence(
            DER.integer(Data([0x01])) +
            DER.set(digestAlgorithmDER) +
            DER.sequence(OID.pkcs7Data) +
            DER.contextTag(0, explicit: false, certData) +
            DER.set(signerInfo)
        )

        return DER.sequence(
            OID.pkcs7SignedData +
            DER.contextTag(0, explicit: true, signedData)
        )
    }

    private static func buildIssuerAndSerial(from certData: Data) -> Data {
        guard let cert = SecCertificateCreateWithData(nil, certData as CFData),
              let vals = SecCertificateCopyValues(cert, nil, nil) as? [String: Any] else {
            return DER.sequence(DER.sequence(Data()) + DER.integer(Data([0x01])))
        }

        var issuerData = Data()
        if let subjectArray = (vals[kSecOIDX509V1SubjectName as String] as? [String: Any])?["value"] as? [[String: Any]] {
            for item in subjectArray {
                if let label = item["label"] as? String, let val = item["value"] as? String {
                    let oidData: Data
                    switch label {
                    case kSecOIDCommonName as String:           oidData = OID.commonName
                    case kSecOIDOrganizationName as String:     oidData = OID.organizationName
                    case kSecOIDOrganizationalUnitName as String: oidData = OID.organizationalUnit
                    case kSecOIDCountryName as String:          oidData = OID.countryName
                    default: continue
                    }
                    issuerData.append(DER.set(DER.sequence(oidData + DER.utf8String(val))))
                }
            }
        }

        var serial = Data([0x01])
        if let serialVal = (vals[kSecOIDSerialNumber as String] as? [String: Any])?["value"] as? Data {
            serial = serialVal
        }

        return DER.sequence(DER.sequence(issuerData) + DER.integer(serial))
    }
}
