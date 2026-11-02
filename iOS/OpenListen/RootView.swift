import SwiftUI
import OpenListenCore

enum ListenStyle {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.07)
    static let surface = Color(red: 0.08, green: 0.10, blue: 0.14)
}

struct AudioCover: View {
    let id: UUID
    var large = false
    private var colors: [Color] { id.uuidString.first!.isNumber ? [.teal, .indigo] : [.purple, .blue] }
    var body: some View {
        RoundedRectangle(cornerRadius: large ? 32 : 12)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "waveform").font(.system(size: large ? 100 : 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.85)).accessibilityHidden(true)
            }
            .aspectRatio(1, contentMode: .fit)
    }
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @State private var tab = 0
    @State private var adding = false
    @State private var showingPlayer = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                LibraryView().navigationTitle("你的聲音收藏")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("加入", systemImage: "plus") { adding = true } } }
            }.tabItem { Label("收藏", systemImage: "waveform") }.tag(0)
            NavigationStack { PlaylistsView() }.tabItem { Label("清單", systemImage: "text.line.first.and.arrowtriangle.forward") }.tag(1)
            NavigationStack { TransfersView() }.tabItem { Label("下載", systemImage: "arrow.down.circle") }.tag(2)
            NavigationStack { SettingsView() }.tabItem { Label("設定", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let item = player.current {
                HStack(spacing: 12) {
                    Button { showingPlayer = true } label: {
                        HStack(spacing: 12) {
                            AudioCover(id: item.id).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(item.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel(player.isPlaying ? "暫停" : "播放")
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("下一首")
                }.padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $adding) { ImportView() }
        .sheet(isPresented: $showingPlayer) { PlayerView() }
        .alert("OpenListen", isPresented: Binding(get: { !adding && (library.message != nil || player.error != nil) }, set: { if !$0 { library.message = nil; player.error = nil } })) {
            Button("知道了", role: .cancel) { library.message = nil; player.error = nil }
        } message: { Text(library.message ?? player.error ?? "") }
        .onOpenURL { url in
            if url.host == "add" { adding = true } else { tab = 0 }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @State private var search = ""
    private var items: [AudioItem] {
        library.snapshot.items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.channel.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("OPENLISTEN").font(.caption.weight(.bold)).tracking(3).foregroundStyle(.mint)
                    Text("留低想聽的，\n慢慢聽。").font(.largeTitle.weight(.bold))
                    Text("\(library.snapshot.items.filter { $0.localFilename != nil }.count) 項已可離線播放")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 16)
            }.listRowBackground(Color.clear)
            if items.isEmpty {
                ContentUnavailableView("從一條連結開始", systemImage: "headphones", description: Text("按右上角「加入」，儲存影片、頻道或播放清單連結。"))
                    .listRowBackground(Color.clear)
            } else {
                Section("收藏 · \(items.count)") {
                    ForEach(items) { item in AudioRow(item: item, queue: items.map(\.id)) }
                }
            }
        }.scrollContentBackground(.hidden).background(ListenStyle.background)
            .searchable(text: $search, prompt: "搜尋名稱或創作者")
            .refreshable { await library.refresh() }
    }
}

struct AudioRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    let item: AudioItem
    let queue: [UUID]

    var body: some View {
        HStack(spacing: 12) {
            Button { playOrDownload() } label: {
                HStack(spacing: 12) {
                    AudioCover(id: item.id).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.white)
                        Text(item.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Label(status, systemImage: item.localFilename != nil ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.caption2).foregroundStyle(item.localFilename != nil ? Color.mint : .secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Menu {
                if item.localFilename != nil { Button("播放", systemImage: "play.fill") { player.play(item, in: queue) } }
                if item.state == "ready" && item.localFilename == nil { Button("下載到手機", systemImage: "arrow.down.circle") { library.download(item) } }
                if item.state == "failed" { Button("重新處理", systemImage: "arrow.clockwise") { Task { await library.retry(item) } } }
                Menu("加入播放清單", systemImage: "text.badge.plus") {
                    if library.snapshot.lists.isEmpty { Text("先到「清單」建立播放清單") }
                    ForEach(library.snapshot.lists) { list in
                        Button(list.name) {
                            if let index = library.snapshot.lists.firstIndex(where: { $0.id == list.id }),
                               !library.snapshot.lists[index].itemIDs.contains(item.id) {
                                library.snapshot.lists[index].itemIDs.append(item.id); library.persist()
                            }
                        }
                    }
                }
                if item.localFilename != nil {
                    Button("移除手機音檔", systemImage: "trash", role: .destructive) {
                        if player.currentID == item.id { player.stop() }
                        library.removeDownload(item)
                    }
                }
                if let url = URL(string: item.sourceURL) { Link("開啟原始連結", destination: url) }
                Button("移除收藏及電腦音檔", systemImage: "trash", role: .destructive) {
                    if player.currentID == item.id { player.stop() }
                    Task { await library.removeItem(item) }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("\(item.title) 的選項")
        }.padding(.vertical, 5).listRowBackground(ListenStyle.surface)
    }

    private var status: String {
        if item.localFilename != nil { return "已下載 · \(playbackTime(item.duration ?? 0))" }
        if library.downloads.contains(item.id) { return "正在下載到手機" }
        switch item.state {
        case "ready": return "準備完成 · 按一下下載"
        case "processing": return "電腦正在處理"
        case "failed": return "處理失敗 · 可重新嘗試"
        default: return "等候處理"
        }
    }
    private func playOrDownload() {
        if item.localFilename != nil { player.play(item, in: queue) }
        else if item.state == "ready" { library.download(item) }
        else if item.state == "failed" { library.message = item.error ?? "處理失敗，請重新嘗試。" }
    }
}

struct PlayerView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                if let item = player.current {
                    VStack(spacing: 28) {
                        AudioCover(id: item.id, large: true).padding(.horizontal, 8)
                        VStack(spacing: 10) {
                            Text(item.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                            Text(item.channel).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 5) {
                            Slider(value: Binding(get: { min(player.elapsed, max(player.duration, 1)) }, set: { player.seek($0) }), in: 0...max(player.duration, 1))
                                .accessibilityLabel("播放位置")
                            HStack { Text(playbackTime(player.elapsed)); Spacer(); Text(playbackTime(player.duration)) }
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 30) {
                            Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel("上一首")
                            Button { player.toggle() } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.largeTitle)
                                    .foregroundStyle(.black).frame(width: 84, height: 84).background(.mint, in: Circle())
                            }.accessibilityLabel(player.isPlaying ? "暫停" : "播放")
                            Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel("下一首")
                        }
                        Label("已存在這部 iPhone，離線也能聽", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                    }.padding(28)
                }
            }.background(ListenStyle.background).navigationTitle("正在播放").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
