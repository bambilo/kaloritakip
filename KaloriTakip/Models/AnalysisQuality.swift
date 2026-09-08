import Foundation

/// Kullanıcıya model adı hiç gösterilmez; yalnızca hız/dikkat tercihi sunulur.
enum AnalysisQuality: String, CaseIterable {
    case hizli, dengeli, titiz

    var model: GeminiModel {
        switch self {
        case .hizli: return .flashLite
        case .dengeli: return .flash36
        case .titiz: return .flash38
        }
    }

    var label: String {
        switch self {
        case .hizli: return "Hızlı"
        case .dengeli: return "Dengeli"
        case .titiz: return "Titiz"
        }
    }

    var explanation: String {
        switch self {
        case .hizli: return "Birkaç saniyede sonuçlanır. Günlük yemekler için yeterli."
        case .dengeli: return "Biraz daha bekletir, karışık tabaklarda daha dikkatli ölçer."
        case .titiz: return "En dikkatli ölçüm. Kalabalık sofralar için."
        }
    }
}
