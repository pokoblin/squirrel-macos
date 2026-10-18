import Foundation
import Observation
import RimeKit

/// 置顶列表（personal/phrases.txt 里的每一条，候选置顶设计 5.1）。
/// 置顶、还原马上写进 personal，「应用改动」时才进 Rime 目录。文件很小，直接在主线程读写
@MainActor @Observable
public final class PinsModel {
    public private(set) var phrases: [Phrase] = []
    /// 和上次应用时不一样（底栏要显示「应用改动」）
    public private(set) var needsApply = false
    /// 刚做完的事或出的错（显示在试打页上）
    public var message: String?
    /// personal/phrases.txt 读不了时的说明（这时不能置顶、还原，免得把原文件盖掉）
    public private(set) var problem: String?

    let env: AppEnvironment
    private var store: PersonalPhraseStore { PersonalPhraseStore(paths: env.paths) }

    init(env: AppEnvironment) {
        self.env = env
    }

    /// 重读文件、重算有没有没应用的改动（应用、还原、导入以后也要调）
    public func refresh() {
        do {
            phrases = try store.load()
            problem = nil
        } catch {
            phrases = []
            problem = PhraseFileError.unreadable(String(describing: error)).description
        }
        needsApply = store.needsApply()
    }

    /// 把 text 调到 code 的第一位；同编码原来置顶的那条换掉。按磁盘上最新的文件改
    @discardableResult
    public func pin(text: String, code: String) -> Bool {
        var replaced: [Phrase] = []
        let saved = update { phrases in
            let result = CandidatePins.pinning(text: text, code: code, in: phrases)
            replaced = result.replaced
            return result.phrases
        }
        guard saved else { return false }
        var line = "已把「\(text)」调到 \(code) 的第一位，点「应用改动」后生效"
        if !replaced.isEmpty {
            line += "（替换了原来的「\(replaced.map(\.text).joined(separator: "」「"))」）"
        }
        message = line
        return true
    }

    public func unpin(_ phrase: Phrase) {
        guard update({ CandidatePins.removing(phrase, from: $0) }) else { return }
        message = "已还原 \(phrase.code) 的「\(phrase.text)」，点「应用改动」后生效"
    }

    private func update(_ change: ([Phrase]) -> [Phrase]) -> Bool {
        defer { refresh() }
        do {
            try store.update(change)
        } catch ApplyError.busy {
            message = "正在应用改动，等一下再试"
            return false
        } catch let error as PhraseFileError {
            message = "\(error)，没有改"
            return false
        } catch {
            message = "写不进手动短语：\(error)"
            return false
        }
        return true
    }
}
