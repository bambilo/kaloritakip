import Foundation
import SwiftData

@Model
final class FoodLog {
    var id: UUID = UUID()
    var logDate: String = ""          // 'YYYY-MM-DD' -- gun bazli filtre
    var loggedAt: Date = Date()
    var mealType: String = MealType.atistirmalik.rawValue
    var foodName: String = ""
    var portionDesc: String?
    var grams: Double = 0
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var source: String = "manual"     // ai | manual | favorite
    var wasEdited: Bool = false
    var aiModel: String?
    var aiConfidence: String?
    var referenceObjectsJSON: String?
    var scaleReasoning: String?
    @Attribute(.externalStorage) var thumbnail: Data?

    var meal: MealType {
        get { MealType(rawValue: mealType) ?? .atistirmalik }
        set { mealType = newValue.rawValue }
    }

    init(logDate: String, loggedAt: Date, mealType: MealType, foodName: String,
         portionDesc: String? = nil, grams: Double, calories: Double,
         proteinG: Double, carbsG: Double, fatG: Double, source: String,
         wasEdited: Bool = false, aiModel: String? = nil, aiConfidence: String? = nil,
         referenceObjectsJSON: String? = nil, scaleReasoning: String? = nil,
         thumbnail: Data? = nil) {
        self.logDate = logDate
        self.loggedAt = loggedAt
        self.mealType = mealType.rawValue
        self.foodName = foodName
        self.portionDesc = portionDesc
        self.grams = grams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.source = source
        self.wasEdited = wasEdited
        self.aiModel = aiModel
        self.aiConfidence = aiConfidence
        self.referenceObjectsJSON = referenceObjectsJSON
        self.scaleReasoning = scaleReasoning
        self.thumbnail = thumbnail
    }
}

@Model
final class Favorite {
    var id: UUID = UUID()
    var foodName: String = ""
    var grams: Double = 0
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var useCount: Int = 1
    var lastUsedAt: Date = Date()

    init(foodName: String, grams: Double, calories: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.foodName = foodName
        self.grams = grams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.useCount = 1
        self.lastUsedAt = Date()
    }
}

/// Tek kullanicilik profil: uygulamada tek satir tutulur (cihaz basina bir kisi).
@Model
final class UserProfile {
    var id: UUID = UUID()
    var sex: String = Sex.kadin.rawValue
    var age: Int = 30
    var heightCm: Double = 170
    var weightKg: Double = 70
    var activityLevel: String = ActivityLevel.hafif.rawValue
    var goalType: String = GoalType.koru.rawValue
    var calorieGoal: Double?
    var proteinGoalG: Double?
    var carbsGoalG: Double?
    var fatGoalG: Double?
    var goalsAreManual: Bool = false
    var updatedAt: Date = Date()

    init() {}

    var goals: MacroGoals {
        if let c = calorieGoal, let p = proteinGoalG, let cb = carbsGoalG, let f = fatGoalG {
            return MacroGoals(calorieGoal: c, proteinGoalG: p, carbsGoalG: cb, fatGoalG: f)
        }
        return MacroGoals(calorieGoal: 2000, proteinGoalG: 100, carbsGoalG: 250, fatGoalG: 65)
    }

    var hasCustomGoals: Bool { calorieGoal != nil }
}
