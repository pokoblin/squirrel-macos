import Darwin
import Foundation

public enum ApplyError: Error, Equatable, Sendable, CustomStringConvertible {
    case busy
    case squirrelNotInstalled
    case writeFailed(String, restored: Bool)

    public var description: String {
        switch self {
        case .busy:
            return "正在应用改动，请稍等再试"
        case .squirrelNotInstalled:
            return "还没有安装鼠须管"
        case let .writeFailed(message, restored):
            return restored
                ? "写入配置时出错，已经自动还原成写入前的样子：\(message)"
                : "写入配置时出错，自动还原也失败了，请用 rimectl restore 手动还原：\(message)"
        }
    }
}

/// 锁文件：同一时间只允许一个应用改动（应用和 rimectl 共用）。对象释放时解锁。
public final class ApplyLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    public static func acquire(_ paths: AppPaths) throws -> ApplyLock {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let fd = open(paths.lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw ApplyError.busy }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw ApplyError.busy
        }
        return ApplyLock(descriptor: fd)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
