import SwiftUI
import SwiftData
import Charts

private struct DayTotal: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodLog.loggedAt) private var allLogs: [FoodLog]

    @State private var windowDays = 7
    @State private var selectedDate = Date()

    private var goals: MacroGoals { (profiles.first ?? UserProfile()).goals }

    private var days: [Date] {
        (0..<windowDays).reversed().map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
    }

    private var series: [DayTotal] {
        let byKey = Dictionary(grouping: allLogs, by: { $0.logDate })
        let fmt = DateFormatter(); fmt.dateFormat = windowDays == 7 ? "dd.MM" : "dd"
        return days.map { day in
            let key = day.dayKey
            let rows = byKey[key] ?? []
            return DayTotal(date: day, label: fmt.string(from: day),
                            calories: rows.reduce(0) { $0 + $1.calories },
                            protein: rows.reduce(0) { $0 + $1.proteinG },
                            carbs: rows.reduce(0) { $0 + $1.carbsG },
                            fat: rows.reduce(0) { $0 + $1.fatG })
        }
    }

    private var loggedDays: [DayTotal] { series.filter { $0.calories > 0 } }
    private var selectedDayLogs: [FoodLog] { allLogs.filter { $0.logDate == selectedDate.dayKey } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.rowRhythm + 4) {
                    Text("Geçmiş").font(Theme.serifTitle()).foregroundStyle(Theme.porcelain)
                    Picker("Aralık", selection: $windowDays) {
                        Text("Son 7 gün").tag(7)
                        Text("Son 30 gün").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.copper)

                    chart

                    HStack(spacing: Theme.rowRhythm) {
                        statColumn("Kayıtlı gün", "\(loggedDays.count)/\(windowDays)")
                        statColumn("Ortalama", loggedDays.isEmpty ? "—" :
                                    Theme.kcal(loggedDays.map(\.calories).reduce(0, +) / Double(loggedDays.count)))
                        statColumn("Hedefte gün", "\(loggedDays.filter { $0.calories <= goals.calorieGoal }.count)")
                    }
                    Hairline()

                    DatePicker("Bir günü aç", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .tint(Theme.copper)
                        .font(Theme.uiBody())

                    if selectedDayLogs.isEmpty {
                        Text("Bu günde kayıt yok.").font(Theme.uiBody()).foregroundStyle(Theme.porcelainDim)
                    } else {
                        let dayTotal = selectedDayLogs.reduce((0.0, 0.0, 0.0, 0.0)) { acc, l in
                            (acc.0 + l.calories, acc.1 + l.proteinG, acc.2 + l.carbsG, acc.3 + l.fatG)
                        }
                        Text(Theme.kcal(dayTotal.0))
                            .font(Theme.measure(24))
                            .foregroundStyle(Theme.porcelain)
                        ForEach(MealType.allCases, id: \.self) { meal in
                            let rows = selectedDayLogs.filter { $0.meal == meal }
                            if !rows.isEmpty {
                                Text(meal.plainLabel).font(Theme.serifBody()).foregroundStyle(Theme.porcelain)
                                ForEach(rows) { log in
                                    MeasureRowStatic(name: log.foodName,
                                                     portion: log.grams > 0 ? Theme.grams(log.grams) : nil,
                                                     valueText: Theme.kcal(log.calories))
                                }
                            }
                        }
                    }
                }
                .padding(Theme.outerMargin)
            }
            .inkBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { day in
                BarMark(x: .value("Gün", day.label), y: .value("Kalori", day.calories), width: .fixed(3))
                    .foregroundStyle(day.calories > goals.calorieGoal ? Theme.nar : Theme.copper)
                    .cornerRadius(1.5)
            }
            RuleMark(y: .value("Hedef", goals.calorieGoal))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Theme.copper.opacity(0.6))
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(Theme.uiCaption(10)).foregroundStyle(Theme.porcelainDim)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.hairlineColor)
                AxisValueLabel().font(Theme.uiCaption(10)).foregroundStyle(Theme.porcelainDim)
            }
        }
        .frame(height: 180)
    }

    private func statColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.uiCaption()).foregroundStyle(Theme.porcelainDim)
            Text(value).font(Theme.measure(17)).foregroundStyle(Theme.porcelain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
