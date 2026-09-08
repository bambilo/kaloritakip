import Foundation

/// "Analiz et" sonrasi kullaniciya gosterilen, duzenlenebilir tek bir kalem.
/// ai.py'deki _new_item() sozlugunun Swift karsiligi.
struct PendingItem: Identifiable {
    let id = UUID()
    var foodName: String
    var portionDesc: String?
    var grams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var confidence: String?
    var manualKcal: Bool = false   // kalori elle yazildiysa oranlama durur

    static func blank() -> PendingItem {
        PendingItem(foodName: "", grams: 100, calories: 0, proteinG: 0, carbsG: 0, fatG: 0, manualKcal: true)
    }

    static func from(_ item: FoodItem) -> PendingItem {
        PendingItem(foodName: item.ad, portionDesc: item.porsiyonTarifi, grams: item.gram,
                    calories: item.kalori, proteinG: item.proteinG, carbsG: item.karbonhidratG,
                    fatG: item.yagG, confidence: item.guven)
    }

    /// Gramaj degisince kalori/makrolari orantili gunceller (manuel kalori yazilmadiysa).
    mutating func updateGrams(_ newGrams: Double) {
        if manualKcal {
            grams = newGrams
        } else {
            let scaled = Nutrition.scale(grams: grams, calories: calories, protein: proteinG,
                                         carbs: carbsG, fat: fatG, toNewGrams: newGrams)
            grams = newGrams
            calories = scaled.calories
            proteinG = scaled.protein
            carbsG = scaled.carbs
            fatG = scaled.fat
        }
    }
}

struct PendingAnalysis {
    var items: [PendingItem]
    var referenceObjects: [ReferenceObject]
    var scaleReasoning: String
    var warnings: [String]
    var model: String
    var image: Data?          // 320px onizleme (log_images karsiligi)
    var mealType: MealType
    var edited: Bool = false
}

extension Array where Element == PendingItem {
    var totalCalories: Double { reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { reduce(0) { $0 + $1.fatG } }
}
