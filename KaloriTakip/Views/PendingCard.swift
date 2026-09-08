import SwiftUI

/// Kartın tek kullanıldığı yer: onayını bekleyen analiz sonucu.
struct PendingCard: View {
    @Binding var pending: PendingAnalysis
    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var showReasoning = false
    @State private var expandedItems: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowRhythm) {
            header

            if !pending.scaleReasoning.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showReasoning.toggle() }
                } label: {
                    Text(pending.scaleReasoning)
                        .font(Theme.serifItalic())
                        .foregroundStyle(Theme.porcelainDim)
                        .lineLimit(showReasoning ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if !pending.referenceObjects.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(pending.referenceObjects) { ref in
                        Text("\(ref.nesne) — \(ref.varsayilanOlcu)")
                            .font(Theme.uiCaption())
                            .foregroundStyle(Theme.porcelainDim)
                    }
                }
            } else {
                Text("Kadrajda referans nesne bulunamadı, tahmin daha kaba olabilir.")
                    .font(Theme.uiCaption())
                    .foregroundStyle(Theme.nar)
            }

            ForEach(pending.warnings, id: \.self) { warning in
                Text(warning).font(Theme.uiCaption()).foregroundStyle(Theme.porcelainDim)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach($pending.items) { $item in
                    ItemRow(item: $item, expanded: expandedBinding(item.id), onDelete: { removeItem(item.id) })
                }
            }

            Picker("Öğün", selection: $pending.mealType) {
                ForEach(MealType.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .tint(Theme.copper)

            HStack(spacing: Theme.spacingS) {
                Button("Güne ekle", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.copper)
                    .disabled(pending.items.isEmpty)
                Button("Kalem ekle") { pending.items.append(.blank()) }
                    .buttonStyle(.bordered)
                Button("Vazgeç", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Theme.outerMargin)
        .background(Theme.inkDeep, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairlineColor, lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.spacingS) {
            if let data = pending.image, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
            Text(Theme.kcal(pending.items.totalCalories))
                .font(Theme.measure(38))
                .foregroundStyle(Theme.porcelain)
        }
    }

    private func expandedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedItems.contains(id) },
            set: { isOn in
                if isOn { expandedItems.insert(id) } else { expandedItems.remove(id) }
            }
        )
    }

    private func removeItem(_ id: UUID) {
        pending.items.removeAll { $0.id == id }
        pending.edited = true
    }
}

private struct ItemRow: View {
    @Binding var item: PendingItem
    @Binding var expanded: Bool
    var onDelete: () -> Void

    private var confidenceValue: Double {
        switch item.confidence {
        case "yuksek": return 3
        case "orta": return 2
        case "dusuk": return 1
        default: return 0
        }
    }

    var body: some View {
        MeasureRow(name: item.foodName, portion: item.portionDesc,
                   valueText: Theme.kcal(item.calories), expanded: $expanded) {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                TextField("Yemek adı", text: $item.foodName)
                    .font(Theme.uiBody())
                    .textFieldStyle(.roundedBorder)
                if confidenceValue > 0 {
                    CalibratedScale(style: .compact, label: "Güven",
                                     value: confidenceValue, goal: 3,
                                     accessibilityValueText: "\(item.confidence ?? "") güven")
                }
                HStack {
                    field("Gramaj (g)", Binding(get: { item.grams }, set: { item.updateGrams($0) }))
                    field("Kalori (kcal)", Binding(get: { item.calories }, set: { item.calories = $0; item.manualKcal = true }))
                }
                HStack {
                    field("Protein", $item.proteinG)
                    field("Karb.", $item.carbsG)
                    field("Yağ", $item.fatG)
                }
                Button("Kalemi çıkar", role: .destructive, action: onDelete)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.uiCaption()).foregroundStyle(Theme.porcelainDim)
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}
