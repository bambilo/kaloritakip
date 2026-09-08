import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodLog.loggedAt) private var allLogs: [FoodLog]
    @AppStorage("analysisQuality") private var qualityRaw = AnalysisQuality.hizli.rawValue

    @State private var sex: Sex = .kadin
    @State private var age = 30
    @State private var heightCm = 170.0
    @State private var weightKg = 70.0
    @State private var activity: ActivityLevel = .hafif
    @State private var goal: GoalType = .koru
    @State private var manual = false
    @State private var manualCalories = 2000.0
    @State private var manualProtein = 100.0
    @State private var manualCarbs = 250.0
    @State private var manualFat = 65.0
    @State private var saved = false

    private var quality: AnalysisQuality { AnalysisQuality(rawValue: qualityRaw) ?? .hizli }

    private var profile: UserProfile {
        if let p = profiles.first { return p }
        let p = UserProfile()
        context.insert(p)
        return p
    }

    private var computedGoals: MacroGoals {
        Nutrition.calculateGoals(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, activity: activity, goal: goal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hedefler") {
                    Picker("Cinsiyet", selection: $sex) {
                        ForEach(Sex.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Stepper("Yaş: \(age)", value: $age, in: 10...100)
                    HStack {
                        Text("Boy"); Spacer()
                        TextField("cm", value: $heightCm, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text("cm").foregroundStyle(Theme.porcelainDim)
                    }
                    HStack {
                        Text("Kilo"); Spacer()
                        TextField("kg", value: $weightKg, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text("kg").foregroundStyle(Theme.porcelainDim)
                    }
                    Picker("Aktivite düzeyi", selection: $activity) {
                        ForEach(ActivityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Hedef", selection: $goal) {
                        ForEach(GoalType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Hedefleri elle gireceğim", isOn: $manual)
                    if manual {
                        HStack { Text("Kalori"); Spacer(); TextField("kcal", value: $manualCalories, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Protein"); Spacer(); TextField("g", value: $manualProtein, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Karbonhidrat"); Spacer(); TextField("g", value: $manualCarbs, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Yağ"); Spacer(); TextField("g", value: $manualFat, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    } else {
                        let g = computedGoals
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BMR ≈ \(Theme.kcal(Nutrition.bmr(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg)))")
                            Text("Hedef: \(Theme.kcal(g.calorieGoal)) · Protein \(Theme.grams(g.proteinGoalG)) / Karb. \(Theme.grams(g.carbsGoalG)) / Yağ \(Theme.grams(g.fatGoalG))")
                        }
                        .font(Theme.uiCaption()).foregroundStyle(Theme.porcelainDim)
                    }
                    Button("Kaydet") { save() }
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Theme.inkDeep)

                Section {
                    Picker("Analiz kalitesi", selection: $qualityRaw) {
                        ForEach(AnalysisQuality.allCases, id: \.self) { q in
                            Text(q.label).tag(q.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(quality.explanation)
                        .font(Theme.uiCaption())
                        .foregroundStyle(Theme.porcelainDim)
                } header: {
                    Text("Analiz")
                }
                .listRowBackground(Theme.inkDeep)

                Section {
                    ShareLink(item: csvExport()) {
                        Label("Kayıtlarımı paylaş", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Veriler")
                }
                .listRowBackground(Theme.inkDeep)
            }
            .tint(Theme.copper)
            .scrollContentBackground(.hidden)
            .inkBackground()
            .navigationTitle("Ayarlar")
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .onAppear(perform: loadFromProfile)
            .alert("Kaydedildi", isPresented: $saved) { Button("Tamam", role: .cancel) {} }
        }
    }

    private func loadFromProfile() {
        let p = profile
        sex = Sex(rawValue: p.sex) ?? .kadin
        age = p.age
        heightCm = p.heightCm
        weightKg = p.weightKg
        activity = ActivityLevel(rawValue: p.activityLevel) ?? .hafif
        goal = GoalType(rawValue: p.goalType) ?? .koru
        manual = p.goalsAreManual
        if let c = p.calorieGoal { manualCalories = c }
        if let pr = p.proteinGoalG { manualProtein = pr }
        if let cb = p.carbsGoalG { manualCarbs = cb }
        if let f = p.fatGoalG { manualFat = f }
    }

    private func save() {
        let p = profile
        p.sex = sex.rawValue
        p.age = age
        p.heightCm = heightCm
        p.weightKg = weightKg
        p.activityLevel = activity.rawValue
        p.goalType = goal.rawValue
        p.goalsAreManual = manual
        if manual {
            p.calorieGoal = manualCalories
            p.proteinGoalG = manualProtein
            p.carbsGoalG = manualCarbs
            p.fatGoalG = manualFat
        } else {
            let g = computedGoals
            p.calorieGoal = g.calorieGoal
            p.proteinGoalG = g.proteinGoalG
            p.carbsGoalG = g.carbsGoalG
            p.fatGoalG = g.fatGoalG
        }
        p.updatedAt = Date()
        saved = true
    }

    private func csvExport() -> String {
        var lines = ["tarih,ogun,yemek,gram,kalori,protein_g,karbonhidrat_g,yag_g,kaynak"]
        for log in allLogs.sorted(by: { $0.logDate > $1.logDate }) {
            let fields = [log.logDate, log.mealType, log.foodName, String(log.grams),
                         String(log.calories), String(log.proteinG), String(log.carbsG),
                         String(log.fatG), log.source]
            lines.append(fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "'"))\"" }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
