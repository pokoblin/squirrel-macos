import Foundation
import Testing
@testable import RimeKit

@Suite struct SquirrelReleaseTests {
    @Test func 版本号比较() throws {
        let v = { (s: String) in try #require(SquirrelVersion(s)) }
        #expect(try v("1.1.2") > v("1.1.1"))
        #expect(try v("1.10") > v("1.9"))
        #expect(try v("v1.2") == v("1.2.0"))
        #expect(try v("1.1") == v("1.1.0"))
        #expect(SquirrelVersion("abc") == nil)
        #expect(SquirrelVersion("") == nil)
        #expect(try v("v1.2").description == "1.2")
    }

    @Test func 读最新版本() async throws {
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: "1.1.2", digest: "ABCDEF")))
        let r = try await SquirrelReleaseSource(http: http, retry: .immediate).latest()
        #expect(r == SquirrelRelease(version: "1.1.2", downloadURL: InstallFixtures.pkgURL("1.1.2"), sha256: "abcdef"))
    }

    @Test func 没有digest时sha256为空() async throws {
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: "1.1.2", digest: nil)))
        #expect(try await SquirrelReleaseSource(http: http, retry: .immediate).latest().sha256 == nil)
    }

    @Test func 没有安装包() async {
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: "1.1.2", digest: nil, assetName: "notes.txt")))
        await #expect(throws: SquirrelReleaseError.noPackage) {
            try await SquirrelReleaseSource(http: http, retry: .immediate).latest()
        }
    }

    @Test func 读已安装的版本() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var l = try DeployFixtures.locations(dir)
        #expect(l.installedSquirrelVersion == nil)
        try InstallFixtures.writeInfoPlist(app: l.squirrelApp, version: "1.1.2")
        #expect(l.installedSquirrelVersion == "1.1.2")
        l.squirrelApp = dir.url.appending(path: "None.app")
        #expect(l.installedSquirrelVersion == nil)
    }
}
