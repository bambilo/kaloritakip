import SwiftUI

/// Ekle ekranının dairesel "tabak" çekim kontrolü.
struct PlateButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: {
            Theme.Haptic.medium()
            action()
        }) {
            EmptyView()
        }
        .buttonStyle(PlateButtonStyle())
        .frame(width: 108, height: 108)
    }
}

private struct PlateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let tint = configuration.isPressed ? Theme.tombak : Theme.copper
        return ZStack {
            Circle()
                .fill(Theme.inkDeep)
                .frame(width: 108, height: 108)
            Circle()
                .strokeBorder(tint, lineWidth: 1.25)
                .frame(width: 108, height: 108)
            Circle()
                .strokeBorder(Theme.hairlineColor, lineWidth: 1)
                .frame(width: 84, height: 84)
            Image(systemName: "camera")
                .font(.system(size: 26, weight: .thin))
                .foregroundStyle(tint)
        }
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
