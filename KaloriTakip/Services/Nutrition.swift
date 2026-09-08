import Foundation

enum MealType: String, CaseIterable, Codable {
    case kahvalti, ogle, aksam, atistirmalik

    var label: String {
        switch self {
        case .kahvalti: return "🍳 Kahvaltı"
        case .ogle: return "🥗 Öğle"
        case .aksam: return "🍽️ Akşam"
        case .atistirmalik: return "🍎 Atıştırmalık"
        }
    }

    static func suggested(for date: Date = Date()) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<10: return .kahvalti
        case 10..<15: return .ogle
        case 15..<21: return .aksam
        default: return .atistirmalik
        }
    }
}

enum Sex: String, CaseIterable, Codable {
    case kadin, erkek
    var label: String { self == .erkek ? "Erkek" : "Kadın" }
}

enum ActivityLevel: String, CaseIterable, Codable {
    case sedanter, hafif, orta, aktif, cokAktif = "cok_aktif"

    var factor: Double {
        switch self {
        case .sedanter: return 1.2
        case .hafif: return 1.375
        case .orta: return 1.55
        case .aktif: return 1.725
        case .cokAktif: return 1.9
        }
    }

    var label: String {
        switch self {
        case .sedanter: return "Sedanter (masa başı, spor yok)"
        case .hafif: return "Hafif aktif (haftada 1-3 gün spor)"
        case .orta: return "Orta aktif (haftada 3-5 gün spor)"
        case .aktif: return "Çok aktif (haftada 6-7 gün spor)"
        case .cokAktif: return "Ekstra aktif (ağır iş / günde 2 antrenman)"
        }
    }
}

enum GoalType: String, CaseIterable, Codable {
    case kiloVer = "kilo_ver", koru, kiloAl = "kilo_al"

    var factor: Double {
        switch self {
        case .kiloVer: return 0.85
        case .koru: return 1.0
        case .kiloAl: return 1.15
        }
    }

    var label: String {
        switch self {
        case .kiloVer: return "Kilo ver (-%15 kalori)"
        case .koru: return "Kiloyu koru"
        case .kiloAl: return "Kilo al (+%15 kalori)"
        }
    }
}

struct MacroGoals {
    var calorieGoal: Double
    var proteinGoalG: Double
    var carbsGoalG: Double
    var fatGoalG: Double
}

enum Nutrition {
    /// Mifflin-St Jeor bazal metabolizma hizi (kcal/gun).
    static func bmr(sex: Sex, age: Int, heightCm: Double, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .erkek ? base + 5 : base - 161
    }

    static func tdee(sex: Sex, age: Int, heightCm: Double, weightKg: Double, activity: ActivityLevel) -> Double {
        bmr(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg) * activity.factor
    }

    /// Kalori hedefi 1200 kcal altina dusurulmez. Protein 1.6 g/kg, yag kalorinin
    /// %25'i, kalani karbonhidrat.
    static func calculateGoals(sex: Sex, age: Int, heightCm: Double, weightKg: Double,
                                activity: ActivityLevel, goal: GoalType) -> MacroGoals {
        let calories = max(1200, tdee(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, activity: activity) * goal.factor)
        let proteinG = (1.6 * weightKg).rounded()
        let fatG = (calories * 0.25 / 9).rounded()
        let carbsKcal = calories - (proteinG * 4 + fatG * 9)
        let carbsG = max(0, (carbsKcal / 4).rounded())
        return MacroGoals(calorieGoal: calories.rounded(), proteinGoalG: proteinG, carbsGoalG: carbsG, fatGoalG: fatG)
    }

    /// Gramaj degisince kalori ve makrolari 100g bazina normalize edip yeniden olcekler.
    static func scale(grams: Double, calories: Double, protein: Double, carbs: Double, fat: Double,
                       toNewGrams newGrams: Double) -> (calories: Double, protein: Double, carbs: Double, fat: Double) {
        guard grams > 0, newGrams >= 0 else { return (calories, protein, carbs, fat) }
        let ratio = newGrams / grams
        func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        return (round1(calories * ratio), round1(protein * ratio), round1(carbs * ratio), round1(fat * ratio))
    }
}

extension Date {
    /// Gunun 'YYYY-MM-DD' anahtari, cihazin yerel takviminde.
    var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        return f.string(from: self)
    }
}
