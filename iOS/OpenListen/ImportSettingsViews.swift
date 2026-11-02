import SwiftUI

struct ImportView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var links = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("加入連結") {
                    TextEditor(text: $links).frame(minHeight: 130).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().keyboardType(.URL).accessibilityLabel("YouTube 連結，每行一條")
                    Text("影片、播放清單或頻道，每行一條。每批最多 10 條連結、合共 50 項音訊。").font(.caption).foregroundStyle(.secondary)
                    Button("儲存連結，稍後處理", systemImage: "bookmark") {
                        library.saveSources(links); links = ""
                    }.disabled(links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button {
                        let urls = links.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                        Task { await library.importSources(urls) }
                    } label: { Label(library.importing ? "正在讀取清單…" : "開始處理", systemImage: "arrow.down.circle.fill") }
                        .disabled(library.importing || links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !library.snapshot.savedSources.isEmpty {
                    Section("已儲存連結 · \(library.snapshot.savedSources.count)") {
                        ForEach(library.snapshot.savedSources, id: \.self) { Text($0).font(.caption).lineLimit(2) }
                            .onDelete { offsets in library.snapshot.savedSources.remove(atOffsets: offsets); library.persist() }
                        Button("處理已儲存的前 10 條", systemImage: "arrow.down.to.line") {
                            Task { await library.importSources(Array(library.snapshot.savedSources.prefix(10))) }
                        }.disabled(library.importing)
                        Text("儲存連結會保留，方便再次檢查頻道更新；可向左掃移除。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("只處理你有權下載的內容。處理期間電腦需要保持開啟。直播及超過 3 小時的影片暫不支援。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("加入聲音").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
                .alert("加入結果", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
                    Button("知道了") { library.message = nil }
                } message: { Text(library.message ?? "") }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var address = ""
    @State private var token = ""
    @State private var connecting = false
    var body: some View {
        Form {
            Section("連接你的電腦") {
                TextField("http://my-mac.local:8765", text: $address).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("電腦地址")
                SecureField("電腦顯示的配對碼", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(connecting ? "連線中…" : "儲存並測試連線") {
                    connecting = true
                    Task { await library.connect(address: address, token: token); connecting = false }
                }.disabled(connecting || address.isEmpty || token.isEmpty)
                Text(library.connectionStatus).font(.footnote).foregroundStyle(.secondary)
            }
            Section("安裝方式") {
                Text("在電腦啟動 OpenListen Companion，將電腦地址與配對碼填在上面。首次連線時，請允許存取本地網絡。")
                    .font(.subheadline)
                Text("手機與電腦使用同一個可信任的 Wi-Fi。外出使用需要自行配置安全連線；已下載的內容可隨時離線播放。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("OpenListen 0.1") {
                Label("免費 · MIT 開源授權", systemImage: "chevron.left.forwardslash.chevron.right")
                Label("音檔存在你的 iPhone", systemImage: "iphone")
                Text("沒有收費、廣告或使用分析。配對碼存於 iPhone 鑰匙圈，程式不會要求你的 YouTube 密碼。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("設定")
            .onAppear { address = library.address; token = PairingKey.read() }
    }
}
