//
//  ScoringRunTrackerTests.swift
//  VideoPickerTests
//

import Testing
@testable import VideoPicker

struct ScoringRunTrackerTests {

    @Test func startedRunIsLatest() {
        let tracker = ScoringRunTracker().advanced()

        #expect(tracker.isLatest(tracker.latestRunID))
    }

    @Test func runBecomesStaleWhenScoringIsRestarted() {
        // Arrange: 採点を開始する
        let firstRun = ScoringRunTracker().advanced()
        let firstRunID = firstRun.latestRunID

        // Act: モード切り替えで「中止 → やり直し」が続けて起きる
        let cancelled = firstRun.advanced()
        let restarted = cancelled.advanced()

        // Assert: 古い採点の終了処理は無視され、新しい採点だけが有効
        #expect(!restarted.isLatest(firstRunID))
        #expect(restarted.isLatest(restarted.latestRunID))
    }

    @Test func runBecomesStaleWhenScoringIsCancelled() {
        let running = ScoringRunTracker().advanced()
        let runID = running.latestRunID

        let cancelled = running.advanced()

        #expect(!cancelled.isLatest(runID))
    }

    @Test func advancingDoesNotChangeTheOriginalTracker() {
        let original = ScoringRunTracker()

        _ = original.advanced()

        #expect(original == ScoringRunTracker())
    }
}
