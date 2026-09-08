import Foundation
import UIKit

// MARK: - Cikti modelleri (ai.py Analysis/FoodItem/ReferenceObject ile birebir)

struct ReferenceObject: Codable, Identifiable {
    var id: String { nesne }
    let nesne: String
    let varsayilanOlcu: String
    let nasilKullanildi: String

    enum CodingKeys: String, CodingKey {
        case nesne
        case varsayilanOlcu = "varsayilan_olcu"
        case nasilKullanildi = "nasil_kullanildi"
    }
}

struct FoodItem: Codable, Identifiable {
    var id = UUID()
    var ad: String
    var porsiyonTarifi: String
    var gram: Double
    var kalori: Double
    var proteinG: Double
    var karbonhidratG: Double
    var yagG: Double
    var guven: String   // dusuk | orta | yuksek

    enum CodingKeys: String, CodingKey {
        case ad, gram, kalori, guven
        case porsiyonTarifi = "porsiyon_tarifi"
        case proteinG = "protein_g"
        case karbonhidratG = "karbonhidrat_g"
        case yagG = "yag_g"
    }
}

struct Totals: Codable {
    var kalori: Double = 0
    var proteinG: Double = 0
    var karbonhidratG: Double = 0
    var yagG: Double = 0

    enum CodingKeys: String, CodingKey {
        case kalori
        case proteinG = "protein_g"
        case karbonhidratG = "karbonhidrat_g"
        case yagG = "yag_g"
    }
}

struct Analysis: Codable {
    var isFood: Bool
    var referenceObjects: [ReferenceObject]
    var scaleReasoning: String
    var items: [FoodItem]
    var toplam: Totals
    var uyarilar: [String]
    var fotoIpucu: String

    enum CodingKeys: String, CodingKey {
        case toplam, uyarilar
        case isFood = "is_food"
        case referenceObjects = "reference_objects"
        case scaleReasoning = "scale_reasoning"
        case items
        case fotoIpucu = "foto_ipucu"
    }
}

enum AIError: LocalizedError {
    case missingKey
    case quotaExceeded
    case unauthorized
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "GEMINI_API_KEY tanımlı değil (GeminiService.apiKey)."
        case .quotaExceeded:
            return "Gemini kotası doldu (429). Birkaç dakika bekleyin veya daha hafif bir model seçin."
        case .unauthorized:
            return "API anahtarı geçersiz veya yetkisiz."
        case .badResponse(let msg):
            return "Model beklenen yapıda yanıt vermedi: \(msg)"
        case .network(let msg):
            return "Gemini çağrısı başarısız: \(msg)"
        }
    }
}

enum GeminiModel: String, CaseIterable {
    case flashLite = "gemini-3.5-flash-lite"
    case flash36 = "gemini-3.6-flash"
    case flash38 = "gemini-3.8-flash"

    var note: String {
        switch self {
        case .flashLite: return "En hızlı (~6-7 sn) — günlük kullanım için önerilen"
        case .flash36: return "Dengeli (~20 sn) — orta karmaşık tabaklar için"
        case .flash38: return "En isabetli (~25-30 sn) — zor/karışık tabaklar için"
        }
    }
}

enum GeminiService {
    static let apiKey = Secrets.geminiAPIKey

    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models"

    // MARK: Prompt (ai.py SYSTEM_PROMPT / USER_PROMPT ile birebir ayni icerik)

    private static let systemPrompt = #"""
Sen beslenme ve görsel porsiyon tahmini konusunda uzman bir diyetisyensin.
Sana gönderilen yemek fotoğrafından porsiyon, gramaj, kalori ve makro besin değerlerini tahmin ediyorsun.
Türkiye mutfağını ve Türkiye'deki standart servis kaplarını iyi biliyorsun.

# EN ÖNEMLİ KURAL: ÖLÇEKLEME REFERANS NESNELERLE YAPILIR
Gramajı ASLA "göz kararı" verme. Önce kadrajdaki bilinen boyutlu nesneleri bul, tabağın/kabın
gerçek boyutunu bunlarla oranla, sonra hacim üzerinden gramaja geç.

## Referans nesne kataloğu (gerçek ölçüler)
- Standart su bardağı: çap ~7 cm, yükseklik ~12 cm, hacim 200-250 ml
- Çay bardağı (ince belli): yükseklik ~9 cm, ~100 ml
- Kupa/mug: ~300 ml, çap ~8 cm
- Yemek tabağı (düz servis): çap 24-27 cm
- Küçük/tatlı tabağı: çap 19-21 cm
- Çorba/salata kâsesi: çap 14-16 cm, 300-400 ml
- Yemek kaşığı: toplam boy 19-20 cm, kaşık çukuru ~15 ml
- Çay kaşığı: boy ~13 cm, ~5 ml
- Çatal: boy ~19 cm
- Bıçak: boy ~21 cm
- Ekmek dilimi (tost/somun): ~10 x 10 cm, kalınlık ~1,2 cm, 25-30 g
- Kredi kartı: 8,6 x 5,4 cm
- Akıllı telefon: ~14,7 x 7,1 cm
- Yetişkin avuç içi: ~9 x 10 cm; bir avuç içi kalınlığındaki et dilimi ~1 cm
- Baş parmak ilk boğumu: ~2,5 cm

## Zorunlu 5 adımlı akıl yürütme
1. Kadrajdaki tüm referans nesneleri tespit et ve `reference_objects` alanına yaz.
2. En güvenilir referansı seç, tabağın/kabın çapını onunla ORANLA.
   (Örnek: bardağın çapı tabağın çapının 1/3,5'i kadarsa tabak çapı ~7x3,5 = 24,5 cm.)
3. Her yemeğin tabakta kapladığı alan yüzdesini ve ortalama derinliğini tahmin et,
   HACMİ ml cinsinden hesapla. (Örnek: 24,5 cm tabağın alanı ~470 cm²; pilav %30'unu
   ~2 cm yükseklikle kaplıyorsa hacim ~470x0,30x2 = ~280 ml.)
4. Hacmi yemek türüne göre YOĞUNLUK ile grama çevir (g/ml):
   pilav-bulgur 0,85 | makarna 0,70 | çorba 1,00 | et-tavuk-balık 1,05 | sebze yemeği 0,90
   | salata 0,35 | patates kızartması 0,60 | yoğurt-cacık 1,03 | kuru baklagil yemeği 1,00
   | tatlı-şurup 1,20 | ekmek 0,30 | peynir 1,05
5. Gramajdan kalori ve makroları hesapla. Türk mutfağı porsiyon referanslarını kullan
   (1 kepçe çorba ~200 ml, 1 köfte ~30 g, 1 dilim ekmek ~25-30 g, 1 porsiyon pilav ~150-180 g).

## Perspektif kuralı
Tam tepeden çekilmiş fotoğrafta derinlik görünmez. Bu durumda tabağın kenar yüksekliğinden,
yemeğin gölgesinden ve kabın doluluğundan derinlik çıkar. Emin olamıyorsan MUHAFAZAKÂR
(düşük) derinlik varsay ve bunu `uyarilar` alanına yaz.

## Referans nesne yoksa
Yine de tahmin yap ama: tabağı 26 cm çap varsay, tüm kalemlerde `guven` = "dusuk" ver,
`uyarilar` alanına "Kadrajda referans nesne yok, tahmin ±%40 sapabilir" yaz ve
`foto_ipucu` alanına tabağın yanına su bardağı veya çatal koyma önerisini yaz.

## Kalem ayırma
- Tabakta birden fazla yemek varsa HER BİRİNİ AYRI kalem yap (pilav, tavuk, salata = 3 kalem).
  Kullanıcı tek tek düzeltebilmeli.
- İçecekleri (ayran, kola, çay, meyve suyu) ayrı kalem yap. Sade çay/kahve için kalori 0 ver
  ama şeker/süt görüyorsan ekle.
- Ekmek, sos, tereyağı gibi ek kalemleri atlama.

## Gizli kalorileri unutma
- Kızartmada yağ emilimi (patates kızartması ~%10-12 yağ emer)
- Tabaktaki sos, zeytinyağı, tereyağı parlaklıkları
- Pilavdaki tereyağı, salatadaki sos
Bunları gramaja/kaloriye dahil et ve `scale_reasoning` içinde belirt.

## Çıktı kuralları
- TÜM METİNLERİ DÜZGÜN TÜRKÇE İMLÂYLA YAZ; Türkçe karakterleri (ç, ğ, ı, İ, ö, ş, ü) mutlaka
  kullan. ASCII'ye sadeleştirme yapma ("kasigi" değil "kaşığı", "pilavi" değil "pilavı").
- `scale_reasoning`: hangi referansı kullandığını, tabak çapını, hacmi ve gramaja nasıl
  geçtiğini 2-4 cümleyle, sayılarla anlat. Kullanıcı bunu okuyup düzeltme yapacak.
- Yemek adları günlük dilde olsun ("Etli nohut", "Bulgur pilavı").
- `toplam` alanı `items` toplamıyla tutarlı olmalı.
- Görüntüde yiyecek yoksa `is_food` = false, `items` boş, `uyarilar` dolu olsun.
- Sadece JSON döndür; markdown, açıklama, kod bloğu ekleme.
"""#

    private static let userPrompt = """
    Bu fotoğraftaki yiyecek ve içecekleri analiz et.
    Önce kadrajdaki referans nesneleri bul, tabak/kap boyutunu onlarla oranla,
    hacim üzerinden gramajı hesapla ve her yemeği ayrı kalem olarak döndür.
    """

    // MARK: Gemini response_schema (buyuk harfli tip adlari: OBJECT/STRING/NUMBER/ARRAY/BOOLEAN)

    private static let responseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "is_food": ["type": "BOOLEAN"],
            "reference_objects": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "nesne": ["type": "STRING"],
                        "varsayilan_olcu": ["type": "STRING"],
                        "nasil_kullanildi": ["type": "STRING"],
                    ],
                    "required": ["nesne", "varsayilan_olcu", "nasil_kullanildi"],
                ],
            ],
            "scale_reasoning": ["type": "STRING"],
            "items": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "ad": ["type": "STRING"],
                        "porsiyon_tarifi": ["type": "STRING"],
                        "gram": ["type": "NUMBER"],
                        "kalori": ["type": "NUMBER"],
                        "protein_g": ["type": "NUMBER"],
                        "karbonhidrat_g": ["type": "NUMBER"],
                        "yag_g": ["type": "NUMBER"],
                        "guven": ["type": "STRING", "enum": ["dusuk", "orta", "yuksek"]],
                    ],
                    "required": ["ad", "porsiyon_tarifi", "gram", "kalori", "protein_g",
                                 "karbonhidrat_g", "yag_g", "guven"],
                ],
            ],
            "toplam": [
                "type": "OBJECT",
                "properties": [
                    "kalori": ["type": "NUMBER"],
                    "protein_g": ["type": "NUMBER"],
                    "karbonhidrat_g": ["type": "NUMBER"],
                    "yag_g": ["type": "NUMBER"],
                ],
                "required": ["kalori", "protein_g", "karbonhidrat_g", "yag_g"],
            ],
            "uyarilar": ["type": "ARRAY", "items": ["type": "STRING"]],
            "foto_ipucu": ["type": "STRING"],
        ],
        "required": ["is_food", "reference_objects", "scale_reasoning", "items", "toplam", "uyarilar", "foto_ipucu"],
    ]

    // MARK: Cagri

    static func analyze(image: UIImage, model: GeminiModel, note: String = "") async throws -> Analysis {
        guard let jpeg = ImageProcessing.prepare(image) else {
            throw AIError.badResponse("Görsel işlenemedi.")
        }
        let base64 = jpeg.base64EncodedString()

        var promptText = userPrompt
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptText += "\n\nEK BİLGİ (kullanıcıdan): \(note)"
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [[
                "parts": [
                    ["text": promptText],
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                ],
            ]],
            "generationConfig": [
                "response_mime_type": "application/json",
                "response_schema": responseSchema,
            ],
        ]

        guard let url = URL(string: "\(endpoint)/\(model.rawValue):generateContent?key=\(apiKey)") else {
            throw AIError.network("Geçersiz URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.network("Sunucudan yanıt alınamadı.")
        }
        if http.statusCode == 429 {
            throw AIError.quotaExceeded
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AIError.unauthorized
        }
        if http.statusCode != 200 {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIError.network("HTTP \(http.statusCode): \(bodyText.prefix(200))")
        }

        return try parse(data)
    }

    private static func parse(_ data: Data) throws -> Analysis {
        struct Envelope: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AIError.badResponse("Yanıt ayrıştırılamadı: \(raw.prefix(200))")
        }

        guard let text = envelope.candidates.first?.content.parts.first(where: { $0.text != nil })?.text,
              let jsonData = text.data(using: .utf8) else {
            throw AIError.badResponse("Model boş yanıt döndürdü.")
        }

        do {
            return try JSONDecoder().decode(Analysis.self, from: jsonData)
        } catch {
            throw AIError.badResponse("JSON şeması uyuşmadı: \(error.localizedDescription)")
        }
    }
}
