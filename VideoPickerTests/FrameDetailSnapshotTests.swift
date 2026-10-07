//
//  FrameDetailSnapshotTests.swift
//  VideoPickerTests
//

import CoreMedia
import Testing
import UIKit
@testable import VideoPicker

struct FrameDetailSnapshotTests {

    private func makeFrames(count: Int) -> [ScoredFrame] {
        (0..<count).map { index in
            ScoredFrame(image: UIImage(), time: CMTime(seconds: Double(index), preferredTimescale: 600), score: 60 + index)
        }
    }

    @Test func selectsIndexOfTappedFrame() throws {
        // Arrange
        let frames = makeFrames(count: 4)

        // Act
        let snapshot = try #require(FrameDetailSnapshot.make(frames: frames, selectedFrameID: frames[2].id))

        // Assert
        #expect(snapshot.selectedIndex == 2)
        #expect(snapshot.frames.map(\.id) == frames.map(\.id))
    }

    @Test func returnsNilWhenTappedFrameIsNoLongerInList() {
        // 採点中の一覧更新で、タップしたフレームが間引かれた直後を想定
        let frames = makeFrames(count: 3)
        let removedFrame = makeFrames(count: 1)[0]

        #expect(FrameDetailSnapshot.make(frames: frames, selectedFrameID: removedFrame.id) == nil)
    }

    @Test func returnsNilForEmptyList() {
        let frame = makeFrames(count: 1)[0]

        #expect(FrameDetailSnapshot.make(frames: [], selectedFrameID: frame.id) == nil)
    }

    @Test func keepsFramesWhenSourceListChangesLater() throws {
        // Arrange: 採点が進むと元の一覧は並べ替え・間引きで置き換えられる
        var liveFrames = makeFrames(count: 3)
        let originalIDs = liveFrames.map(\.id)
        let snapshot = try #require(FrameDetailSnapshot.make(frames: liveFrames, selectedFrameID: liveFrames[1].id))

        // Act
        liveFrames.removeAll()

        // Assert: 詳細画面が持つ内容は変わらない
        #expect(snapshot.frames.map(\.id) == originalIDs)
        #expect(snapshot.frames[snapshot.selectedIndex].id == originalIDs[1])
    }

    @Test func eachSnapshotHasItsOwnIdentity() throws {
        // 同じフレームをもう一度タップしても、別の遷移として扱われること
        let frames = makeFrames(count: 2)

        let first = try #require(FrameDetailSnapshot.make(frames: frames, selectedFrameID: frames[0].id))
        let second = try #require(FrameDetailSnapshot.make(frames: frames, selectedFrameID: frames[0].id))

        #expect(first != second)
        #expect(first == first)
    }
}
