import Foundation
import Testing
@testable import SuiteCore

@Suite struct SuiteAppsTests {
    @Test func clipboardMessagesHaveTheirOwnNames() {
        let names = Set(ClipboardMessage.allCases.map(\.name.rawValue))
        #expect(names.count == ClipboardMessage.allCases.count)
        #expect(names.allSatisfy { $0.hasPrefix(ClipboardApp.bundleID + ".") })
    }

    @Test func bindingsMessagesHaveTheirOwnNames() {
        let names = Set(BindingsMessage.allCases.map(\.name.rawValue))
        #expect(names.count == BindingsMessage.allCases.count)
        #expect(names.allSatisfy { $0.hasPrefix("local.suite.bindings.") })
        #expect(ExplorerContext.bundleID == "local.suite.explorer")
    }

    @Test func viewerShowsPicturesButNotPDFsOrIcons() {
        #expect(ViewerApp.showsPicture(URL(fileURLWithPath: "/a/photo.jpg")))
        #expect(ViewerApp.showsPicture(URL(fileURLWithPath: "/a/photo.HEIC")))
        #expect(!ViewerApp.showsPicture(URL(fileURLWithPath: "/a/book.pdf")))
        #expect(!ViewerApp.showsPicture(URL(fileURLWithPath: "/a/App.icns")))
        #expect(!ViewerApp.showsPicture(URL(fileURLWithPath: "/a/notes.txt")))
        #expect(ViewerApp.showsPDF(URL(fileURLWithPath: "/a/book.pdf")))
    }
}
