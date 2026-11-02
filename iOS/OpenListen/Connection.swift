import Foundation
import Security
import OpenListenCore

enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum PairingKey {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.openlisten.pairing", kSecAttrAccount as String: "companion"]
    }
    static func read() -> String {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String) throws {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AppFailure.message("無法儲存配對碼。") }
        var request = query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else {
            throw AppFailure.message("無法儲存配對碼。")
        }
    }
}

struct CompanionAPI {
    let baseURL: URL
    let token: String

    func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = path == "v1/imports" ? 1000 : 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send<T: Decodable>(_ type: T.Type, path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: method, body: body))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AppFailure.message(detail?["detail"] as? String ?? "連線失敗，請檢查電腦地址與配對碼。")
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

struct CompanionHealth: Decodable { let name: String; let ffmpeg: Bool }
struct ImportResult: Decodable {
    struct Failure: Decodable { let url: String; let message: String }
    let tracks: [AudioItem]
    let failures: [Failure]
}

enum LocalFiles {
    static let directory: URL = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenListen", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()
    static let audioDirectory: URL = {
        var folder = directory.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return folder
    }()
    static func audio(_ id: UUID) -> URL { audioDirectory.appendingPathComponent("\(id.uuidString).m4a") }
}

extension Notification.Name {
    static let audioDownloadFinished = Notification.Name("OpenListen.audioDownloadFinished")
}

final class AudioDownloads: NSObject, URLSessionDownloadDelegate {
    static let shared = AudioDownloads()
    static var backgroundCompletion: (() -> Void)?
    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "org.openlisten.audio-downloads")
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func start(_ item: AudioItem, api: CompanionAPI) {
        session.getAllTasks { tasks in
            guard !tasks.contains(where: { $0.taskDescription == item.id.uuidString }) else { return }
            let task = self.session.downloadTask(with: api.request("v1/tracks/\(item.id.uuidString.lowercased())/audio"))
            task.taskDescription = item.id.uuidString
            task.resume()
        }
    }

    func cancel(_ id: UUID) {
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == id.uuidString }.forEach { $0.cancel() }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let text = downloadTask.taskDescription, let id = UUID(uuidString: text) else { return }
        do {
            guard let status = (downloadTask.response as? HTTPURLResponse)?.statusCode,
                  status == 200 || status == 206 else {
                throw AppFailure.message("音檔下載失敗，請重新配對或稍後再試。")
            }
            let destination = LocalFiles.audio(id)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            notify(id, error: nil)
        } catch { notify(id, error: error.localizedDescription) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let text = task.taskDescription, let id = UUID(uuidString: text) else { return }
        notify(id, error: error.localizedDescription)
    }

    private func notify(_ id: UUID, error: String?) {
        DispatchQueue.main.async {
            var info: [String: Any] = ["id": id]
            if let error { info["error"] = error }
            NotificationCenter.default.post(name: .audioDownloadFinished, object: nil, userInfo: info)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            Self.backgroundCompletion?()
            Self.backgroundCompletion = nil
        }
    }
}
