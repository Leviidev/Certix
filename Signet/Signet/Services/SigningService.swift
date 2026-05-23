import Foundation
import Security

class SigningService {
    static let shared = SigningService()

    @MainActor
    func sign(job: SigningJob, store: AppStore) async {
        var updatedJob = job
        updatedJob.status = .signing
        updatedJob.progress = 0.0
        store.updateSigningJob(updatedJob)

        do {
            let outputFileName = try await performSigning(job: job, store: store) { progress in
                Task { @MainActor in
                    var j = job
                    j.status = .signing
                    j.progress = progress
                    store.updateSigningJob(j)
                }
            }

            var completed = job
            completed.status = .completed
            completed.progress = 1.0
            completed.outputFileName = outputFileName
            completed.dateCompleted = Date()
            store.updateSigningJob(completed)

        } catch {
            var failed = job
            failed.status = .failed
            failed.errorMessage = error.localizedDescription
            store.updateSigningJob(failed)
        }
    }

    private func performSigning(
        job: SigningJob,
        store: AppStore,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> String {

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

        let infoPlistURL = appBundle.appendingPathComponent("Info.plist")
        guard let plistData = FileManager.default.contents(atPath: infoPlistURL.path),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else {
            throw SignetError.invalidIPA("Cannot read Info.plist")
        }

        let bundleID = certificate.teamID + "." + (plist["CFBundleIdentifier"] as? String ?? "app").split(separator: ".").last!

        progressCallback(0.35)

        if let profileData = profileData {
            let profileDest = appBundle.appendingPathComponent("embedded.mobileprovision")
            try profileData.write(to: profileDest)
        }

        progressCallback(0.45)

        let entitlements = buildEntitlements(for: certificate, bundleID: bundleID, profileData: profileData)
        let entitlementsData = try PropertyListSerialization.data(fromPropertyList: entitlements,
                                                                   format: .xml, options: 0)

        let binariesDir = appBundle.appendingPathComponent("Frameworks")
        var binariesToSign: [URL] = []

        if FileManager.default.fileExists(atPath: binariesDir.path) {
            let frameworks = try FileManager.default.contentsOfDirectory(at: binariesDir,
                                                                          includingPropertiesForKeys: nil)
            for framework in frameworks where framework.pathExtension == "framework" {
                let fwName = framework.deletingPathExtension().lastPathComponent
                let fwBinary = framework.appendingPathComponent(fwName)
                if FileManager.default.fileExists(atPath: fwBinary.path) {
                    binariesToSign.append(fwBinary)
                }
            }
        }

        let mainBinaryName = plist["CFBundleExecutable"] as? String ?? appBundle.deletingPathExtension().lastPathComponent
        let mainBinary = appBundle.appendingPathComponent(mainBinaryName)
        binariesToSign.append(mainBinary)

        for (index, binary) in binariesToSign.enumerated() {
            let progress = 0.45 + 0.40 * (Double(index) / Double(binariesToSign.count))
            progressCallback(progress)

            try MachOSigner.shared.sign(
                binaryURL: binary,
                identity: identity,
                bundleID: bundleID,
                teamID: certificate.teamID,
                entitlements: entitlementsData
            )
        }

        progressCallback(0.90)

        let outputName = "\(ipa.name.replacingOccurrences(of: " ", with: "_"))_signed_\(UUID().uuidString.prefix(8)).ipa"
        let outputURL = store.signingDirectory.appendingPathComponent(outputName)
        try ZipService.shared.zip(directory: workDir, outputURL: outputURL)

        progressCallback(1.0)
        return outputName
    }

    private func buildEntitlements(for certificate: Certificate, bundleID: String, profileData: Data?) -> [String: Any] {
        var entitlements: [String: Any] = [
            "application-identifier": "\(certificate.teamID).\(bundleID)",
            "com.apple.developer.team-identifier": certificate.teamID,
            "get-task-allow": true
        ]

        if let profileData = profileData,
           let profile = ProvisioningProfile.parse(from: profileData) {
            for (key, val) in profile.entitlements {
                if key != "application-identifier" {
                    entitlements[key] = val
                }
            }
        }

        return entitlements
    }
}
