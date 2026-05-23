import Foundation
import CryptoKit
import Security

class MachOSigner {

    static let shared = MachOSigner()

    private let pageSize: Int = 4096
    private let pageShift: UInt8 = 12

    // MARK: - Public Interface

    func sign(
        binaryURL: URL,
        identity: SecIdentity,
        bundleID: String,
        teamID: String,
        entitlements: Data?
    ) throws {
        var data = try Data(contentsOf: binaryURL)

        if isFatBinary(data: data) {
            data = try signFatBinary(data: &data, identity: identity,
                                     bundleID: bundleID, teamID: teamID,
                                     entitlements: entitlements)
        } else {
            data = try signMachO(data: data, identity: identity,
                                  bundleID: bundleID, teamID: teamID,
                                  entitlements: entitlements)
        }

        try data.write(to: binaryURL)
    }

    // MARK: - Fat Binary

    private func isFatBinary(data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let magic = data.readUInt32BE(at: 0)
        return magic == 0xCAFEBABE || magic == 0xBEBAFECA
    }

    private func signFatBinary(
        data: inout Data,
        identity: SecIdentity,
        bundleID: String,
        teamID: String,
        entitlements: Data?
    ) throws -> Data {
        let magic = data.readUInt32BE(at: 0)
        let bigEndian = magic == 0xCAFEBABE
        let archCount = bigEndian ? Int(data.readUInt32BE(at: 4)) : Int(data.readUInt32LE(at: 4))

        struct ArchInfo { let offset, size, align: Int }
        var archInfos: [ArchInfo] = []

        for i in 0 ..< archCount {
            let base = 8 + i * 20
            let offset = bigEndian ? Int(data.readUInt32BE(at: base + 8))  : Int(data.readUInt32LE(at: base + 8))
            let size   = bigEndian ? Int(data.readUInt32BE(at: base + 12)) : Int(data.readUInt32LE(at: base + 12))
            let align  = bigEndian ? Int(data.readUInt32BE(at: base + 16)) : Int(data.readUInt32LE(at: base + 16))
            archInfos.append(ArchInfo(offset: offset, size: size, align: align))
        }

        var result = data
        for info in archInfos {
            let sliceData = data.subdata(in: info.offset ..< info.offset + info.size)
            let signed = try signMachO(data: sliceData, identity: identity,
                                       bundleID: bundleID, teamID: teamID,
                                       entitlements: entitlements)
            result.replaceSubrange(
                info.offset ..< info.offset + min(info.size, signed.count),
                with: signed
            )
        }
        return result
    }

    // MARK: - Mach-O Signing

    private func signMachO(
        data: Data,
        identity: SecIdentity,
        bundleID: String,
        teamID: String,
        entitlements: Data?
    ) throws -> Data {
        guard data.count >= 4 else { throw SignetError.signingFailed("Too small to be Mach-O") }

        let magic = data.readUInt32LE(at: 0)
        let is64  = (magic == 0xFEEDFACF || magic == 0xCFFAEDFE)
        let isLE  = (magic == 0xFEEDFACE || magic == 0xFEEDFACF)
        let headerSize = is64 ? 32 : 28

        let ncmds: Int = isLE
            ? (is64 ? Int(data.readUInt32LE(at: 16)) : Int(data.readUInt32LE(at: 12)))
            : (is64 ? Int(data.readUInt32BE(at: 16)) : Int(data.readUInt32BE(at: 12)))

        var lcOffset = headerSize
        var csSLCOffset    = -1
        var csDataOffset   = 0
        var csDataSize     = 0

        for _ in 0 ..< ncmds {
            let cmd     = isLE ? data.readUInt32LE(at: lcOffset)     : data.readUInt32BE(at: lcOffset)
            let cmdSize = isLE ? Int(data.readUInt32LE(at: lcOffset + 4)) : Int(data.readUInt32BE(at: lcOffset + 4))

            if cmd == 0x1D {
                csSLCOffset  = lcOffset
                csDataOffset = isLE ? Int(data.readUInt32LE(at: lcOffset + 8)) : Int(data.readUInt32BE(at: lcOffset + 8))
                csDataSize   = isLE ? Int(data.readUInt32LE(at: lcOffset + 12)) : Int(data.readUInt32BE(at: lcOffset + 12))
            }
            lcOffset += cmdSize
        }

        guard csSLCOffset >= 0 else {
            throw SignetError.signingFailed("No LC_CODE_SIGNATURE found. Binary must have a pre-allocated signature slot.")
        }

        let codeLimit = csDataOffset
        let newSig = try buildCodeSignature(
            data: data,
            codeLimit: codeLimit,
            bundleID: bundleID,
            teamID: teamID,
            identity: identity,
            entitlements: entitlements
        )

        var result = data
        let endRange = min(csDataOffset + csDataSize, result.count)

        if csDataOffset <= result.count {
            if endRange <= result.count {
                result.replaceSubrange(csDataOffset ..< endRange, with: newSig)
            } else {
                result.append(Data(repeating: 0, count: csDataOffset - result.count))
                result.append(newSig)
            }
        }

        let newSizeBytes = withUnsafeBytes(of: UInt32(newSig.count).littleEndian) { Data($0) }
        if isLE {
            result.replaceSubrange(csSLCOffset + 12 ..< csSLCOffset + 16, with: newSizeBytes)
        } else {
            let bigBytes = withUnsafeBytes(of: UInt32(newSig.count).bigEndian) { Data($0) }
            result.replaceSubrange(csSLCOffset + 12 ..< csSLCOffset + 16, with: bigBytes)
        }

        return result
    }

    // MARK: - Code Signature Builder

    private func buildCodeSignature(
        data: Data,
        codeLimit: Int,
        bundleID: String,
        teamID: String,
        identity: SecIdentity,
        entitlements: Data?
    ) throws -> Data {

        let requirements      = buildRequirementsBlob()
        let entitlementsBlob  = entitlements.map { buildEntitlementsBlob($0) }
        let codeDirectory     = buildCodeDirectory(
            data: data, codeLimit: codeLimit,
            bundleID: bundleID, teamID: teamID,
            requirements: requirements, entitlements: entitlementsBlob
        )
        let cms    = try CMSBuilder.buildSignedData(codeDirectory: codeDirectory, identity: identity)
        let cmsBlob = buildBlobWrapper(cms)

        var blobs: [(type: UInt32, data: Data)] = [
            (0x00000000, codeDirectory),
            (0x00000002, requirements),
        ]
        if let ent = entitlementsBlob { blobs.append((0x00000005, ent)) }
        blobs.append((0x00010000, cmsBlob))

        return buildSuperBlob(blobs: blobs)
    }

    // MARK: - CodeDirectory

    private func buildCodeDirectory(
        data: Data,
        codeLimit: Int,
        bundleID: String,
        teamID: String,
        requirements: Data,
        entitlements: Data?
    ) -> Data {
        let identBytes = Data(bundleID.utf8) + Data([0])
        let teamBytes  = Data(teamID.utf8)  + Data([0])
        let hashSize   = 32
        let nSpecial   = 5
        let pageCount  = (codeLimit + pageSize - 1) / pageSize
        let version: UInt32 = 0x20400

        let fixedHdrSize = 88
        let identOff = UInt32(fixedHdrSize)
        let teamOff  = identOff + UInt32(identBytes.count)
        let hashOff  = teamOff  + UInt32(teamBytes.count) + UInt32(nSpecial * hashSize)

        var cd = Data()
        cd.appendUInt32BE(0xFADE0C02)
        cd.appendUInt32BE(0)               // length (filled below)
        cd.appendUInt32BE(version)
        cd.appendUInt32BE(0)               // flags
        cd.appendUInt32BE(hashOff)
        cd.appendUInt32BE(identOff)
        cd.appendUInt32BE(UInt32(nSpecial))
        cd.appendUInt32BE(UInt32(pageCount))
        cd.appendUInt32BE(UInt32(codeLimit))
        cd.append(UInt8(hashSize))
        cd.append(UInt8(2))                // hashType: SHA-256
        cd.append(UInt8(0))                // platform
        cd.append(pageShift)
        cd.appendUInt32BE(0)               // spare2
        cd.appendUInt32BE(0)               // scatterOffset
        cd.appendUInt32BE(teamOff)
        cd.appendUInt32BE(0)               // spare3
        cd.appendUInt32BE(0); cd.appendUInt32BE(0)  // codeLimit64
        cd.appendUInt32BE(0); cd.appendUInt32BE(0)  // execSegBase
        cd.appendUInt32BE(0); cd.appendUInt32BE(0)  // execSegLimit / Flags

        cd.append(identBytes)
        cd.append(teamBytes)

        let emptyHash = Data(repeating: 0, count: hashSize)
        let reqHash   = Data(SHA256.hash(data: requirements))
        let entHash   = entitlements.map { Data(SHA256.hash(data: $0)) } ?? emptyHash

        // Special slots (negative indices, stored in reverse: -5 first)
        cd.append(emptyHash)   // slot -5: DER entitlements
        cd.append(emptyHash)   // slot -4: (unused)
        cd.append(emptyHash)   // slot -3: resource dir
        cd.append(reqHash)     // slot -2: requirements
        cd.append(entHash)     // slot -1: entitlements

        // Code slots
        for i in 0 ..< pageCount {
            let start = i * pageSize
            let end   = min(start + pageSize, codeLimit)
            let page  = data.subdata(in: start ..< end)
            cd.append(Data(SHA256.hash(data: page)))
        }

        withUnsafeBytes(of: UInt32(cd.count).bigEndian) { bytes in
            cd.replaceSubrange(4 ..< 8, with: bytes)
        }

        return cd
    }

    // MARK: - Blob Builders

    private func buildRequirementsBlob() -> Data {
        var b = Data()
        b.appendUInt32BE(0xFADE0C01)
        b.appendUInt32BE(12)
        b.appendUInt32BE(0)
        return b
    }

    private func buildEntitlementsBlob(_ plist: Data) -> Data {
        var b = Data()
        b.appendUInt32BE(0xFADE7171)
        b.appendUInt32BE(UInt32(8 + plist.count))
        b.append(plist)
        return b
    }

    private func buildBlobWrapper(_ data: Data) -> Data {
        var b = Data()
        b.appendUInt32BE(0xFADE0B01)
        b.appendUInt32BE(UInt32(8 + data.count))
        b.append(data)
        return b
    }

    private func buildSuperBlob(blobs: [(type: UInt32, data: Data)]) -> Data {
        let headerSize = 12 + blobs.count * 8
        var offsets: [UInt32] = []
        var currentOffset = UInt32(headerSize)
        for blob in blobs {
            offsets.append(currentOffset)
            currentOffset += UInt32(blob.data.count)
        }

        var result = Data()
        result.appendUInt32BE(0xFADE0CC0)
        result.appendUInt32BE(currentOffset)
        result.appendUInt32BE(UInt32(blobs.count))

        for (i, blob) in blobs.enumerated() {
            result.appendUInt32BE(blob.type)
            result.appendUInt32BE(offsets[i])
        }
        for blob in blobs { result.append(blob.data) }

        return result
    }
}

// MARK: - Data Extensions for Mach-O

extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            var val: UInt32 = 0
            memcpy(&val, ptr.baseAddress!.advanced(by: offset), 4)
            return UInt32(bigEndian: val)
        }
    }

    func readUInt64LE(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            var val: UInt64 = 0
            memcpy(&val, ptr.baseAddress!.advanced(by: offset), 8)
            return UInt64(littleEndian: val)
        }
    }

    func readUInt64BE(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            var val: UInt64 = 0
            memcpy(&val, ptr.baseAddress!.advanced(by: offset), 8)
            return UInt64(bigEndian: val)
        }
    }

    mutating func appendUInt32BE(_ val: UInt32) {
        var v = val.bigEndian
        append(Data(bytes: &v, count: 4))
    }
}
