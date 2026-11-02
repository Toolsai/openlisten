import SwiftUI
import WidgetKit

struct ListenEntry: TimelineEntry { let date: Date }
struct ListenProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListenEntry { ListenEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ListenEntry) -> Void) { completion(ListenEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ListenEntry>) -> Void) {
        completion(Timeline(entries: [ListenEntry(date: .now)], policy: .never))
    }
}

@main
struct OpenListenWidget: Widget {
    let kind = "OpenListenShortcuts"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ListenProvider()) { _ in
            VStack(alignment: .leading, spacing: 14) {
                HStack { Image(systemName: "waveform").foregroundStyle(.mint); Text("OpenListen").font(.headline) }
                Text("你的聲音收藏").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Link(destination: URL(string: "openlisten://library")!) { Label("收藏", systemImage: "headphones") }
                    Link(destination: URL(string: "openlisten://add")!) { Label("加入", systemImage: "plus.circle") }
                }.font(.caption.weight(.semibold)).foregroundStyle(.mint)
            }.containerBackground(for: .widget) { Color(red: 0.05, green: 0.07, blue: 0.11) }
                .widgetURL(URL(string: "openlisten://library"))
        }
        .configurationDisplayName("OpenListen 快速入口")
        .description("開啟收藏或加入新的連結。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
