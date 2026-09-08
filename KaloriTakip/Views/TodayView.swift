import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodLog.loggedAt) private var allLogs: [FoodLog]

    private var todayKey: String { Date().dayKey }
    private var logs: [FoodLog] { allLogs.filter { $0.logDate == todayKey } }
    private var goals: MacroGoals { (profiles.first ?? UserProfile()).goals }

    private var totals: (cal: Double, p: Double, c: Double, f: Double) {
        logs.reduce((0.0, 0.0, 0.0, 0.0)) { acc, log in
            (acc.0 + log.calories, acc.1 + log.proteinG, acc.2 + log.carbsG, acc.3 + log.fatG)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Date().formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "tr_TR"))))
                        .font(Theme.serifTitle())
                        .foregroundStyle(Theme.porcelain)
                    progressSection
                        .padding(.vertical, Theme.spacingS)
                    if logs.isEmpty {
                        Text("Bugün henüz bir şey eklemedin. Bir fotoğrafla başla.")
                            .font(Theme.uiBody())
                            .foregroundStyle(Theme.porcelainDim)
                            .padding(.top, 12)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !logs.isEmpty {
                    mealSections
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .inkBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: Theme.rowRhythm) {
            CalibratedScale(style: .full, label: "Bugünkü kalori",
                             value: totals.cal, goal: goals.calorieGoal,
                             accessibilityValueText: "\(Theme.number(totals.cal)) kalori, hedef \(Theme.number(goals.calorieGoal))")
            HStack(spacing: Theme.rowRhythm) {
                CalibratedScale(style: .compact, label: "protein \(Theme.number(totals.p))/\(Theme.number(goals.proteinGoalG))g",
                                 value: totals.p, goal: goals.proteinGoalG,
                                 accessibilityValueText: "protein \(Theme.number(totals.p)) gram, hedef \(Theme.number(goals.proteinGoalG))")
                CalibratedScale(style: .compact, label: "karb. \(Theme.number(totals.c))/\(Theme.number(goals.carbsGoalG))g",
                                 value: totals.c, goal: goals.carbsGoalG,
                                 accessibilityValueText: "karbonhidrat \(Theme.number(totals.c)) gram, hedef \(Theme.number(goals.carbsGoalG))")
                CalibratedScale(style: .compact, label: "yağ \(Theme.number(totals.f))/\(Theme.number(goals.fatGoalG))g",
                                 value: totals.f, goal: goals.fatGoalG,
                                 accessibilityValueText: "yağ \(Theme.number(totals.f)) gram, hedef \(Theme.number(goals.fatGoalG))")
            }
        }
    }

    @ViewBuilder
    private var mealSections: some View {
        ForEach(MealType.allCases, id: \.self) { meal in
            let mealLogs = logs.filter { $0.meal == meal }
            if !mealLogs.isEmpty {
                Section {
                    ForEach(mealLogs) { log in
                        LogRow(log: log)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(meal.plainLabel)
                        .font(Theme.serifBody())
                        .foregroundStyle(Theme.porcelain)
                        .textCase(nil)
                }
            }
        }
    }
}

struct LogRow: View {
    @Bindable var log: FoodLog
    @State private var expanded = false

    var body: some View {
        MeasureRow(name: log.foodName,
                   portion: log.grams > 0 ? Theme.grams(log.grams) : nil,
                   valueText: Theme.kcal(log.calories), expanded: $expanded) {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                Text("Protein \(Theme.grams(log.proteinG)) · Karb. \(Theme.grams(log.carbsG)) · Yağ \(Theme.grams(log.fatG))")
                    .font(Theme.uiCaption()).foregroundStyle(Theme.porcelainDim)
                if let reasoning = log.scaleReasoning, !reasoning.isEmpty {
                    Text(reasoning).font(Theme.serifItalic(13)).foregroundStyle(Theme.porcelainDim)
                }
                if let data = log.thumbnail, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFit()
                        .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Stepper("Gramaj: \(Theme.grams(log.grams))", value: $log.grams, in: 0...2000, step: 10)
                    .tint(Theme.copper)
                    .onChange(of: log.grams) { old, new in
                        let scaled = Nutrition.scale(grams: old, calories: log.calories, protein: log.proteinG,
                                                     carbs: log.carbsG, fat: log.fatG, toNewGrams: new)
                        log.calories = scaled.calories
                        log.proteinG = scaled.protein
                        log.carbsG = scaled.carbs
                        log.fatG = scaled.fat
                        log.wasEdited = true
                    }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Sil", role: .destructive) {
                log.modelContext?.delete(log)
            }
            .tint(Theme.nar)
        }
    }
}

extension MealType {
    /// Ekran başlıklarında etiket yok, sade cümle düzeni.
    var plainLabel: String {
        switch self {
        case .kahvalti: return "Kahvaltı"
        case .ogle: return "Öğle"
        case .aksam: return "Akşam"
        case .atistirmalik: return "Atıştırmalık"
        }
    }
}
