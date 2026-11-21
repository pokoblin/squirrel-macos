import AppCore
import RimeKit
import SwiftUI

struct KeysPage: View {
    @Bindable var model: MainModel

    var body: some View {
        Form {
            Section {
                Picker("单按切换中英文", selection: $model.draft.keys.asciiSwitchKey) {
                    Text("方案默认").tag(AsciiSwitchKey?.none)
                    ForEach(AsciiSwitchKey.allCases, id: \.self) { Text($0.displayName).tag(AsciiSwitchKey?.some($0)) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
