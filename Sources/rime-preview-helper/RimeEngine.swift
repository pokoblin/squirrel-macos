import CRimeAPI
import Darwin
import Foundation
import RimeGuard
import RimePreviewProtocol

/// 加载鼠须管的 librime，在一份配置副本上开一个会话。只在一个线程里用。
final class RimeEngine {
    private let squirrelApp: URL
    private var api: UnsafeMutablePointer<RimeApiPrefix>?
    /// dlopen、dlsym 失败的原因（之后每个 open 都回 loadFailed）
    private var loadError: String?
    /// 版本检查没过的原因（之后每个 open 都回 unsupportedVersion）
    private var versionError: String?
    private var version = ""

    /// 已经 initialize 过的用户目录（nil 是还没初始化）
    private var initializedDir: String?
    private var session: RimeSessionId = 0
    private var isOpen = false
    /// 交给 librime 的字符串。glog 会一直留着 app_name 的指针，所以这些都不释放
    private var retainedStrings: [UnsafeMutablePointer<CChar>] = []

    init(squirrelApp: URL) {
        self.squirrelApp = squirrelApp
        let path = squirrelApp.appending(path: "Contents/Frameworks/librime.1.dylib").path
        guard let handle = dlopen(path, RTLD_NOW) else {
            loadError = dlerror().map { String(cString: $0) } ?? "dlopen 失败：\(path)"
            return
        }
        guard let symbol = dlsym(handle, "rime_get_api") else {
            loadError = dlerror().map { String(cString: $0) } ?? "找不到 rime_get_api"
            return
        }
        typealias GetAPI = @convention(c) () -> UnsafeMutableRawPointer?
        guard let raw = unsafeBitCast(symbol, to: GetAPI.self)() else {
            loadError = "rime_get_api 返回了空指针"
            return
        }
        let api = raw.assumingMemoryBound(to: RimeApiPrefix.self)
        self.api = api
        versionError = Self.checkVersion(api, version: &version)
    }

    /// 主版本 1、次版本 ≥ 16，函数表至少到下标 74；没问题返回 nil
    private static func checkVersion(_ api: UnsafeMutablePointer<RimeApiPrefix>, version: inout String) -> String? {
        let needed = MemoryLayout<RimeApiPrefix>.size - MemoryLayout<Int32>.size
        guard Int(api.pointee.data_size) >= needed else {
            return "librime 的函数表太短（\(api.pointee.data_size) 字节，至少要 \(needed)）"
        }
        guard let getVersion = api.pointee.get_version, let text = getVersion() else {
            return "取不到 librime 的版本号"
        }
        version = String(cString: text)
        let parts = version.split(separator: ".").map { Int($0) }
        guard parts.count >= 2, parts[0] == 1, let minor = parts[1], minor >= 16 else {
            return "librime \(version) 还没验证过（要 1.16 或更新的 1.x）"
        }
        return nil
    }

    func open(userDir: String, schema: String) -> PreviewResponse {
        isOpen = false
        // 第二道保险：真实的 ~/Library/Rime 一律拒绝，在加载配置之前
        let dirURL = URL(fileURLWithPath: userDir).standardizedFileURL
        if RimeDirectoryGuard.isInsideRealRimeDirectory(dirURL) {
            return .failure(.refusedDirectory, "不能在真实的 ~/Library/Rime 上试打：\(userDir)")
        }
        if let loadError { return .failure(.loadFailed, loadError) }
        if let versionError { return .failure(.unsupportedVersion, versionError) }
        guard let api else { return .failure(.loadFailed, "librime 没有加载") }

        // select_schema 遇到不存在的方案也返回成功，所以先自己看编译结果在不在
        let dir = dirURL.path
        let compiled = dirURL.appending(path: "build/\(schema).schema.yaml").path
        guard !schema.isEmpty, FileManager.default.fileExists(atPath: compiled) else {
            return .failure(.schemaMissing, "副本里没有 build/\(schema).schema.yaml")
        }

        if initializedDir == nil {
            var traits = makeTraits(userDir: dir)
            api.pointee.setup(&traits)
            api.pointee.initialize(&traits)
            initializedDir = dir
        } else if initializedDir != dir {
            // 换目录：finalize 会关掉所有会话，再用新目录 initialize（不用再 setup）
            api.pointee.finalize()
            session = 0
            var traits = makeTraits(userDir: dir)
            api.pointee.initialize(&traits)
            initializedDir = dir
        }
        if session == 0 {
            session = api.pointee.create_session()
            if session == 0 { return .failure(.loadFailed, "librime 建不了会话") }
        }
        guard api.pointee.select_schema(session, schema) != 0, currentSchema() == schema else {
            return .failure(.schemaMissing, "选不了方案 \(schema)")
        }
        api.pointee.clear_composition(session)
        isOpen = true
        var state = snapshot()
        state.committed = nil   // 刚打开，之前残留的上屏文字不算
        return .success(state, librimeVersion: version)
    }

    func input(_ text: String) -> PreviewResponse {
        guard isOpen, let api else { return Self.notOpen }
        // 只收可打印 ASCII；先整串检查，不合法就一个键都不发
        guard text.unicodeScalars.allSatisfy({ (0x20...0x7e).contains($0.value) }) else {
            return .failure(.badRequest, "只能输入可打印的 ASCII 字符")
        }
        // librime 不处理的字符（返回 0），鼠须管会原样交给正在打字的程序（比如没有编码时打数字、空格、标点）。
        // 这里接在上屏文字后面：先取出这个键之前已经上屏的文字，保证先后顺序
        var passed = ""
        for byte in text.utf8 {
            if api.pointee.process_key(session, Int32(byte), 0) == 0 {
                passed += takeCommit() ?? ""
                passed.unicodeScalars.append(Unicode.Scalar(byte))
            }
        }
        var state = snapshot()
        if !passed.isEmpty { state.committed = passed + (state.committed ?? "") }
        return .success(state)
    }

    func key(_ key: PreviewKey) -> PreviewResponse {
        guard isOpen, let api else { return Self.notOpen }
        _ = api.pointee.process_key(session, key.keysym, 0)
        return .success(snapshot())
    }

    func select(_ index: Int) -> PreviewResponse {
        guard isOpen, let api else { return Self.notOpen }
        guard index >= 0 else { return .failure(.badRequest, "候选序号不能是负数：\(index)") }
        // 序号超出本页时 librime 什么也不做，照样回现在的样子
        _ = api.pointee.select_candidate_on_current_page(session, index)
        return .success(snapshot())
    }

    func clear() -> PreviewResponse {
        guard isOpen, let api else { return Self.notOpen }
        api.pointee.clear_composition(session)
        return .success(snapshot())
    }

    /// stdin 关掉以后调用
    func shutdown() {
        guard let api, initializedDir != nil else { return }
        api.pointee.finalize()
        initializedDir = nil
        session = 0
        isOpen = false
    }

    /// 开关现在开着没有（繁简转换这类，名字见方案的 switches 或过滤器的 option_name）
    func option(_ name: String) -> PreviewResponse {
        guard isOpen, let api else { return Self.notOpen }
        // 成功的回复都要带现在的样子（应用那边把没有 state 的成功回复当成辅助程序坏了）
        return PreviewResponse(ok: true, state: snapshot(), option: api.pointee.get_option(session, name) != 0)
    }

    /// 本页第 index 个候选是不是对应整段输入。librime 不给每个候选管多长的编码（sel_start、sel_end 是整个片段的），
    /// 拼音里短的候选（打 nihao 时的「你」）和整句在同一页。所以开一个临时会话，重打同样的编码、翻到同一页、选它，
    /// 看还剩不剩编码。正在打的会话不动
    func covers(_ index: Int) -> PreviewResponse {
        guard isOpen, let api else { return Self.notOpen }
        guard index >= 0 else { return .failure(.badRequest, "候选序号不能是负数：\(index)") }
        let state = snapshot()
        guard !state.input.isEmpty, let schema = currentSchema() else { return PreviewResponse(ok: true, state: state, covers: false) }
        let probe = api.pointee.create_session()
        guard probe != 0 else { return .failure(.loadFailed, "librime 建不了会话") }
        defer { _ = api.pointee.destroy_session(probe) }
        guard api.pointee.select_schema(probe, schema) != 0 else { return PreviewResponse(ok: true, state: state, covers: false) }
        for byte in state.input.utf8 { _ = api.pointee.process_key(probe, Int32(byte), 0) }
        for _ in 0..<state.pageNo { _ = api.pointee.process_key(probe, PreviewKey.pageDown.keysym, 0) }
        guard api.pointee.select_candidate_on_current_page(probe, index) != 0 else {
            return PreviewResponse(ok: true, state: state, covers: false)
        }
        let rest = api.pointee.get_input(probe).map { String(cString: $0) } ?? ""
        return PreviewResponse(ok: true, state: state, covers: rest.isEmpty)
    }

    private static let notOpen = PreviewResponse.failure(.notOpen, "先发 open")

    /// 现在的样子。先读上屏再读候选：四码唯一自动上屏时候选为空，不算失败
    private func snapshot() -> PreviewState {
        guard let api else { return .empty }
        var state = PreviewState()
        state.committed = takeCommit()

        var context = RimeContext()
        context.data_size = Int32(MemoryLayout<RimeContext>.size - MemoryLayout<Int32>.size)
        guard api.pointee.get_context(session, &context) != 0 else { return state }
        defer { _ = api.pointee.free_context(&context) }

        let composition = context.composition
        state.preedit = composition.preedit.map { String(cString: $0) } ?? ""
        state.cursor = Int(composition.cursor_pos)
        state.input = api.pointee.get_input(session).map { String(cString: $0) } ?? ""
        // sel_start、sel_end、length 都是 preedit 里的字节位置：选中的是整个 preedit 才算整段
        state.wholeInput = !state.preedit.isEmpty && composition.sel_start == 0 && composition.sel_end == composition.length

        let menu = context.menu
        if let candidates = menu.candidates {
            state.candidates = (0..<Int(max(0, menu.num_candidates))).map { i in
                let c = candidates[i]
                return PreviewCandidate(text: c.text.map { String(cString: $0) } ?? "",
                                        comment: c.comment.map { String(cString: $0) } ?? "")
            }
        }
        let pageSize = Int(max(0, menu.page_size))
        if let labels = context.select_labels {
            state.labels = (0..<pageSize).map { i in
                labels[i].map { String(cString: $0) } ?? ""
            }
        } else if let keys = menu.select_keys, case let text = String(cString: keys), !text.isEmpty {
            // 没设 alternative_select_labels、设了 alternative_select_keys：鼠须管拿选词键的字符当序号
            state.labels = text.prefix(pageSize).map(String.init)
        }
        state.pageNo = Int(menu.page_no)
        state.isLastPage = menu.is_last_page != 0
        state.highlighted = Int(menu.highlighted_candidate_index)
        return state
    }

    /// 取出 librime 攒着的上屏文字（取过就清掉）；没有返回 nil
    private func takeCommit() -> String? {
        guard let api else { return nil }
        var commit = RimeCommit()
        commit.data_size = Int32(MemoryLayout<RimeCommit>.size - MemoryLayout<Int32>.size)
        guard api.pointee.get_commit(session, &commit) != 0 else { return nil }
        defer { _ = api.pointee.free_commit(&commit) }
        return commit.text.map { String(cString: $0) }
    }

    private func currentSchema() -> String? {
        guard let api else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        guard api.pointee.get_current_schema(session, &buffer, buffer.count) != 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func makeTraits(userDir: String) -> RimeTraits {
        var traits = RimeTraits()
        traits.data_size = Int32(MemoryLayout<RimeTraits>.size - MemoryLayout<Int32>.size)
        traits.shared_data_dir = retained(squirrelApp.appending(path: "Contents/SharedSupport").path)
        traits.user_data_dir = retained(userDir)
        traits.distribution_name = retained("SquirrelHelper")
        traits.distribution_code_name = retained("SquirrelHelper")
        traits.distribution_version = retained("preview")
        traits.app_name = retained("rime.squirrel-helper-preview")
        traits.min_log_level = 3        // 只记 FATAL
        traits.log_dir = retained(userDir)   // 日志写进副本目录，不碰鼠须管的日志
        return traits
    }

    private func retained(_ text: String) -> UnsafePointer<CChar> {
        let copy = strdup(text)!
        retainedStrings.append(copy)
        return UnsafePointer(copy)
    }
}
