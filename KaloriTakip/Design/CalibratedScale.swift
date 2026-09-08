import SwiftUI

/// Ürünün kendi fikrini taşıyan tek gösterge dili: bir cetvel, bir çentik, bir iğne.
/// `full` gün kalorisi için, `compact` makro/güven/geçmiş için kullanılır.
struct CalibratedScale: View {
    enum Style { case full, compact }

    var style: Style
    var label: String
    var value: Double
    var goal: Double
    var accessibilityValueText: String

    private var isOverGoal: Bool { value > goal }
    private var indicatorColor: Color { isOverGoal ? Theme.nar : Theme.copper }

    private var scaleMax: Double {
        let m = max(goal * 1.25, value * 1.05)
        let step: Double = style == .full ? 500 : 50
        return (ceil(m / step) * step).isFinite ? max(ceil(m / step) * step, step) : step
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            if style == .full {
                fullRuler
            } else {
                compactRuler
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValueText)
    }

    // MARK: Full — gün kalorisi

    private var fullRuler: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let goalX = width * CGFloat(goal / scaleMax)
            let valueX = min(width, width * CGFloat(value / scaleMax))
            let minorStep = scaleMax / 20 // her adımda ince çentik (100 kcal aralıklarına yakın)
            let majorStep: Double = 500

            ZStack(alignment: .leading) {
                // Cetvel çizgisi
                Rectangle().fill(Theme.hairlineColor).frame(height: 1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: 18)

                // Çentikler
                ForEach(Array(stride(from: 0.0, through: scaleMax, by: minorStep)), id: \.self) { tick in
                    let isMajor = tick.truncatingRemainder(dividingBy: majorStep) == 0
                    Rectangle()
                        .fill(Theme.hairlineColor)
                        .frame(width: 1, height: isMajor ? 12 : 6)
                        .offset(x: width * CGFloat(tick / scaleMax), y: 12 - (isMajor ? 6 : 3))
                    if isMajor {
                        Text(Theme.number(tick))
                            .font(Theme.uiCaption(11))
                            .foregroundStyle(Theme.porcelainDim)
                            .fixedSize()
                            .offset(x: max(0, min(width - 24, width * CGFloat(tick / scaleMax) - 10)), y: 26)
                    }
                }

                // Dolu bant (0'dan mevcut değere)
                Rectangle()
                    .fill(indicatorColor.opacity(0.9))
                    .frame(width: valueX, height: 2)
                    .offset(y: 18)

                // Hedef çentiği
                Rectangle()
                    .fill(Theme.copper)
                    .frame(width: 2, height: 20)
                    .offset(x: goalX, y: 8)

                // İğne
                Triangle()
                    .fill(indicatorColor)
                    .frame(width: 10, height: 8)
                    .offset(x: valueX - 5, y: -2)
            }
        }
        .frame(height: 56)
    }

    // MARK: Compact — makro / güven / geçmiş

    private var compactRuler: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.uiCaption())
                .foregroundStyle(Theme.porcelainDim)
            GeometryReader { proxy in
                let width = proxy.size.width
                let goalX = width * CGFloat(min(goal / scaleMax, 1))
                let valueX = min(width, width * CGFloat(value / scaleMax))
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.hairlineColor).frame(height: 3)
                    Rectangle().fill(indicatorColor).frame(width: valueX, height: 3)
                    Rectangle().fill(Theme.porcelainDim).frame(width: 1.5, height: 9).offset(x: goalX, y: -3)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
