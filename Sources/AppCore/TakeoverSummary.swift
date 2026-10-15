import Foundation
import RimeKit

/// 接管预览给界面看的摘要：只有名字、文件名和条数，没有个人内容
public struct TakeoverSummary: Sendable, Equatable {
    public var schemas: [String]
    public var options: [String]
    public var appearance: [String]
    /// 「文件：键」
    public var preservedPatches: [String]
    public var personalDicts: [String]
    public var manualPhrases: Int
    public var textReplacementMatches: Int
    public var notes: [String]
    public var replaced: [String]
    public var unchanged: Int
    public var added: [String]
    public var kept: [String]
    /// 不能接管的原因（例如读不了文本替换）
    public var blockedReason: String?

    public var canConfirm: Bool { blockedReason == nil }

    public static func make(_ proposal: TakeoverProposal, preview: TakeoverPreview, catalog: Catalog,
                            blockedReason: String?) -> TakeoverSummary {
        let s = proposal.settings
        func schemaName(_ id: String) -> String {
            let name = catalog.packageOwning(schema: id)?.schemas.first { $0.id == id }?.name ?? id
            return "\(name)（\(id)）"
        }
        var options: [String] = []
        for packageID in s.options.keys.sorted() {
            guard let spec = catalog.package(packageID) else { continue }
            for option in spec.options {
                options.append("\(spec.name) · \(option.name)：\(s.choice(option, of: spec).name)")
            }
        }
        let a = s.appearance
        var look: [String] = []
        if let v = a.fontPoint { look.append("候选字字号 \(v)") }
        if let v = a.labelFontPoint { look.append("序号字号 \(v)") }
        if let v = a.commentFontPoint { look.append("注释字号 \(v)") }
        if let v = a.colorScheme { look.append("浅色配色 \(v)") }
        if let v = a.colorSchemeDark { look.append("深色配色 \(v)") }
        if let v = a.candidateListLayout { look.append(v == .linear ? "候选横排" : "候选竖排") }
        if let v = a.textOrientation { look.append(v == .horizontal ? "文字横排" : "文字竖排") }
        if let v = a.pageSize { look.append("每页 \(v) 个候选") }
        let preserved = s.preservedPatches.sorted { $0.key < $1.key }.flatMap { name, items in
            items.map { "\(name).custom.yaml：\($0.key)" }
        }
        return TakeoverSummary(
            schemas: s.schemas.map(schemaName), options: options, appearance: look, preservedPatches: preserved,
            personalDicts: proposal.personalDicts.map(\.lastPathComponent), manualPhrases: proposal.manualPhrases.count,
            textReplacementMatches: proposal.textReplacementMatches, notes: proposal.notes + preview.warnings,
            replaced: preview.replaced, unchanged: preview.unchanged.count, added: preview.added, kept: preview.kept,
            blockedReason: blockedReason)
    }
}
