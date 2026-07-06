import SwiftUI
import Observation

/// Persists the user's preferred quote text color to UserDefaults.
/// SillyTavern has no server endpoint for this, so it stays client-side.
@Observable
final class QuoteColorSettings {
    static let shared = QuoteColorSettings()

    private let defaultsKey = "st_quote_color"

    /// The color applied to quoted text (default: system blue).
    var quoteColor: Color {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
            quoteColor = Color(uiColor: uiColor)
        } else {
            quoteColor = .blue
        }
    }

    private func save() {
        let uiColor = UIColor(quoteColor)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
