import SwiftUI

/// Standart satır: serif ad + porsiyon cümlesi + sağa dayalı ölçülmüş sayı.
/// Kartın dışında arayüzün geri kalanı bu satır + `Hairline` ile kurulur.
struct MeasureRow<Details: View>: View {
    var name: String
    var portion: String?
    var valueText: String
    @Binding var expanded: Bool
    @ViewBuilder var details: () -> Details

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacingS) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.isEmpty ? "Yeni kalem" : name)
                            .font(Theme.serifBody())
                            .foregroundStyle(Theme.porcelain)
                        if let portion, !portion.isEmpty {
                            Text(portion)
                                .font(Theme.uiCaption())
                                .foregroundStyle(Theme.porcelainDim)
                        }
                    }
                    Spacer()
                    Text(valueText)
                        .font(Theme.measure(17))
                        .foregroundStyle(Theme.porcelain)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.porcelainDim)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, Theme.spacingS)

            if expanded {
                details()
                    .padding(.bottom, Theme.spacingS)
            }
        }
        Hairline()
    }
}

/// Basit, salt-görüntüleme satırı (detay/aç-kapa yok).
struct MeasureRowStatic: View {
    var name: String
    var portion: String?
    var valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingS) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Theme.serifBody()).foregroundStyle(Theme.porcelain)
                    if let portion, !portion.isEmpty {
                        Text(portion).font(Theme.uiCaption()).foregroundStyle(Theme.porcelainDim)
                    }
                }
                Spacer()
                Text(valueText).font(Theme.measure(17)).foregroundStyle(Theme.porcelain)
            }
            .padding(.vertical, Theme.spacingS)
        }
        Hairline()
    }
}
