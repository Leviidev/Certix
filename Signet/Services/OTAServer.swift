import Foundation
import Network

@MainActor
class OTAServer: ObservableObject {
    static let shared = OTAServer()

    @Published var isRunning = false
    @Published var serverURL = ""
    @Published var port: UInt16 = 8080

    private var listener: NWListener?
    private var servedIPA: URL?
    private var servedJobID: UUID?

    func start(for job: SigningJob, store: AppStore) throws {
        guard let outputFile = job.outputFileName else {
            throw SignetError.serverError("No output file for job")
        }

        servedIPA = store.signingDirectory.appendingPathComponent(outputFile)
        servedJobID = job.id

        guard let ipa = store.ipas.first(where: { $0.id == job.ipaID }) else {
            throw SignetError.serverError("IPA not found")
        }

        let params = NWParameters.tcp
        let nwPort = NWEndpoint.Port(integerLiteral: port)
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.handleConnection(connection, ipa: ipa)
            }
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.updateServerURL()
                case .failed, .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        serverURL = ""
    }

    func installURL(for job: SigningJob, store: AppStore) -> String {
        guard let ipa = store.ipas.first(where: { $0.id == job.ipaID }) else { return "" }
        let manifestURL = "http://localhost:\(port)/manifest/\(job.id.uuidString)"
        _ = ipa
        return "itms-services://?action=download-manifest&url=\(manifestURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
    }

    private func updateServerURL() {
        serverURL = "http://localhost:\(port)"
    }

    private func handleConnection(_ connection: NWConnection, ipa: IPAFile) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(on: connection, ipa: ipa)
    }

    private func receiveRequest(on connection: NWConnection, ipa: IPAFile) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            Task { @MainActor [weak self] in
                self?.handleRequest(request, on: connection, ipa: ipa)
            }
        }
    }

    private func handleRequest(_ request: String, on connection: NWConnection, ipa: IPAFile) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { connection.cancel(); return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { connection.cancel(); return }
        let path = parts[1]

        if path.hasPrefix("/manifest/") {
            serveManifest(on: connection, ipa: ipa)
        } else if path == "/app.ipa" {
            serveIPA(on: connection)
        } else {
            let resp = httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8))
            connection.send(content: resp, completion: .contentProcessed({ _ in connection.cancel() }))
        }
    }

    private func serveManifest(on connection: NWConnection, ipa: IPAFile) {
        let ipaURL = "http://localhost:\(port)/app.ipa"
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>items</key>
            <array>
                <dict>
                    <key>assets</key>
                    <array>
                        <dict>
                            <key>kind</key>
                            <string>software-package</string>
                            <key>url</key>
                            <string>\(ipaURL)</string>
                        </dict>
                    </array>
                    <key>metadata</key>
                    <dict>
                        <key>bundle-identifier</key>
                        <string>\(ipa.bundleID)</string>
                        <key>bundle-version</key>
                        <string>\(ipa.version)</string>
                        <key>kind</key>
                        <string>software</string>
                        <key>title</key>
                        <string>\(ipa.name)</string>
                    </dict>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let body = Data(manifest.utf8)
        let resp = httpResponse(status: "200 OK", contentType: "application/xml", body: body)
        connection.send(content: resp, completion: .contentProcessed({ _ in connection.cancel() }))
    }

    private func serveIPA(on connection: NWConnection) {
        guard let ipaURL = servedIPA,
              let data = try? Data(contentsOf: ipaURL) else {
            let resp = httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data("IPA not found".utf8))
            connection.send(content: resp, completion: .contentProcessed({ _ in connection.cancel() }))
            return
        }

        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/octet-stream",
            "Content-Length: \(data.count)",
            "Content-Disposition: attachment; filename=\"app.ipa\"",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed({ _ in connection.cancel() }))
    }

    private func httpResponse(status: String, contentType: String, body: Data) -> Data {
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(body)
        return response
    }
}
