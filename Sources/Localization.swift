import Foundation

let localizedChineseStrings: [String: String] = {
    guard let url = Bundle.main.url(forResource: "zh-Hans", withExtension: "json", subdirectory: "Localizations"),
          let data = try? Data(contentsOf: url),
          let strings = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return strings
}()

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let language = UserDefaults.standard.string(forKey: "ui.language") ?? "zh-Hans"
    let template = language == "zh-Hans" ? (localizedChineseStrings[key] ?? key) : key
    return arguments.isEmpty ? template : String(format: template, locale: Locale(identifier: language == "en" ? "en_US" : "zh_CN"), arguments: arguments)
}
