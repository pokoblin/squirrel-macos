/// 应用的名字。只用在给人看的地方（界面、文件头、提示）；
/// 内部标识（bundle ID、数据目录 squirrel-macos、rimectl）不跟着改，免得已有数据对不上
public enum AppInfo {
    public static let name = "鼠须管助手"
    /// 和 tools/app/Info.plist 的 CFBundleShortVersionString 一致（有测试检查）。在线方案清单的 minAppVersion 和它比
    public static let version = "0.2.1"
}
