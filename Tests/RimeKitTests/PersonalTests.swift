import Foundation
import Testing
@testable import RimeKit

@Suite struct PersonalTests {
    @Test func 读短语文件() {
        let text = "# 注释\n\n测试短语\ttstx\t1\n没有权重\tmyqz\n坏行\n\t空短语\n"
        #expect(PhraseFile.parse(text) == [
            Phrase(text: "测试短语", code: "tstx", weight: 1),
            Phrase(text: "没有权重", code: "myqz", weight: nil),
        ])
    }

    @Test func 写短语文件() {
        let text = PhraseFile.render([Phrase(text: "甲", code: "a", weight: 1), Phrase(text: "乙", code: "b", weight: nil)])
        #expect(text == "甲\ta\t1\n乙\tb\n")
    }

    @Test func 读个人内容() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: paths.personalDicts.appending(path: "py_user.dict.yaml"))
        try Data("x".utf8).write(to: paths.personalDicts.appending(path: "readme.txt"))
        try Data("甲\ta\t1\n".utf8).write(to: paths.personalPhrases)
        let content = try PersonalContent.load(from: paths)
        #expect(content.dicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(content.phrases == [Phrase(text: "甲", code: "a", weight: 1)])
        #expect(content.hasDict(named: "py_user"))
        #expect(!content.hasDict(named: "wb_user"))
    }

    @Test func 没有个人内容时是空的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(try PersonalContent.load(from: Fixtures.paths(dir)) == .empty)
    }
}
