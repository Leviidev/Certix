import Foundation
import Security
import UIKit

class SigningService {
    static let shared = SigningService()

    @MainActor
    func sign(job: SigningJob, store: AppStore, options: SigningOptions = SigningOptions()) async {
        store.clearJobLogs()
        store.appendJobLog("→ Starting Certix signing engine")

        var updatedJob = job
        updatedJob.status = .signing
        updatedJob.progress = 0.0
        store.updateSigningJob(updatedJob)

        do {
            let outputFileName = try await performSigning(job: job, store: store, options: options) { progress in
                Task { @MainActor in
                    var j = job
                    j.status = .signing
                    j.progress = progress
                    store.updateSigningJob(j)
                }
            }

            store.appendJobLog("✓ Signing complete: \(outputFileName)")
            var completed = job
            completed.status = .completed
            completed.progress = 1.0
            completed.outputFileName = outputFileName
            completed.dateCompleted = Date()
            store.updateSigningJob(completed)

        } catch {
            store.appendJobLog("✗ Error: \(error.localizedDescription)")
            var failed = job
            failed.status = .failed
            failed.errorMessage = error.localizedDescription
            store.updateSigningJob(failed)
        }
    }

    @MainActor
    private func performSigning(
        job: SigningJob,
        store: AppStore,
        options: SigningOptions,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> String {

        store.appendJobLog("→ Loading certificate: \"\(job.certificateName)\"")
        guard let ipa = store.ipas.first(where: { $0.id == job.ipaID }) else {
            throw SignetError.fileNotFound("IPA not found")
        }
        guard let certificate = store.certificates.first(where: { $0.id == job.certificateID }) else {
            throw SignetError.fileNotFound("Certificate not found")
        }

        progressCallback(0.05)

        let identity = try CertificateService.shared.loadIdentity(for: certificate, store: store)
        let profileData = try CertificateService.shared.loadProfileData(for: certificate, store: store)

        progressCallback(0.10)

        store.appendJobLog("→ Extracting IPA: \(ipa.name) (\(ipa.fileSizeFormatted))")
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let ipaURL = ipa.storedURL(in: store.ipasDirectory)
        try ZipService.shared.unzip(sourceURL: ipaURL, destinationURL: workDir)

        progressCallback(0.25)

        let payloadDir = workDir.appendingPathComponent("Payload")
        let contents = try FileManager.default.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil)
        guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            throw SignetError.invalidIPA("No app bundle found")
        }

        store.appendJobLog("→ App bundle: \(appBundle.lastPathComponent)")

        let infoPlistURL = appBundle.appendingPathComponent("Info.plist")
        guard let plistData = FileManager.default.contents(atPath: infoPlistURL.path),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else {
            throw SignetError.invalidIPA("Cannot read Info.plist")
        }

        let origBundleID = plist["CFBundleIdentifier"] as? String ?? "app"
        store.appendJobLog("→ Original bundle ID: \(origBundleID)")

        var finalBundleID = certificate.teamID + "." + (origBundleID.split(separator: ".").last.map(String.init) ?? origBundleID)

        if options.hasBundleIDOverride {
            finalBundleID = options.customBundleID.trimmingCharacters(in: .whitespaces)
            plist["CFBundleIdentifier"] = finalBundleID
            store.appendJobLog("→ Bundle ID overridden → \(finalBundleID)")
        } else {
            plist["CFBundleIdentifier"] = finalBundleID
        }

        if options.hasAppNameOverride {
            let n = options.customAppName.trimmingCharacters(in: .whitespaces)
            plist["CFBundleName"] = n
            plist["CFBundleDisplayName"] = n
            store.appendJobLog("→ App name overridden → \(n)")
        }

        if options.hasVersionOverride {
            let v = options.customVersion.trimmingCharacters(in: .whitespaces)
            plist["CFBundleShortVersionString"] = v
            store.appendJobLog("→ Version overridden → \(v)")
        }

        if let iconData = options.customIconData {
            store.appendJobLog("→ Injecting custom icon...")
            replaceIcons(in: appBundle, with: iconData)
        }

        let updatedPlistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try updatedPlistData.write(to: infoPlistURL)

        progressCallback(0.35)

        if let profileData = profileData {
            let profileDest = appBundle.appendingPathComponent("embedded.mobileprovision")
            try profileData.write(to: profileDest)
            store.appendJobLog("→ Provisioning profile injected")
        }

        progressCallback(0.45)

        let entitlements = buildEntitlements(for: certificate, bundleID: finalBundleID, profileData: profileData)
        let entitlementsData = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)

        var binariesToSign: [URL] = []

        let binariesDir = appBundle.appendingPathComponent("Frameworks")
        if FileManager.default.fileExists(atPath: binariesDir.path) {
            let frameworks = try FileManager.default.contentsOfDirectory(at: binariesDir, includingPropertiesForKeys: nil)
            for framework in frameworks where framework.pathExtension == "framework" {
                let fwName = framework.deletingPathExtension().lastPathComponent
                let fwBinary = framework.appendingPathComponent(fwName)
                if FileManager.default.fileExists(atPath: fwBinary.path) {
                    binariesToSign.append(fwBinary)
                    store.appendJobLog("→ Framework queued: \(fwName)")
                }
            }
        }

        let mainBinaryName = plist["CFBundleExecutable"] as? String ?? appBundle.deletingPathExtension().lastPathComponent
        binariesToSign.append(appBundle.appendingPathComponent(mainBinaryName))

        for (index, binary) in binariesToSign.enumerated() {
            store.appendJobLog("→ Signing: \(binary.lastPathComponent)")
            progressCallback(0.45 + 0.40 * (Double(index) / Double(binariesToSign.count)))
            try MachOSigner.shared.sign(
                binaryURL: binary,
                identity: identity,
                bundleID: finalBundleID,
                teamID: certificate.teamID,
                entitlements: entitlementsData
            )
        }

        progressCallback(0.90)

        store.appendJobLog("→ Repackaging IPA...")
        let outputName = "\(ipa.name.replacingOccurrences(of: " ", with: "_"))_signed_\(UUID().uuidString.prefix(8)).ipa"
        let outputURL = store.signingDirectory.appendingPathComponent(outputName)
        try ZipService.shared.zip(directory: workDir, outputURL: outputURL)

        progressCallback(1.0)
        return outputName
    }

    private func replaceIcons(in appBundle: URL, with iconData: Data) {
        guard let sourceImage = UIImage(data: iconData) else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: appBundle, includingPropertiesForKeys: nil) else { return }

        for fileURL in files where fileURL.pathExtension.lowercased() == "png" {
            guard let existingData = try? Data(contentsOf: fileURL),
                  let existingImage = UIImage(data: existingData),
                  existingImage.size.width == existingImage.size.height,
                  existingImage.size.width >= 29 else { continue }

            let targetSize = existingImage.size
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let resized = renderer.image { _ in
                sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            if let newPNG = resized.pngData() {
                try? newPNG.write(to: fileURL)
            }
        }
    }

    private func buildEntitlements(for certificate: Certificate, bundleID: String, profileData: Data?) -> [String: Any] {
        var entitlements: [String: Any] = [
            "application-identifier": "\(certificate.teamID).\(bundleID)",
            "com.apple.developer.team-identifier": certificate.teamID,
            "get-task-allow": true
        ]

        if let profileData = profileData,
           let profile = ProvisioningProfile.parse(from: profileData) {
            for (key, val) in profile.entitlements where key != "application-identifier" {
                entitlements[key] = val
            }
        }

        return entitlements
    }
}
