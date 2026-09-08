# Kalori Takip

Yemek fotoğrafı çekiyorsun, uygulama kadrajdaki bardağı, tabağı, çatalı referans alıp
gerçek porsiyonu, gramajı, kaloriyi ve makroları tahmin ediyor. Diğer kalori
uygulamalarından farkı da tam olarak bu: göz kararı bir sayı üretmek yerine önce
kadrajdaki bilinen boyutlu nesnelerle tabağın gerçek çapını çıkarıyor, sonra hacim
üzerinden gramaja geçiyor — tıpkı bir diyetisyenin yapacağı gibi.

Başlangıçta Streamlit ile yazılmış bir web uygulamasıydı; bu repo onun yerine geçen,
tamamen native SwiftUI ile yazılmış iOS uygulaması. Aracı sunucu yok — telefon
doğrudan Gemini'ye bağlanıyor, veriler cihazda tutuluyor. İki kişilik (aile) kullanım
için düşünüldü; her telefon kendi verisini tutuyor.

## Özellikler

- **Fotoğrafla analiz** — kamera veya galeriden fotoğraf, referans nesnelerle
  ölçekleme yapan bir sistem promptuyla Gemini'ye gönderiliyor
- **Düzenlenebilir sonuç** — analiz sonrası her kalemin adı, gramajı, kalorisi,
  makroları elle düzeltilebiliyor; gramaj değişince değerler orantılı güncelleniyor
- **Günlük takip** — kalori ve makro hedeflerine göre ilerleme, öğün bazlı liste
- **Geçmiş** — 7/30 günlük grafik, günlük detaya inme
- **Favoriler** ve **elle ekleme** — fotoğrafsız hızlı kayıt
- **Otomatik hedef hesabı** — boy/kilo/yaş/aktivite/hedefe göre BMR/TDEE tabanlı
  kalori ve makro hedefi, istenirse elle de girilebiliyor
- Analiz kalitesi (hızlı/dengeli/titiz) dışında hiçbir teknik detay veya model adı
  arayüzde görünmüyor

## Kullanılan teknolojiler

- **Swift / SwiftUI** — arayüz
- **SwiftData** — yerel veri saklama (yemek kayıtları, favoriler, profil)
- **Swift Charts** — geçmiş grafiği
- **XcodeGen** — proje dosyası `project.yml`'den üretiliyor, elle düzenlenmiyor
- **Gemini API** — görsel analiz (referans nesneyle porsiyon/kalori tahmini)

## Kurulum

Gereksinimler: Xcode (26+), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone https://github.com/bambilo/kaloritakip.git
cd kaloritakip
cp KaloriTakip/Secrets.swift.example KaloriTakip/Secrets.swift
# Secrets.swift içine kendi Gemini API anahtarınızı yapıştırın
# (https://aistudio.google.com -> Get API key)
xcodegen generate
open KaloriTakip.xcodeproj
```

### Telefona kurma (ücretsiz Apple ID ile sideload)

1. iPhone'u Mac'e kabloyla bağlayın, Xcode'da cihaz seçiciden telefonu seçin.
2. `KaloriTakip` hedefi → **Signing & Capabilities** → **Team**'den kendi Apple
   ID'nizi seçin (ücretsiz hesap yeterli). Bundle identifier çakışırsa
   (`com.ardanural.kaloritakip`) sonuna kendi isminizi ekleyip benzersiz yapın.
3. ⌘R (Run) — ilk seferde telefonda **Ayarlar → Genel → VPN ve Cihaz Yönetimi**
   üzerinden geliştirici profilinize güvenmeniz gerekiyor.
4. Ücretsiz Apple ID ile imzalanan uygulamalar **7 günde bir** yeniden imzalanmalı;
   bir hafta sonra Mac'e bağlayıp tekrar ⌘R yapmanız yeterli, veriler silinmiyor.

## Notlar

- API anahtarı `Secrets.swift` içinde tutuluyor (gitignore'da, repoya girmiyor).
  Bu proje **yalnızca kişisel sideload kullanımı** içindir — App Store'a
  yüklemeyin, IPA'yı paylaşmayın.
- Sistem promptu Türk mutfağı ve standart servis kaplarına (bardak, tabak, kaşık
  vb.) göre kalibre edilmiş.
