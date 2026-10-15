import Foundation
import Testing
@testable import RimeKit

@Suite struct PackageVerifierTests {
    static let goodPkgutil = """
    Package "Squirrel-1.1.2.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Notarization: trusted by the Apple notary service
       Signed with a trusted timestamp on: 2026-01-14 01:32:48 +0000
       Certificate Chain:
        1. Developer ID Installer: Yuncao Liu (28HU5A7B46)
           Expires: 2027-02-01 22:12:15 +0000
        2. Developer ID Certification Authority
        3. Apple Root CA
    """

    @Test func 正常的包通过() throws {
        try SquirrelPackageVerifier.checkPkgutil(status: 0, output: Self.goodPkgutil)
        try SquirrelPackageVerifier.checkSpctl(status: 0, output: """
        Squirrel-1.1.2.pkg: accepted
        source=Notarized Developer ID
        origin=Developer ID Installer: Yuncao Liu (28HU5A7B46)
        """)
    }

    @Test func 包被改过() {
        #expect(throws: VerificationError.invalidPackage("Status: package is invalid (checksum did not verify)")) {
            try SquirrelPackageVerifier.checkPkgutil(status: 1, output: "Package \"bad.pkg\":\n   Status: package is invalid (checksum did not verify)\n")
        }
    }

    @Test func 别人签名的() {
        let other = Self.goodPkgutil.replacingOccurrences(of: "Yuncao Liu (28HU5A7B46)", with: "Someone Else (ABCDE12345)")
        #expect(throws: VerificationError.wrongTeam("1. Developer ID Installer: Someone Else (ABCDE12345)")) {
            try SquirrelPackageVerifier.checkPkgutil(status: 0, output: other)
        }
    }

    @Test func 没公证() {
        let output = Self.goodPkgutil.replacingOccurrences(of: "   Notarization: trusted by the Apple notary service\n", with: "")
        #expect(throws: VerificationError.notNotarized) {
            try SquirrelPackageVerifier.checkPkgutil(status: 0, output: output)
        }
    }

    @Test func 不是开发者证书签的() {
        let output = Self.goodPkgutil.replacingOccurrences(of: "signed by a developer certificate issued by Apple for distribution", with: "signed by a certificate trusted by Mac OS X")
        #expect(throws: VerificationError.notDeveloperID) {
            try SquirrelPackageVerifier.checkPkgutil(status: 0, output: output)
        }
    }

    @Test func Gatekeeper拒绝() {
        #expect(throws: VerificationError.gatekeeperRejected("junk.pkg: rejected source=no usable signature")) {
            try SquirrelPackageVerifier.checkSpctl(status: 3, output: "junk.pkg: rejected\nsource=no usable signature\n")
        }
    }

    @Test func sha256对不上() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = dir.url.appending(path: "x.pkg")
        try Data("hello".utf8).write(to: pkg)
        let actual = Hashing.sha256(of: Data("hello".utf8))
        #expect(throws: VerificationError.checksumMismatch(expected: "00", actual: actual)) {
            try SquirrelPackageVerifier().verify(pkg, sha256: "00")
        }
    }

    @Test func 错误信息是中文() {
        #expect(VerificationError.notNotarized.description == "鼠须管安装包没有经过苹果公证，不安装")
    }
}
