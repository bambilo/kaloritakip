import SwiftUI

/// Tek koreografi: bakır ölçüm çizgisi fotoğrafın üzerinde bir kez süzülür.
/// Uygulamadaki kendiliğinden animasyon yalnızca burada var.
struct AnalyzingView: View {
    let image: UIImage

    @State private var scanProgress: CGFloat = 0
    @State private var stage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stages = ["Kadraja bakıyorum.", "Referans arıyorum.", "Porsiyonu hesaplıyorum."]

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Theme.inkDeep.opacity(0.5).ignoresSafeArea()

            GeometryReader { proxy in
                Rectangle()
                    .fill(Theme.copper)
                    .frame(height: 1.5)
                    .shadow(color: Theme.copper.opacity(0.7), radius: 8)
                    .position(x: proxy.size.width / 2,
                              y: reduceMotion ? proxy.size.height / 2 : scanProgress * proxy.size.height)
            }

            VStack {
                Spacer()
                Text(stages[stage])
                    .font(Theme.uiBody())
                    .foregroundStyle(Theme.porcelain)
                    .padding(.bottom, 64)
                    .transition(.opacity)
                    .id(stage)
            }
        }
        .onAppear(perform: start)
    }

    private func start() {
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 2.4)) { scanProgress = 1 }
        }
        Task {
            for i in stages.indices {
                await MainActor.run { withAnimation(.easeInOut(duration: 0.2)) { stage = i } }
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
        }
    }
}
