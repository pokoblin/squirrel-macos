import Darwin
import Foundation

public enum ApplyError: Error, Equatable, Sendable, CustomStringConvertible {
    case busy
    case squirrelNotInstalled
    case writeFailed(String, restored: Bool, backupID: String)
    case lockFailed(String)

    public var description: String {
        switch self {
        case .busy:
            return "正在应用改动，请稍等再试"
        case .squirrelNotInstalled:
            return "还没有安装鼠须管"
        case .lockFailed(let path):
            return "打不开锁文件 \(path)（可能没有权限或者磁盘满了）"
        case let .writeFailed(message, restored, backupID):
            return restored
                ? "写入配置时出错，已经自动还原成写入前的样子：\(message)"
                : "写入配置时出错，自动还原也失败了。写入前的备份是 \(backupID)，请用 rimectl restore \(backupID) 手动还原：\(message)"
        }
    }
}

/// 锁文件：同一时间只允许一个应用改动（应用和 rimectl 共用）。对象释放时解锁。
/// 还原到某个备份时出错
public enum RestoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(String, safetyBackupID: String, rolledBack: Bool)

    public var description: String {
        switch self {
        case let .failed(message, safetyBackupID, rolledBack):
            return rolledBack
                ? "还原时出错，已经回到还原前的样子（还原前的备份是 \(safetyBackupID)）：\(message)"
                : "还原时出错，回到还原前的样子也失败了。请用 rimectl restore \(safetyBackupID) 再试：\(message)"
        }
    }
}

public final class ApplyLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    public static func acquire(_ paths: AppPaths) throws -> ApplyLock {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let fd = open(paths.lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw ApplyError.lockFailed(paths.lockFile.path) }
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
