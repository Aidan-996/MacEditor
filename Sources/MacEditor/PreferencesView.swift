import SwiftUI

struct PreferencesView: View {
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("tabWidth") private var tabWidth: Int = 4
    @AppStorage("softWrapDefault") private var softWrapDefault: Bool = true
    @AppStorage("theme") private var theme: String = "auto"
    @AppStorage("autosaveEnabled") private var autosaveEnabled: Bool = false
    @AppStorage("uiLanguage") private var uiLanguage: String = "system"

    private func t(_ key: String) -> String { L10n.t(key, uiLanguage) }

    var body: some View {
        Form {
            Picker(t("uiLanguage"), selection: $uiLanguage) {
                Text(t("langSystem")).tag("system")
                Text("简体中文").tag("zh")
                Text("English").tag("en")
            }
            Picker(t("theme"), selection: $theme) {
                Text(t("themeAuto")).tag("auto")
                ForEach(Theme.all, id: \.id) { th in
                    Text(th.name).tag(th.id)
                }
            }
            Stepper(value: $fontSize, in: 8...40, step: 1) {
                Text(L10n.f("fontSize", uiLanguage, Int(fontSize)))
            }
            Stepper(value: $tabWidth, in: 1...16) {
                Text(L10n.f("tabWidth", uiLanguage, tabWidth))
            }
            Toggle(t("softWrapDefault"), isOn: $softWrapDefault)
            Toggle(t("autosave"), isOn: $autosaveEnabled)
        }
        .padding(20)
        .frame(width: 420)
    }
}
