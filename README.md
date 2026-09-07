# 🥗 Kalori Takip

Yemek fotoğrafından **referans nesnelerle ölçekleme** yaparak porsiyon, gramaj, kalori ve
makro tahmini yapan; onayladığın kayıtları günlük beslenme günlüğüne yazan Streamlit uygulaması.

- **Vision AI:** Gemini (varsayılan `gemini-3.6-flash`) — kadrajdaki bardak, çatal, tabak kenarı,
  el gibi bilinen nesnelerle tabağın gerçek boyutunu oranlar, hacim → yoğunluk → gramaj yolunu izler.
- **Düzeltme:** Her kalem ayrı kart; gramajı değiştirdiğinde kalori ve makrolar orantılı güncellenir.
  Kaloriyi elle yazarsan o kalemde oranlama durur.
- **Takip:** Günlük kalori/makro toplamları, hedefe göre ilerleme, öğün bazlı liste, tekil silme.
- **Çok kullanıcı:** İsim + PIN ile ayrı profiller, ayrı hedefler ve ayrı geçmiş.

## Kurulum (yerel)

```bash
brew install python@3.12                      # Streamlit ve google-genai Python >= 3.10 istiyor
cd ~/kaloritakip
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .streamlit/secrets.toml.example .streamlit/secrets.toml
# secrets.toml içine GEMINI_API_KEY yaz (https://aistudio.google.com -> Get API key)

streamlit run app.py                          # http://localhost:8501
```

Yerelde veriler `kaloritakip.db` (SQLite) dosyasında tutulur; ilk çalıştırmada otomatik oluşur.

## Deploy (telefondan iki kişi kullanmak için)

Tarayıcı kamerası yalnızca HTTPS'te açıldığı için uygulama Streamlit Community Cloud'da barındırılır.
Cloud'un diski kalıcı olmadığından veri Turso (libSQL) üzerinde durur — SQL ve şema birebir SQLite.

1. **Turso:** [app.turso.tech](https://app.turso.tech) → ücretsiz hesap (GitHub ile giriş yapılabilir) →
   *Create Database* → adı `kaloritakip` → bölge Frankfurt/Amsterdam → oluştuktan sonra
   veritabanı sayfasından **Database URL** (`libsql://...`) ve *Create Token* ile **auth token** al.
   Tabloları elle oluşturmana gerek yok; uygulama ilk açılışta şemayı kendisi kurar.
2. **GitHub:** `git init && git add . && git commit -m "kalori takip"` → **private** repo'ya push.
   (`.streamlit/secrets.toml` `.gitignore`'da, repoya girmez.)
3. **Streamlit Cloud:** [share.streamlit.io](https://share.streamlit.io) → repo'yu bağla →
   *Advanced settings* → **Python 3.12** → Secrets alanına:

   ```toml
   GEMINI_API_KEY = "..."
   TURSO_DATABASE_URL = "libsql://....turso.io"
   TURSO_AUTH_TOKEN = "..."
   ```

4. İlk açılışta **Yeni profil** sekmesinden kendi profilini, arkadaşın da kendi profilini oluşturur.
5. Telefondan HTTPS adrese gir → tarayıcı menüsünden **Ana ekrana ekle**. "Beni hatırla"
   işaretlersen kısayoldan her açılışta otomatik giriş yaparsın (30 gün).

> **Not:** "Beni hatırla" tokeni adres çubuğundaki `?t=...` parametresinde durur. O adresi
> başkasıyla paylaşırsan profiline erişebilir; paylaşırken adresin `?t=` kısmını silin.

## Dosyalar

| Dosya | İş |
|---|---|
| `app.py` | Streamlit arayüzü: giriş, Ekle / Bugün / Geçmiş / Profil sekmeleri |
| `ai.py` | Vision system prompt, JSON şeması, Gemini çağrısı, görsel ön işleme (EXIF + küçültme) |
| `db.py` | Şema ve tüm CRUD; `TURSO_DATABASE_URL` varsa Turso, yoksa yerel SQLite |
| `auth.py` | Profil, PIN (pbkdf2-sha256), "beni hatırla" tokeni |
| `nutrition.py` | Mifflin-St Jeor hedefleri, orantılı porsiyon ölçekleme, tarih/saat dilimi |

## Doğrulama / hata ayıklama

```bash
# Veritabanı sağlığı
.venv/bin/python -c "import db; db.init_db(); print(db.health())"

# Gemini'yi arayüzsüz dene (prompt çıktısını ham JSON olarak gör)
.venv/bin/python -m ai fotograf.jpg
.venv/bin/python -m ai fotograf.jpg gemini-3.8-flash
```

Saat dilimi varsayılan `Europe/Istanbul`'dur (sunucu UTC olduğunda gece yenilen öğünler doğru güne
yazılsın diye). Değiştirmek için secrets'a `TIMEZONE = "..."` ekleyin.


- Modele gönderilen fotoğraf 1024 piksele küçültülür (kota ve hız için); geçmişte görünen
  küçük önizleme 320 piksel olarak veritabanında saklanır.
