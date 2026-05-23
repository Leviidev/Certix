import Foundation
import SwiftUI
import Combine

@MainActor
class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var certificates: [Certificate] = []
    @Published var ipas: [IPAFile] = []
    @Published var signingJobs: [SigningJob] = []
    @Published var isImportingCertificate = false
    @Published var isImportingIPA = false
    @Published var activeInstallJob: SigningJob?
    @Published var serverURL: String = ""
    @Published var isServerRunning = false

    private let certsKey = "signet_certificates"
    private let ipasKey = "signet_ipas"
    private let jobsKey = "signet_jobs"

    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var ipasDirectory: URL { documentsURL.appendingPathComponent("IPAs", isDirectory: true) }
    var signingDirectory: URL { documentsURL.appendingPathComponent("Signed", isDirectory: true) }
    var certsDirectory: URL { documentsURL.appendingPathComponent("Certificates", isDirectory: true) }

    init() {
        createDirectories()
        load()
    }

    private func createDirectories() {
        [ipasDirectory, signingDirectory, certsDirectory].forEach {
            try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: certsKey),
           let decoded = try? JSONDecoder().decode([Certificate].self, from: data) {
            certificates = decoded
        }
        if let data = UserDefaults.standard.data(forKey: ipasKey),
           let decoded = try? JSONDecoder().decode([IPAFile].self, from: data) {
            ipas = decoded
        }
        if let data = UserDefaults.standard.data(forKey: jobsKey),
           let decoded = try? JSONDecoder().decode([SigningJob].self, from: data) {
            signingJobs = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(certificates) {
            UserDefaults.standard.set(data, forKey: certsKey)
        }
        if let data = try? JSONEncoder().encode(ipas) {
            UserDefaults.standard.set(data, forKey: ipasKey)
        }
        if let data = try? JSONEncoder().encode(signingJobs) {
            UserDefaults.standard.set(data, forKey: jobsKey)
        }
    }

    func addCertificate(_ cert: Certificate) {
        certificates.append(cert)
        save()
    }

    func removeCertificate(_ cert: Certificate) {
        certificates.removeAll { $0.id == cert.id }
        try? FileManager.default.removeItem(at: certsDirectory.appendingPathComponent(cert.p12FileName))
        if let profileFile = cert.profileFileName {
            try? FileManager.default.removeItem(at: certsDirectory.appendingPathComponent(profileFile))
        }
        save()
    }

    func addIPA(_ ipa: IPAFile) {
        ipas.append(ipa)
        save()
    }

    func removeIPA(_ ipa: IPAFile) {
        ipas.removeAll { $0.id == ipa.id }
        try? FileManager.default.removeItem(at: ipa.storedURL(in: ipasDirectory))
        save()
    }

    func addSigningJob(_ job: SigningJob) {
        signingJobs.insert(job, at: 0)
        save()
    }

    func updateSigningJob(_ job: SigningJob) {
        if let index = signingJobs.firstIndex(where: { $0.id == job.id }) {
            signingJobs[index] = job
            save()
        }
    }

    func removeSigningJob(_ job: SigningJob) {
        signingJobs.removeAll { $0.id == job.id }
        if let outputFile = job.outputFileName {
            try? FileManager.default.removeItem(at: signingDirectory.appendingPathComponent(outputFile))
        }
        save()
    }

    var recentJobs: [SigningJob] {
        Array(signingJobs.prefix(5))
    }

    var completedJobs: [SigningJob] {
        signingJobs.filter { $0.status == .completed }
    }
}
