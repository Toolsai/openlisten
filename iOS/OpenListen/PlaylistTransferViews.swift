import SwiftUI
import OpenListenCore

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var creating = false
    @State private var name = ""
    var body: some View {
        List {
            if library.snapshot.lists.isEmpty {
                ContentUnavailableView("為不同時刻留一份清單", systemImage: "music.note.list", description: Text("建立通勤、散步或睡前清單，再從收藏加入音訊。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(library.snapshot.lists) { list in
                NavigationLink { PlaylistDetail(id: list.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.stack.fill").font(.title2).foregroundStyle(.mint)
                            .frame(width: 48, height: 48).background(ListenStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(list.name).font(.headline)
                            Text("\(list.itemIDs.count) 項音訊").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }.listRowBackground(ListenStyle.surface)
            }.onDelete { offsets in library.snapshot.lists.remove(atOffsets: offsets); library.persist() }
        }.scrollContentBackground(.hidden).background(ListenStyle.background).navigationTitle("播放清單")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("新增", systemImage: "plus") { creating = true } } }
            .alert("建立播放清單", isPresented: $creating) {
                TextField("清單名稱", text: $name)
                Button("建立") {
                    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { library.snapshot.lists.append(ListeningList(name: value)); library.persist() }
                    name = ""
                }
                Button("取消", role: .cancel) { name = "" }
            }
    }
}

struct PlaylistDetail: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    let id: UUID
    private var list: ListeningList? { library.snapshot.lists.first { $0.id == id } }
    private var items: [AudioItem] {
        (list?.itemIDs ?? []).compactMap { id in library.snapshot.items.first { $0.id == id } }
    }
    var body: some View {
        List {
            if let first = items.first(where: { $0.localFilename != nil }) {
                Button("播放已下載項目", systemImage: "play.fill") { player.play(first, in: items.map(\.id)) }
                    .listRowBackground(ListenStyle.surface)
            }
            if items.isEmpty {
                ContentUnavailableView("清單還是空的", systemImage: "text.badge.plus", description: Text("到收藏按音訊旁的「⋯」，再選「加入播放清單」。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in AudioRow(item: item, queue: items.map(\.id)) }
                .onMove { source, destination in
                    guard let index = library.snapshot.lists.firstIndex(where: { $0.id == id }) else { return }
                    library.snapshot.lists[index].itemIDs.move(fromOffsets: source, toOffset: destination); library.persist()
                }
                .onDelete { offsets in
                    guard let index = library.snapshot.lists.firstIndex(where: { $0.id == id }) else { return }
                    let removing = Set(offsets.map { items[$0].id })
                    library.snapshot.lists[index].itemIDs.removeAll { removing.contains($0) }; library.persist()
                }
        }.scrollContentBackground(.hidden).background(ListenStyle.background)
            .navigationTitle(list?.name ?? "播放清單").toolbar { EditButton() }
    }
}

struct TransfersView: View {
    @EnvironmentObject private var library: LibraryStore
    private var pending: [AudioItem] { library.snapshot.items.filter { $0.localFilename == nil } }
    var body: some View {
        List {
            Section {
                Label(library.connectionStatus, systemImage: "desktopcomputer").font(.subheadline)
                Button("下載全部已完成音訊", systemImage: "arrow.down.to.line") {
                    for item in pending where item.state == "ready" { library.download(item) }
                }.disabled(!pending.contains { $0.state == "ready" })
            }.listRowBackground(ListenStyle.surface)
            if pending.isEmpty {
                ContentUnavailableView("已經準備好了", systemImage: "checkmark.circle", description: Text("已下載音訊可在收藏內離線播放。"))
                    .listRowBackground(Color.clear)
            } else {
                Section("處理與下載") {
                    ForEach(pending) { item in AudioRow(item: item, queue: []) }
                }
            }
        }.scrollContentBackground(.hidden).background(ListenStyle.background).navigationTitle("下載")
            .refreshable { await library.refresh() }
    }
}
