import SwiftUI

enum AppLanguage {
  static let key = "pocketcrew.language"
  static let supported = ["en", "es", "zh-Hans"]
  static let catalog: [String: [String: String]] = {
    guard let url = Bundle.module.url(forResource: "translations", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let value = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
    return value
  }()
  static func text(_ value: String) -> String {
    let language = UserDefaults.standard.string(forKey: key) ?? "en"
    return catalog[value]?[language] ?? value
  }
}

struct LanguagePicker: View {
  @AppStorage(AppLanguage.key) private var language = "en"
  var body: some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 12) {
        Picker(AppLanguage.text("Language"), selection: $language) {
          Text("English").tag("en")
          Text("Español").tag("es")
          Text("简体中文").tag("zh-Hans")
        }
        Text(AppLanguage.text("Choose your language. Your family’s words stay unchanged."))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
