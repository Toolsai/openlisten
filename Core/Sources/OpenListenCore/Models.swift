import Foundation

public struct AudioItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var videoId: String
    public var title: String
    public var channel: String
    public var duration: Double?
    public var sourceURL: String
    public var state: String
    public var error: String?
    public var localFilename: String?
    public var position: Double?

    public init(id: UUID = UUID(), videoId: String, title: String, channel: String,
                duration: Double? = nil, sourceURL: String, state: String = "queued",
                error: String? = nil, localFilename: String? = nil, position: Double? = nil) {
        self.id = id; self.videoId = videoId; self.title = title; self.channel = channel
        self.duration = duration; self.sourceURL = sourceURL; self.state = state
        self.error = error; self.localFilename = localFilename; self.position = position
    }
}

public struct ListeningList: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var itemIDs: [UUID]

    public init(id: UUID = UUID(), name: String, itemIDs: [UUID] = []) {
        self.id = id; self.name = name; self.itemIDs = itemIDs
    }
}

public struct LibrarySnapshot: Codable {
    public var items: [AudioItem]
    public var lists: [ListeningList]
    public var savedSources: [String]

    public init(items: [AudioItem] = [], lists: [ListeningList] = [], savedSources: [String] = []) {
        self.items = items; self.lists = lists; self.savedSources = savedSources
    }

    public mutating func merge(_ incoming: [AudioItem]) {
        for var item in incoming {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                item.localFilename = items[index].localFilename
                item.position = items[index].position
                items[index] = item
            } else {
                items.append(item)
            }
        }
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        for index in lists.indices { lists[index].itemIDs.removeAll { $0 == id } }
    }
}

public enum ConnectionAddress {
    public static func parse(_ input: String) -> URL? {
        guard let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = components.compactMap { Int($0) }
        let privateIPv4 = components.count == 4 && octets.count == 4 && octets.allSatisfy { (0...255).contains($0) } &&
            (octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) ||
             (octets[0] == 172 && (16...31).contains(octets[1])))
        let local = host == "localhost" || host.hasSuffix(".local") || privateIPv4
        guard parts.scheme == "https" || (parts.scheme == "http" && local) else { return nil }
        return parts.url
    }
}

public func playbackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let value = Int(min(seconds, 359999))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
        : String(format: "%d:%02d", value / 60, value % 60)
}
