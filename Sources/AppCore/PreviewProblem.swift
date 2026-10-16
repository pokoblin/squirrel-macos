import Foundation
import RimeKit

/// 试打页出错时给用户看的说明（设计第 5 节）
public struct PreviewProblem: Equatable, Sendable {
    public var title: String
    public var lines: [String]
    /// 显示「重试」按钮
    public var canRetry: Bool

    public init(title: String, lines: [String], canRetry: Bool) {
        self.title = title
        self.lines = lines
        self.canRetry = canRetry
    }

    /// 没装鼠须管：界面上带去「诊断」页的按钮
    public static let notInstalled = PreviewProblem(title: "先安装鼠须管",
                                                    lines: ["试打要用鼠须管自带的 librime，可以去「诊断」页安装"], canRetry: false)

    public static func describe(_ error: any Error, squirrelInstalled: Bool, hasPending: Bool) -> PreviewProblem {
        guard squirrelInstalled else { return notInstalled }
        if let error = error as? SettingsError {
            return PreviewProblem(title: "设置有问题", lines: ["\(error)"], canRetry: false)
        }
        guard let error = error as? PreviewError else {
            return PreviewProblem(title: "试打出错了", lines: ["\(error)"], canRetry: true)
        }
        switch error {
        case .notDeployed:
            return PreviewProblem(title: "鼠须管还没部署过配置", lines: hasPending ? ["可以改看「应用后的样子」"] : [], canRetry: true)
        case let .packagesNotCached(names):
            return PreviewProblem(title: "这些方案还没下载过：\(names.joined(separator: "、"))，应用改动时会下载", lines: [], canRetry: false)
        case let .compileFailed(lines):
            return PreviewProblem(title: "新配置编译不过", lines: lines, canRetry: false)
        case .timedOut:
            return PreviewProblem(title: "试打出错了", lines: ["辅助程序太久没回应，已经停掉了"], canRetry: true)
        case let .helperDied(status, stderr):
            let how = status.map { "辅助程序意外退出了（退出码 \($0)）" } ?? "辅助程序被系统停掉了（没有退出码）"
            return PreviewProblem(title: "试打出错了", lines: [how] + stderr, canRetry: true)
        case let .failed(kind, message):
            return failed(kind, message)
        case .helperMissing, .refusedDirectory:
            return PreviewProblem(title: "试打出错了", lines: [error.description], canRetry: false)
        case .noSchemas:
            return PreviewProblem(title: "试打出错了", lines: [error.description], canRetry: true)
        }
    }

    /// 辅助程序回的错误
    private static func failed(_ kind: PreviewFailureKind, _ message: String) -> PreviewProblem {
        switch kind {
        case .loadFailed:
            // 应用和辅助程序的签名不一样（打包漏了 entitlement）：是我们的错，不让用户自己处理
            if message.contains("Team ID") {
                return PreviewProblem(title: "应用的签名有问题，试打用不了",
                                      lines: ["这是鼠须管助手打包时的问题，不是你的设置有问题，请等新版本", message], canRetry: false)
            }
            return PreviewProblem(title: "加载不了鼠须管的 librime", lines: [message], canRetry: false)
        case .unsupportedVersion:
            guard let version = firstMatch(#"\d+(\.\d+)+"#, in: message) else {
                return PreviewProblem(title: "这个版本的鼠须管还没验证过，暂时不能试打", lines: [message], canRetry: false)
            }
            return PreviewProblem(title: "这个版本的鼠须管（librime \(version)）还没验证过，暂时不能试打",
                                  lines: message == version ? [] : [message], canRetry: false)
        case .schemaMissing:
            // 辅助程序的原话：「副本里没有 build/X.schema.yaml」或「选不了方案 X」
            let schema = firstMatch(#"(?<=build/).+(?=\.schema\.yaml)"#, in: message)
                ?? firstMatch(#"(?<=选不了方案 ).+"#, in: message)
            return PreviewProblem(title: schema.map { "副本里找不到方案 \($0)" } ?? "副本里找不到这个方案",
                                  lines: ["复制配置时鼠须管可能正在部署，点「重试」再试"], canRetry: true)
        case .refusedDirectory:
            return PreviewProblem(title: "试打出错了", lines: [PreviewError.failed(kind, message).description], canRetry: false)
        case .notOpen, .badRequest:
            return PreviewProblem(title: "试打出错了", lines: [PreviewError.failed(kind, message).description], canRetry: true)
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }
}
