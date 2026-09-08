import SwiftUI
import SwiftData

struct AddView: View {
    @Environment(\.modelContext) private var context
    @Query private var favorites: [Favorite]
    @AppStorage("analysisQuality") private var qualityRaw = AnalysisQuality.hizli.rawValue

    @State private var showCameraPicker = false
    @State private var showLibraryPicker = false
    @State private var note = ""
    @State private var analyzingImage: UIImage?
    @State private var pending: PendingAnalysis?
    @State private var errorMessage: String?
    @State private var addFavoriteOnSave = false

    private var quality: AnalysisQuality { AnalysisQuality(rawValue: qualityRaw) ?? .hizli }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.rowRhythm + 4) {
                    Text("Ekle").font(Theme.serifTitle()).foregroundStyle(Theme.porcelain)
                    if let pending {
                        PendingCard(pending: binding(for: pending), onSave: save, onCancel: { self.pending = nil })
                    } else {
                        captureSection
                        Hairline()
                        favoritesSection
                        manualAddSection
                    }
                }
                .padding(Theme.outerMargin)
            }
            .inkBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Hata", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .fullScreenCover(item: $analyzingImage.asIdentifiableImage) { wrapped in
                AnalyzingView(image: wrapped.image)
            }
            .sheet(isPresented: $showCameraPicker) {
                ImagePicker(source: .camera) { image in analyze(image) }
            }
            .sheet(isPresented: $showLibraryPicker) {
                ImagePicker(source: .library) { image in analyze(image) }
            }
        }
    }

    private var captureSection: some View {
        VStack(spacing: Theme.spacingS) {
            PlateButton { showCameraPicker = true }
            Text("Tabağın yanına bir bardak ya da çatal koy.\nÖlçüyü ondan alıyorum.")
                .font(Theme.uiCaption())
                .foregroundStyle(Theme.porcelainDim)
                .multilineTextAlignment(.center)
            Button("Galeriden seç") { showLibraryPicker = true }
                .font(Theme.uiLabel())
                .foregroundStyle(Theme.copper)
                .padding(.top, Theme.spacingS)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.rowRhythm)
    }

    private var favoritesSection: some View {
        Group {
            if !favorites.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sık yediklerin").font(Theme.serifBody()).foregroundStyle(Theme.porcelain)
                        .padding(.bottom, Theme.spacingXS)
                    ForEach(favorites.sorted(by: { $0.useCount > $1.useCount }).prefix(8)) { fav in
                        Button { addFavoriteToToday(fav) } label: {
                            MeasureRowStatic(name: fav.foodName, portion: nil, valueText: Theme.kcal(fav.calories))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @State private var manualName = ""
    @State private var manualGrams = 100.0
    @State private var manualCalories = 0.0
    @State private var manualProtein = 0.0
    @State private var manualCarbs = 0.0
    @State private var manualFat = 0.0
    @State private var manualMeal = MealType.suggested()
    @State private var manualAsFavorite = false

    private var manualAddSection: some View {
        DisclosureGroup("Elle ekle") {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                TextField("Yemek adı", text: $manualName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    labeledField("Gramaj", $manualGrams)
                    labeledField("Kalori", $manualCalories)
                }
                HStack {
                    labeledField("Protein", $manualProtein)
                    labeledField("Karb.", $manualCarbs)
                    labeledField("Yağ", $manualFat)
                }
                Picker("Öğün", selection: $manualMeal) {
                    ForEach(MealType.allCases, id: \.self) { Text($0.plainLabel).tag($0) }
                }
                .tint(Theme.copper)
                Toggle("Favorilere ekle", isOn: $manualAsFavorite)
                    .tint(Theme.copper)
                Button("Güne ekle") { saveManual() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.copper)
                    .frame(maxWidth: .infinity)
                    .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty || manualCalories <= 0)
            }
            .padding(.top, Theme.spacingS)
        }
        .tint(Theme.copper)
        .font(Theme.uiLabel())
    }

    private func labeledField(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.uiCaption()).foregroundStyle(Theme.porcelainDim)
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: Actions

    private func analyze(_ image: UIImage) {
        analyzingImage = image
        Task {
            do {
                let analysis = try await GeminiService.analyze(image: image, model: quality.model, note: note)
                await MainActor.run {
                    analyzingImage = nil
                    if !analysis.isFood {
                        errorMessage = "Fotoğrafta yiyecek bulunamadı. " + analysis.uyarilar.joined(separator: " ")
                        return
                    }
                    pending = PendingAnalysis(
                        items: analysis.items.map(PendingItem.from),
                        referenceObjects: analysis.referenceObjects,
                        scaleReasoning: analysis.scaleReasoning,
                        warnings: analysis.uyarilar + (analysis.fotoIpucu.isEmpty ? [] : [analysis.fotoIpucu]),
                        model: quality.model.rawValue,
                        image: ImageProcessing.thumbnail(image),
                        mealType: MealType.suggested()
                    )
                }
            } catch {
                await MainActor.run {
                    analyzingImage = nil
                    errorMessage = (error as? AIError)?.errorDescription ?? "Bağlantı kurulamadı. Tekrar dene."
                }
            }
        }
    }

    private func binding(for value: PendingAnalysis) -> Binding<PendingAnalysis> {
        Binding(get: { pending ?? value }, set: { pending = $0 })
    }

    private func save() {
        guard let pending else { return }
        let dayKey = Date().dayKey
        for item in pending.items {
            let log = FoodLog(logDate: dayKey, loggedAt: Date(), mealType: pending.mealType,
                              foodName: item.foodName, portionDesc: item.portionDesc, grams: item.grams,
                              calories: item.calories, proteinG: item.proteinG, carbsG: item.carbsG,
                              fatG: item.fatG, source: "ai", wasEdited: pending.edited,
                              aiModel: pending.model, aiConfidence: item.confidence,
                              referenceObjectsJSON: nil, scaleReasoning: pending.scaleReasoning,
                              thumbnail: pending.image)
            context.insert(log)
            if addFavoriteOnSave {
                upsertFavorite(name: item.foodName, grams: item.grams, calories: item.calories,
                              protein: item.proteinG, carbs: item.carbsG, fat: item.fatG)
            }
        }
        self.pending = nil
        note = ""
    }

    private func saveManual() {
        let log = FoodLog(logDate: Date().dayKey, loggedAt: Date(), mealType: manualMeal,
                          foodName: manualName, grams: manualGrams, calories: manualCalories,
                          proteinG: manualProtein, carbsG: manualCarbs, fatG: manualFat, source: "manual")
        context.insert(log)
        if manualAsFavorite {
            upsertFavorite(name: manualName, grams: manualGrams, calories: manualCalories,
                          protein: manualProtein, carbs: manualCarbs, fat: manualFat)
        }
        manualName = ""; manualGrams = 100; manualCalories = 0; manualProtein = 0; manualCarbs = 0; manualFat = 0
        manualAsFavorite = false
    }

    private func addFavoriteToToday(_ fav: Favorite) {
        let log = FoodLog(logDate: Date().dayKey, loggedAt: Date(), mealType: MealType.suggested(),
                          foodName: fav.foodName, grams: fav.grams, calories: fav.calories,
                          proteinG: fav.proteinG, carbsG: fav.carbsG, fatG: fav.fatG, source: "favorite")
        context.insert(log)
        fav.useCount += 1
        fav.lastUsedAt = Date()
    }

    private func upsertFavorite(name: String, grams: Double, calories: Double, protein: Double, carbs: Double, fat: Double) {
        if let existing = favorites.first(where: { $0.foodName == name }) {
            existing.grams = grams; existing.calories = calories
            existing.proteinG = protein; existing.carbsG = carbs; existing.fatG = fat
            existing.useCount += 1; existing.lastUsedAt = Date()
        } else {
            context.insert(Favorite(foodName: name, grams: grams, calories: calories, proteinG: protein, carbsG: carbs, fatG: fat))
        }
    }
}

/// `fullScreenCover(item:)` icin UIImage'i Identifiable yapan sarmalayici.
private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private extension Binding where Value == UIImage? {
    var asIdentifiableImage: Binding<IdentifiableImage?> {
        Binding<IdentifiableImage?>(
            get: { wrappedValue.map(IdentifiableImage.init) },
            set: { newValue in wrappedValue = newValue?.image }
        )
    }
}
