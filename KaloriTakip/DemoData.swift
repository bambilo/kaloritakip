import Foundation
import SwiftData

#if DEBUG
/// `-seedDemoData` başlatma argümanıyla örnek bir gün verisi ekler (yalnızca görsel kontrol için).
enum DemoData {
    static func seed(into context: ModelContext) {
        let profile = UserProfile()
        context.insert(profile)

        let today = Date().dayKey
        let entries: [(MealType, String, String, Double, Double, Double, Double, Double)] = [
            (.kahvalti, "Menemen", "1 tabak", 220, 620, 24, 18, 48),
            (.ogle, "Bulgur pilavı", "1 kepçe, 180 g", 180, 290, 7, 58, 4),
            (.ogle, "Izgara tavuk", "1 avuç içi, 120 g", 120, 198, 32, 0, 7),
            (.aksam, "Mercimek çorbası", "1 kâse, 300 ml", 300, 180, 11, 26, 4),
        ]
        for (meal, name, portion, grams, cal, protein, carbs, fat) in entries {
            let log = FoodLog(logDate: today, loggedAt: Date(), mealType: meal, foodName: name,
                              portionDesc: portion, grams: grams, calories: cal,
                              proteinG: protein, carbsG: carbs, fatG: fat, source: "manual")
            context.insert(log)
        }

        context.insert(Favorite(foodName: "Yulaf ezmesi", grams: 60, calories: 230, proteinG: 8, carbsG: 39, fatG: 5))
        context.insert(Favorite(foodName: "Ayran", grams: 200, calories: 70, proteinG: 4, carbsG: 6, fatG: 3))
    }
}
#endif
