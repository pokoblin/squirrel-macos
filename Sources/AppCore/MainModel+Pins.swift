import Foundation
import RimeKit

/// 候选置顶（在试打页上点候选旁边的图钉）
extension MainModel {
    /// 把试打页本页第 index 个候选调到第一位（不能置顶时什么都不做，按钮本来就是灰的）。
    /// 写之前让辅助程序确认它对应整段编码：拼音里短的候选和整句在同一页，光看编码区分不出来
    public func pinCandidate(at index: Int) async {
        guard case let .available(text, code) = preview.pinAvailability(at: index, pinned: pins.phrases) else { return }
        switch await preview.confirmCovers(index) {
        case true?:
            if pins.pin(text: text, code: code) { preview.markPersonalChanged() }
        case false?:
            pins.message = "「\(text)」只对应前面一段编码，不能置顶"
        case nil:
            pins.message = "试打出错了，没能确认「\(text)」能不能置顶，先没有置顶"
        }
    }

    public func unpin(_ phrase: Phrase) {
        let before = pins.phrases
        pins.unpin(phrase)
        if pins.phrases != before { preview.markPersonalChanged() }
    }
}
