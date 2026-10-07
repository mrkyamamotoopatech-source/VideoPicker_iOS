//
//  OpenSourceLicenseTests.swift
//  VideoPickerTests
//

import Foundation
import Testing
@testable import VideoPicker

struct OpenSourceLicenseTests {

    @Test func listsTheLibrariesUsedForPersonDetection() {
        let names = OpenSourceLicense.all.map(\.name)

        #expect(names.contains { $0.contains("MediaPipe") })
        #expect(names.contains { $0.contains("OpenCV") })
        #expect(names.contains { $0.contains("BlazeFace") })
    }

    @Test func everyListedLicenseHasItsFullTextBundled() throws {
        // ライセンス文の同梱漏れは配布条件の違反になるので、全項目について本文を読めることを確認する
        for license in OpenSourceLicense.all {
            let text = try #require(license.loadText(), "\(license.name) のライセンス文を読み込めない")
            #expect(text.contains("Apache License"), "\(license.name) の本文がApache Licenseではない")
            #expect(text.count > 1000, "\(license.name) の本文が短すぎる")
        }
    }

    @Test func namesAreUniqueSoTheyCanIdentifyRows() {
        let ids = OpenSourceLicense.all.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test func returnsNilWhenLicenseFileIsMissing() {
        let license = OpenSourceLicense(name: "Missing", licenseName: "None", resourceName: "License-DoesNotExist")

        #expect(license.loadText() == nil)
    }
}
