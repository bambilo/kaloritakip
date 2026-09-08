import SwiftUI
import UIKit

/// "Mürekkep & Bakır": İznik çinisinin kobaltı, bakır sahanın patinası, porselen tabağın kırık beyazı.
enum Theme {
    // MARK: Renk

    static let ink = Color(red: 0x12/255, green: 0x20/255, blue: 0x3A/255)
    static let inkDeep = Color(red: 0x0C/255, green: 0x17/255, blue: 0x29/255)
    static let porcelain = Color(red: 0xEF/255, green: 0xED/255, blue: 0xE6/255)
    static let porcelainDim = Color(red: 0x8E/255, green: 0x9A/255, blue: 0xAB/255)
    static let copper = Color(red: 0xB8/255, green: 0x73/255, blue: 0x33/255)
    static let cini = Color(red: 0x2F/255, green: 0x8F/255, blue: 0x87/255)
    static let tombak = Color(red: 0xE0/255, green: 0xB7/255, blue: 0x7A/255)
    static let nar = Color(red: 0x9E/255, green: 0x2A/255, blue: 0x2B/255)

    static let hairlineColor = porcelainDim.opacity(0.25)

    // MARK: Boşluk

    static let outerMargin: CGFloat = 24
    static let rowRhythm: CGFloat = 16
    static let spacingXS: CGFloat = 6
    static let spacingS: CGFloat = 10

    // MARK: Tipografi (majör üçlü ~1.25: 12 · 15 · 19 · 24 · 30 · 38 · 48)

    /// Yemek adları ve ekran başlıkları — New York serif, cümle düzeninde.
    static func serifTitle(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static func serifBody(_ size: CGFloat = 19) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func serifItalic(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .serif).italic()
    }

    /// Bütün işlevsel metin: butonlar, açıklamalar, form etiketleri.
    static func uiBody(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func uiCaption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func uiLabel(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Yalnızca ölçülmüş sayılar (kcal, gram) — geniş genişlik + tabular rakam.
    static func measure(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .medium, design: .rounded).width(.expanded).monospacedDigit()
    }

    // MARK: Sayı biçimleme (tr_TR)

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func kcal(_ value: Double) -> String {
        let n = numberFormatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
        return "\(n) kcal"
    }

    static func grams(_ value: Double) -> String {
        let n = numberFormatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
        return "\(n) g"
    }

    static func number(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
    }

    // MARK: Haptik

    enum Haptic {
        static func light() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        static func medium() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        static func success() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// Kartın dışında her yerde kullanılan tek ayırıcı: ince, sessiz bir çizgi.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairlineColor)
            .frame(height: 1 / UIScreen.main.scale)
    }
}

extension View {
    /// Ekranların ortak zemini: kobalt mürekkep, koyu tema sabit.
    func inkBackground() -> some View {
        self.background(Theme.ink.ignoresSafeArea())
    }
}
