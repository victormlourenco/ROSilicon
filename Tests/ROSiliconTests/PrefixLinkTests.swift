import Foundation
import Testing
@testable import ROSilicon

/// The links `prepare()` puts in the prefix. Every Play goes through them,
/// the second client's included, while the first may be loading from them.
struct PrefixLinkTests {

    /// Rewriting a link that is already right would leave a moment with no
    /// d3d9.dll at all, and a client starting in that moment would fall back
    /// to Wine's own Direct3D.
    @Test func aLinkAlreadyPointingAtItsTargetIsLeftAlone() throws {
        let scratch = try TemporaryDirectory()
        let target = try scratch.write(Data("dxvk".utf8), to: "app/d3d9.dll")
        let location = try scratch.makeDirectory("game").appending(path: "d3d9.dll")

        try GameRunner.link(target, at: location)
        let first = try fileNumber(of: location)
        try GameRunner.link(target, at: location)

        #expect(try fileNumber(of: location) == first)
        #expect(try destination(of: location) == target.path)
    }

    /// The app moved since the last launch: the old link dangles and is
    /// replaced rather than followed.
    @Test func aLinkToAnAppThatMovedIsReplaced() throws {
        let scratch = try TemporaryDirectory()
        let moved = scratch.url.appending(path: "old/d3d9.dll")
        let target = try scratch.write(Data("dxvk".utf8), to: "app/d3d9.dll")
        let location = try scratch.makeDirectory("game").appending(path: "d3d9.dll")
        try FileManager.default.createSymbolicLink(at: location, withDestinationURL: moved)

        try GameRunner.link(target, at: location)

        #expect(try destination(of: location) == target.path)
    }

    @Test func aFileWhereTheLinkBelongsIsReplaced() throws {
        let scratch = try TemporaryDirectory()
        let target = try scratch.write(Data("dxvk".utf8), to: "app/d3d9.dll")
        let location = try scratch.write(Data("stale copy".utf8), to: "game/d3d9.dll")

        try GameRunner.link(target, at: location)

        #expect(try destination(of: location) == target.path)
    }

    private func destination(of link: URL) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    }

    /// The link's own inode, not its target's.
    private func fileNumber(of link: URL) throws -> Int {
        try #require(
            FileManager.default.attributesOfItem(atPath: link.path)[.systemFileNumber] as? Int)
    }
}
