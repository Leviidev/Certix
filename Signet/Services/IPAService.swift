import Foundation
import UIKit

class IPAService {
    static let shared = IPAService()

    @MainActor
    func importIPA(from sourceURL: URL, store: AppStore) async throws -> IPAFile {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let fileName = "\(UUID().uuidString).ipa"
        let destURL = store.ipasDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        let metadata = try await extractMetadata(from: destURL)

        return IPAFile(
            name: metadata.name,
            bundleID: metadata.bundleID,
            version: metadata.version,
            buildNumber: metadata.buildNumber,
            minimumOSVersion: metadata.minimumOSVersion,
            fileName: fileName,
            fileSize: fileSize,
            dateAdded: Date(),
            iconDataRef: metadata.iconFileName
        )
    }

    private func extractMetadata(from ipaURL: URL) async throws -> (
        name: String, bundleID: String, version: String,
        buildNumber: String, minimumOSVersion: String, iconFileName: String?
    ) {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        try ZipService.shared.unzip(sourceURL: ipaURL, destinationURL: workDir)

        let payloadDir = workDir.appendingPathComponent("Payload")
        let contents = try FileManager.default.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil)
        guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            throw SignetError.invalidIPA("No app bundle found in Payload")
        }

        let infoPlistURL = appBundle.appendingPathComponent("Info.plist")
        guard let plistData = FileManager.default.contents(atPath: infoPlistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else {
            throw SignetError.invalidIPA("Cannot read Info.plist")
        }

        let name = plist["CFBundleName"] as? String ?? plist["CFBundleDisplayName"] as? String ?? "Unknown"
        let bundleID = plist["CFBundleIdentifier"] as? String ?? "unknown"
        let version = plist["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNumber = plist["CFBundleVersion"] as? String ?? "1"
        let minimumOSVersion = plist["MinimumOSVersion"] as? String ?? "16.0"

        let iconFileName = extractIcon(from: appBundle, plist: plist)

        return (name, bundleID, version, buildNumber, minimumOSVersion, iconFileName)
    }

    private func extractIcon(from appBundle: URL, plist: [String: Any]) -> String? {
        var iconNames: [String] = []

        if let icons = plist["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primaryIcon["CFBundleIconFiles"] as? [String] {
            iconNames = files.reversed()
        } else if let iconFile = plist["CFBundleIconFile"] as? String {
            iconNames = [iconFile]
        }

        for iconName in iconNames {
            let candidates = [iconName, "\(iconName)@2x", "\(iconName)@3x",
                              "\(iconName).png", "\(iconName)@2x.png", "\(iconName)@3x.png"]
            for candidate in candidates {
                let iconURL = appBundle.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: iconURL.path),
                   let data = try? Data(contentsOf: iconURL) {
                    let iconFileName = "\(UUID().uuidString).png"
                    if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let iconsDir = documentsDir.appendingPathComponent("Icons")
                        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
                        let destURL = iconsDir.appendingPathComponent(iconFileName)
                        try? data.write(to: destURL)
                        return iconFileName
                    }
                }
            }
        }
        return nil
    }

    func loadIcon(for ipa: IPAFile) -> UIImage? {
        guard let iconFileName = ipa.iconDataRef else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let iconURL = docs.appendingPathComponent("Icons/\(iconFileName)")
        guard let data = try? Data(contentsOf: iconURL) else { return nil }
        return UIImage(data: data)
    }
}
