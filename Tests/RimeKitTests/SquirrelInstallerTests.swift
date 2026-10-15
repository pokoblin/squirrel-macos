import Foundation
import Testing
@testable import RimeKit

@Suite struct SquirrelInstallerTests {
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let http: FakeHTTPClient
        let verifier: FakeVerifier
        let privileged: FakePrivileged

        var installer: SquirrelInstaller {
            SquirrelInstaller(paths: paths, locations: locations, http: http, retry: .immediate,
                              verifier: verifier, privileged: privileged)
        }
    }

    /// installed：测试开始时假装已经装了的版本（nil 表示没装）
    func env(latest: String = "1.1.2", installed: String? = nil) throws -> Env {
        let dir = try TempDir()
        var locations = try DeployFixtures.locations(dir)
        locations.squirrelApp = dir.url.appending(path: "Input Methods/Squirrel.app", directoryHint: .isDirectory)
        if let installed { try InstallFixtures.writeInfoPlist(app: locations.squirrelApp, version: installed) }
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: latest, digest: "abc123")))
        http.stub(InstallFixtures.pkgURL(latest), .success(Data("fake pkg".utf8)))
        return Env(dir: dir, paths: Fixtures.paths(dir), locations: locations, http: http,
                   verifier: FakeVerifier(), privileged: FakePrivileged(app: locations.squirrelApp, version: latest))
    }

    @Test func 没装时下载检查安装() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .installed("1.1.2", previous: nil))
        #expect(e.verifier.checkedSHA256 == ["abc123"])
        #expect(e.privileged.installedPackages == ["Squirrel.pkg"])
        let staging = (try? FileManager.default.contentsOfDirectory(atPath: e.paths.staging.path)) ?? []
        #expect(staging.isEmpty)
    }

    @Test func 已经装了同版本就不下载() async throws {
        let e = try env(installed: "1.1.2"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .alreadyInstalled("1.1.2"))
        #expect(e.http.callCount(InstallFixtures.pkgURL("1.1.2")) == 0)
        #expect(e.privileged.installedPackages.isEmpty)
    }

    @Test func 装的比最新还新也不动() async throws {
        let e = try env(latest: "1.1.2", installed: "1.2.0"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .alreadyInstalled("1.2.0"))
    }

    @Test func 旧版本会升级() async throws {
        let e = try env(latest: "1.1.2", installed: "1.1.1"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .installed("1.1.2", previous: "1.1.1"))
    }

    @Test func 加force时同版本也重装() async throws {
        let e = try env(installed: "1.1.2"); defer { e.dir.remove() }
        #expect(try await e.installer.install(force: true) == .installed("1.1.2", previous: "1.1.2"))
        #expect(e.privileged.installedPackages == ["Squirrel.pkg"])
    }

    @Test func 检查不过就不安装() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.verifier.error = .wrongTeam("1. Developer ID Installer: Someone (X)")
        await #expect(throws: VerificationError.wrongTeam("1. Developer ID Installer: Someone (X)")) {
            try await e.installer.install()
        }
        #expect(e.privileged.installedPackages.isEmpty)
        #expect(e.locations.installedSquirrelVersion == nil)
    }

    @Test func 用户取消授权() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.privileged.error = .cancelled
        await #expect(throws: InstallError.cancelled) { try await e.installer.install() }
        #expect(InstallError.cancelled.description == "你取消了授权，鼠须管没有安装")
    }

    @Test func 装完版本对不上() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.privileged.version = nil
        await #expect(throws: InstallError.versionMismatch(expected: "1.1.2", found: nil)) {
            try await e.installer.install()
        }
    }

    @Test func 正在应用配置时不安装() async throws {
        let e = try env(); defer { e.dir.remove() }
        let held = try ApplyLock.acquire(e.paths)
        await #expect(throws: ApplyError.busy) { try await e.installer.install() }
        _ = held
    }


    @Test func 版本号不是纯数字时_相同就不重装() async throws {
        let e = try env(latest: "1.2.0-rc1", installed: "1.2.0-rc1"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .alreadyInstalled("1.2.0-rc1"))
    }

    @Test func 版本号不是纯数字时也能装_装完不报版本不对() async throws {
        let e = try env(latest: "1.2.0-rc1"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .installed("1.2.0-rc1", previous: nil))
        #expect(e.privileged.installedPackages == ["Squirrel.pkg"])
    }

}
