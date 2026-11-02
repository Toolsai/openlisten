import XCTest
@testable import OpenListenCore

final class CoreTests: XCTestCase {
    func testRefreshPreservesOfflineAudioAndProgress() throws {
        var item = AudioItem(videoId: "abcdefghijk", title: "Title", channel: "Creator", sourceURL: "https://youtu.be/abcdefghijk")
        item.localFilename = "saved.m4a"; item.position = 42
        var snapshot = LibrarySnapshot(items: [item])
        var remote = item; remote.localFilename = nil; remote.position = nil; remote.state = "ready"
        snapshot.merge([remote, remote])
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items[0].position, 42)
        XCTAssertEqual(snapshot.items[0].localFilename, "saved.m4a")
        let reopened = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(reopened.items, snapshot.items)
    }

    func testDeletionRemovesPlaylistReferences() {
        let item = AudioItem(videoId: "abcdefghijk", title: "Title", channel: "Creator", sourceURL: "source")
        var snapshot = LibrarySnapshot(items: [item], lists: [ListeningList(name: "List", itemIDs: [item.id])])
        snapshot.remove(item.id)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.lists[0].itemIDs.isEmpty)
    }

    func testRemoteJSONDecodesWithoutLocalFields() throws {
        let json = #"{"id":"F42E25BD-800D-4979-A9F8-540319338692","videoId":"abcdefghijk","title":"Example","channel":"Creator","sourceURL":"https://youtu.be/abcdefghijk","state":"ready"}"#
        let item = try JSONDecoder().decode(AudioItem.self, from: Data(json.utf8))
        XCTAssertNil(item.localFilename)
    }

    func testPrivateConnectionAddresses() {
        for address in ["http://192.168.1.2:8765", "http://my-mac.local:8765", "http://10.1.0.2:8765", "https://audio.example.com"] {
            XCTAssertNotNil(ConnectionAddress.parse(address), address)
        }
        for address in ["http://audio.example.com", "http://192.168.1.2.evil.example", "file:///etc/passwd", "https://name:password@example.com", "https://example.com?token=secret", "http://172.32.1.1", "http://192.168.999.1"] {
            XCTAssertNil(ConnectionAddress.parse(address), address)
        }
    }

    func testPlaybackTimeHandlesUnavailableDuration() {
        XCTAssertEqual(playbackTime(.nan), "0:00")
        XCTAssertEqual(playbackTime(.infinity), "0:00")
        XCTAssertEqual(playbackTime(-1), "0:00")
        XCTAssertEqual(playbackTime(3661), "1:01:01")
    }
}
