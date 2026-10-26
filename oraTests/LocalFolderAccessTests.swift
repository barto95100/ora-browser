import Foundation
@testable import Ora
import Testing

struct LocalFolderAccessTests {
    private let site = URL(fileURLWithPath: "/Users/me/Sites/demo", isDirectory: true)
    private let sites = URL(fileURLWithPath: "/Users/me/Sites", isDirectory: true)

    @Test func aFileInsideAGrantedFolderMayReadIt() {
        let page = URL(fileURLWithPath: "/Users/me/Sites/demo/index.html")
        #expect(LocalFolderAccess.closestFolder(containing: page, in: [site]) == site)
    }

    @Test func theClosestGrantedFolderWins() {
        let page = URL(fileURLWithPath: "/Users/me/Sites/demo/pages/about.html")
        #expect(LocalFolderAccess.closestFolder(containing: page, in: [sites, site]) == site)
    }

    @Test func aFolderWithASimilarNameDoesNotCount() {
        let page = URL(fileURLWithPath: "/Users/me/Sites/demo-old/index.html")
        #expect(LocalFolderAccess.closestFolder(containing: page, in: [site]) == nil)
    }

    @Test func aFileOutsideEveryGrantedFolderHasNone() {
        let page = URL(fileURLWithPath: "/Users/me/Documents/test.html")
        #expect(LocalFolderAccess.closestFolder(containing: page, in: [site, sites]) == nil)
    }
}
