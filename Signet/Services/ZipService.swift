import Foundation

class ZipService {
    static let shared = ZipService()

    func unzip(sourceURL: URL, destinationURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let entries = try parseZipEntries(data: data)

        for entry in entries {
            guard !entry.name.hasSuffix("/") else {
                let dir = destinationURL.appendingPathComponent(entry.name, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                continue
            }

            let destFile = destinationURL.appendingPathComponent(entry.name)
            let parentDir = destFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            let fileData: Data
            if entry.compressionMethod == 0 {
                fileData = data.subdata(in: entry.dataOffset ..< entry.dataOffset + entry.compressedSize)
            } else {
                fileData = try inflateEntry(data: data, entry: entry)
            }

            try fileData.write(to: destFile)
        }
    }

    func zip(directory: URL, outputURL: URL) throws {
        var localHeaders = Data()
        var centralDirectory = Data()
        var fileCount: UInt16 = 0

        let contents = try allFiles(in: directory)

        for fileURL in contents {
            let relativePath = String(fileURL.path.dropFirst(directory.path.count + 1))
            let fileData = try Data(contentsOf: fileURL)
            let crc = crc32ForData(data: fileData)
            let localOffset = UInt32(localHeaders.count)

            let nameData = relativePath.data(using: .utf8) ?? Data()
            let dosTime = dosDateTime(from: Date())

            var compressedSize = fileData.count + 1024
            var compressed = Data(count: compressedSize)

            let didCompress = fileData.withUnsafeBytes { inPtr in
                compressed.withUnsafeMutableBytes { outPtr in
                    rawDeflate(
                        inPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        fileData.count,
                        outPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        &compressedSize
                    ) == 0
                }
            }

            let (method, finalData): (UInt16, Data)
            if didCompress && compressedSize < fileData.count {
                method = 8
                finalData = compressed.prefix(compressedSize)
            } else {
                method = 0
                finalData = fileData
            }

            var localHeader = Data()
            localHeader.appendUInt32LE(0x04034B50)
            localHeader.appendUInt16LE(20)
            localHeader.appendUInt16LE(0)
            localHeader.appendUInt16LE(method)
            localHeader.appendUInt16LE(dosTime.time)
            localHeader.appendUInt16LE(dosTime.date)
            localHeader.appendUInt32LE(crc)
            localHeader.appendUInt32LE(UInt32(finalData.count))
            localHeader.appendUInt32LE(UInt32(fileData.count))
            localHeader.appendUInt16LE(UInt16(nameData.count))
            localHeader.appendUInt16LE(0)
            localHeader.append(nameData)
            localHeaders.append(localHeader)
            localHeaders.append(finalData)

            var cd = Data()
            cd.appendUInt32LE(0x02014B50)
            cd.appendUInt16LE(0x0317)
            cd.appendUInt16LE(20)
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(method)
            cd.appendUInt16LE(dosTime.time)
            cd.appendUInt16LE(dosTime.date)
            cd.appendUInt32LE(crc)
            cd.appendUInt32LE(UInt32(finalData.count))
            cd.appendUInt32LE(UInt32(fileData.count))
            cd.appendUInt16LE(UInt16(nameData.count))
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(0)
            cd.appendUInt32LE(0x81A40000)
            cd.appendUInt32LE(localOffset)
            cd.append(nameData)
            centralDirectory.append(cd)
            fileCount += 1
        }

        let cdOffset = UInt32(localHeaders.count)
        var eocd = Data()
        eocd.appendUInt32LE(0x06054B50)
        eocd.appendUInt16LE(0)
        eocd.appendUInt16LE(0)
        eocd.appendUInt16LE(fileCount)
        eocd.appendUInt16LE(fileCount)
        eocd.appendUInt32LE(UInt32(centralDirectory.count))
        eocd.appendUInt32LE(cdOffset)
        eocd.appendUInt16LE(0)

        var output = localHeaders
        output.append(centralDirectory)
        output.append(eocd)
        try output.write(to: outputURL)
    }

    private struct ZipEntry {
        let name: String
        let compressionMethod: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let dataOffset: Int
    }

    private func parseZipEntries(data: Data) throws -> [ZipEntry] {
        guard let eocdOffset = findEOCD(data: data) else {
            throw SignetError.invalidIPA("Not a valid ZIP file")
        }

        let cdOffset = Int(data.readUInt32LE(at: eocdOffset + 16))
        let cdSize   = Int(data.readUInt32LE(at: eocdOffset + 12))

        var entries: [ZipEntry] = []
        var pos = cdOffset

        while pos < cdOffset + cdSize {
            guard data.readUInt32LE(at: pos) == 0x02014B50 else { break }

            let compression = data.readUInt16LE(at: pos + 10)
            let crc         = data.readUInt32LE(at: pos + 16)
            let compSize    = Int(data.readUInt32LE(at: pos + 20))
            let uncompSize  = Int(data.readUInt32LE(at: pos + 24))
            let nameLen     = Int(data.readUInt16LE(at: pos + 28))
            let extraLen    = Int(data.readUInt16LE(at: pos + 30))
            let commentLen  = Int(data.readUInt16LE(at: pos + 32))
            let localOffset = Int(data.readUInt32LE(at: pos + 42))
            let name        = String(data: data[(pos + 46) ..< (pos + 46 + nameLen)], encoding: .utf8) ?? ""

            let localExtraLen = Int(data.readUInt16LE(at: localOffset + 28))
            let localNameLen  = Int(data.readUInt16LE(at: localOffset + 26))
            let dataStart     = localOffset + 30 + localNameLen + localExtraLen

            entries.append(ZipEntry(
                name: name,
                compressionMethod: compression,
                crc32: crc,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                dataOffset: dataStart
            ))

            pos += 46 + nameLen + extraLen + commentLen
        }

        return entries
    }

    private func inflateEntry(data: Data, entry: ZipEntry) throws -> Data {
        let compressedSlice = data.subdata(in: entry.dataOffset ..< entry.dataOffset + entry.compressedSize)
        var output = Data(count: entry.uncompressedSize)
        var outLen = entry.uncompressedSize

        let result: Int32 = compressedSlice.withUnsafeBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                rawInflate(
                    inPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    compressedSlice.count,
                    outPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    &outLen
                )
            }
        }

        guard result == 0 else {
            throw SignetError.invalidIPA("Decompression failed for \(entry.name)")
        }
        return output.prefix(outLen)
    }

    private func findEOCD(data: Data) -> Int? {
        let sig: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let sigData = Data(sig)
        var pos = data.count - 22
        while pos >= max(0, data.count - 65535 - 22) {
            if data[pos ..< pos + 4] == sigData { return pos }
            pos -= 1
        }
        return nil
    }

    private func crc32ForData(data: Data) -> UInt32 {
        data.withUnsafeBytes { ptr in
            crc32ForData(ptr.baseAddress?.assumingMemoryBound(to: UInt8.self), data.count)
        }
    }

    private func allFiles(in directory: URL) throws -> [URL] {
        var result: [URL] = []
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                result.append(fileURL)
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    private struct DosDateTime { let time: UInt16; let date: UInt16 }
    private func dosDateTime(from date: Date) -> DosDateTime {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(0, (comps.year ?? 1980) - 1980)
        let time = UInt16(((comps.hour ?? 0) << 11) | ((comps.minute ?? 0) << 5) | ((comps.second ?? 0) / 2))
        let d    = UInt16((year << 9) | ((comps.month ?? 1) << 5) | (comps.day ?? 1))
        return DosDateTime(time: time, date: d)
    }
}

extension Data {
    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            var val: UInt32 = 0
            memcpy(&val, ptr.baseAddress!.advanced(by: offset), 4)
            return UInt32(littleEndian: val)
        }
    }

    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            var val: UInt16 = 0
            memcpy(&val, ptr.baseAddress!.advanced(by: offset), 2)
            return UInt16(littleEndian: val)
        }
    }

    mutating func appendUInt32LE(_ val: UInt32) {
        var v = val.littleEndian
        append(Data(bytes: &v, count: 4))
    }

    mutating func appendUInt16LE(_ val: UInt16) {
        var v = val.littleEndian
        append(Data(bytes: &v, count: 2))
    }
}
