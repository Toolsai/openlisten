import Foundation
import Combine
import OpenListenCore

@MainActor
final class LibraryStore: ObservableObject {
    @Published var snapshot = LibrarySnapshot()
    @Published var address = UserDefaults.standard.string(forKey: "companionAddress") ?? ""
    @Published var message: String?
    @Published var connectionStatus = "尚未連接電腦"
    @Published var importing = false
    @Published var downloads: Set<UUID> = []
    private var observer: NSObjectProtocol?
    private var canSave = true
    private var serverRevision = 0
    private let file = LocalFiles.directory.appendingPathComponent("library.json")

    init() {
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: file))
            }
        } catch {
            let backup = LocalFiles.directory.appendingPathComponent("library-backup-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: file, to: backup)
                message = "未能讀取清單，原有資料已保留為備份。可重新連接電腦取回項目。"
            } catch {
                canSave = false
                message = "未能讀取或備份清單。暫停儲存以保留原有資料，請先備份再重試。"
            }
        }
        for index in snapshot.items.indices {
            let item = snapshot.items[index]
            snapshot.items[index].localFilename = FileManager.default.fileExists(atPath: LocalFiles.audio(item.id).path)
                ? LocalFiles.audio(item.id).lastPathComponent : nil
        }
        observer = NotificationCenter.default.addObserver(forName: .audioDownloadFinished, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, let id = notification.userInfo?["id"] as? UUID else { return }
                self.downloads.remove(id)
                if let error = notification.userInfo?["error"] as? String { self.message = error; return }
                guard let index = self.snapshot.items.firstIndex(where: { $0.id == id }) else {
                    try? FileManager.default.removeItem(at: LocalFiles.audio(id)); return
                }
                self.snapshot.items[index].localFilename = LocalFiles.audio(id).lastPathComponent
                self.persist()
            }
        }
        AudioDownloads.shared.session.getAllTasks { [weak self] tasks in
            let ids = Set(tasks.compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
            Task { @MainActor in self?.downloads = ids }
        }
    }

    var api: CompanionAPI? {
        guard let url = ConnectionAddress.parse(address), !PairingKey.read().isEmpty else { return nil }
        return CompanionAPI(baseURL: url, token: PairingKey.read())
    }

    func connect(address: String, token: String) async {
        guard let url = ConnectionAddress.parse(address) else {
            message = "請輸入電腦的本地地址，例如 http://my-mac.local:8765；公網地址須使用 HTTPS。"; return
        }
        do {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let health = try await CompanionAPI(baseURL: url, token: token).send(CompanionHealth.self, path: "v1/health")
            guard health.name == "OpenListen" else { throw AppFailure.message("這個地址並非 OpenListen 電腦工具。") }
            try PairingKey.save(token)
            self.address = url.absoluteString
            UserDefaults.standard.set(self.address, forKey: "companionAddress")
            await refresh()
            connectionStatus = health.ffmpeg ? "已連接電腦" : "已連線，電腦尚需安裝 FFmpeg"
        } catch { message = error.localizedDescription }
    }

    func refresh() async {
        guard let api else { return }
        let revision = serverRevision
        do {
            let items = try await api.send([AudioItem].self, path: "v1/tracks")
            guard revision == serverRevision else { return }
            snapshot.merge(items)
            persist()
            connectionStatus = "已連接電腦"
        } catch { connectionStatus = "電腦暫時未連線；已下載音訊仍可播放" }
    }

    func saveSources(_ text: String) {
        let sources = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for source in sources where !snapshot.savedSources.contains(source) { snapshot.savedSources.append(source) }
        persist()
    }

    func importSources(_ sources: [String]) async {
        guard !importing else { return }
        guard let api else { message = "請先到設定連接你的電腦。"; return }
        guard !sources.isEmpty, sources.count <= 10 else { message = "每次可處理 1–10 條連結。"; return }
        importing = true
        defer { importing = false }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["urls": sources, "maxEntries": 50])
            let result = try await api.send(ImportResult.self, path: "v1/imports", method: "POST", body: data)
            snapshot.merge(result.tracks)
            persist()
            message = "已加入 \(result.tracks.count) 項。\n" + result.failures.map { $0.message }.joined(separator: "\n")
        } catch { message = error.localizedDescription }
    }

    func download(_ item: AudioItem) {
        guard item.localFilename == nil, !downloads.contains(item.id) else { return }
        guard let api else { message = "請先連接你的電腦。"; return }
        downloads.insert(item.id)
        AudioDownloads.shared.start(item, api: api)
    }

    func retry(_ item: AudioItem) async {
        guard let api else { return }
        do {
            let updated = try await api.send(AudioItem.self, path: "v1/tracks/\(item.id.uuidString.lowercased())/retry", method: "POST")
            snapshot.merge([updated]); persist()
        } catch { message = error.localizedDescription }
    }

    func removeItem(_ item: AudioItem) async {
        guard let api else { message = "請先連接電腦，才能取消處理或刪除電腦上的項目。"; return }
        serverRevision += 1
        defer { serverRevision += 1 }
        do {
            let (_, response) = try await URLSession.shared.data(for: api.request("v1/tracks/\(item.id.uuidString.lowercased())", method: "DELETE"))
            guard let code = (response as? HTTPURLResponse)?.statusCode, code == 204 || code == 404 else {
                throw AppFailure.message("未能移除，請檢查電腦連線。")
            }
            removeDownload(item)
            snapshot.remove(item.id); persist()
        } catch { message = error.localizedDescription }
    }

    func removeDownload(_ item: AudioItem) {
        AudioDownloads.shared.cancel(item.id)
        downloads.remove(item.id)
        do {
            if FileManager.default.fileExists(atPath: LocalFiles.audio(item.id).path) {
                try FileManager.default.removeItem(at: LocalFiles.audio(item.id))
            }
            if let index = snapshot.items.firstIndex(where: { $0.id == item.id }) {
                snapshot.items[index].localFilename = nil
            }
            persist()
        } catch { message = error.localizedDescription }
    }

    func updatePosition(_ id: UUID, seconds: Double) {
        guard seconds.isFinite, let index = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
        snapshot.items[index].position = max(0, seconds)
        persist()
    }

    func persist() {
        guard canSave else { return }
        do { try JSONEncoder().encode(snapshot).write(to: file, options: .atomic) }
        catch { message = "未能保存清單：\(error.localizedDescription)" }
    }
}
