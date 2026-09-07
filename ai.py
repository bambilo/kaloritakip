"""Gemini gorsel analizi: referans nesnelerle olcekleme yaparak porsiyon/kalori tahmini."""

from __future__ import annotations

import base64
import io
import json
import os
from typing import Literal

from PIL import Image, ImageOps
from pydantic import BaseModel, Field, ValidationError

DEFAULT_MODEL = "gemini-3.6-flash"
AVAILABLE_MODELS = ["gemini-3.6-flash", "gemini-3.8-flash", "gemini-3.5-flash-lite"]
MODEL_NOTES = {
    "gemini-3.6-flash": "Dengeli — günlük kullanım için önerilen",
    "gemini-3.8-flash": "En isabetli — zor/karışık tabaklar için",
    "gemini-3.5-flash-lite": "En hızlı ve ucuz — basit tabaklar için",
}

MAX_EDGE = 1024          # modele gonderilen gorselin uzun kenari
THUMB_EDGE = 320         # veritabaninda saklanan kucuk onizleme
JPEG_QUALITY = 85


# ------------------------------------------------------------------ cikti semasi


class ReferenceObject(BaseModel):
    nesne: str = Field(description="Kadrajda gorulen referans nesne, orn. 'su bardagi'")
    varsayilan_olcu: str = Field(description="Bu nesne icin varsayilan gercek olcu, orn. 'cap 7 cm, 200 ml'")
    nasil_kullanildi: str = Field(description="Bu nesnenin olceklemede nasil kullanildigi")


class FoodItem(BaseModel):
    ad: str
    porsiyon_tarifi: str = Field(description="Gunluk dille porsiyon, orn. '1 orta kepce', '2 kasik'")
    gram: float = Field(ge=0)
    kalori: float = Field(ge=0)
    protein_g: float = Field(ge=0)
    karbonhidrat_g: float = Field(ge=0)
    yag_g: float = Field(ge=0)
    guven: Literal["dusuk", "orta", "yuksek"]


class Totals(BaseModel):
    kalori: float = 0
    protein_g: float = 0
    karbonhidrat_g: float = 0
    yag_g: float = 0


class Analysis(BaseModel):
    is_food: bool
    reference_objects: list[ReferenceObject] = []
    scale_reasoning: str = ""
    items: list[FoodItem] = []
    toplam: Totals = Totals()
    uyarilar: list[str] = []
    foto_ipucu: str = ""


# Gemini'ye gonderilen JSON semasi elle yazilir: $ref/$defs iceren
# pydantic ciktisi yerine duz sema kullanmak uyumluluk acisindan guvenli.
RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "is_food": {"type": "boolean", "description": "Goruntude yenilebilir yiyecek/icecek var mi"},
        "reference_objects": {
            "type": "array",
            "description": "Olceklemede kullanilan referans nesneler",
            "items": {
                "type": "object",
                "properties": {
                    "nesne": {"type": "string"},
                    "varsayilan_olcu": {"type": "string"},
                    "nasil_kullanildi": {"type": "string"},
                },
                "required": ["nesne", "varsayilan_olcu", "nasil_kullanildi"],
            },
        },
        "scale_reasoning": {
            "type": "string",
            "description": "Olcekleme akil yurutmesi: referans -> tabak capi -> hacim -> gram",
        },
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "ad": {"type": "string"},
                    "porsiyon_tarifi": {"type": "string"},
                    "gram": {"type": "number"},
                    "kalori": {"type": "number"},
                    "protein_g": {"type": "number"},
                    "karbonhidrat_g": {"type": "number"},
                    "yag_g": {"type": "number"},
                    "guven": {"type": "string", "enum": ["dusuk", "orta", "yuksek"]},
                },
                "required": ["ad", "porsiyon_tarifi", "gram", "kalori", "protein_g",
                             "karbonhidrat_g", "yag_g", "guven"],
            },
        },
        "toplam": {
            "type": "object",
            "properties": {
                "kalori": {"type": "number"},
                "protein_g": {"type": "number"},
                "karbonhidrat_g": {"type": "number"},
                "yag_g": {"type": "number"},
            },
            "required": ["kalori", "protein_g", "karbonhidrat_g", "yag_g"],
        },
        "uyarilar": {"type": "array", "items": {"type": "string"}},
        "foto_ipucu": {"type": "string"},
    },
    "required": ["is_food", "reference_objects", "scale_reasoning", "items", "toplam",
                 "uyarilar", "foto_ipucu"],
}


# ------------------------------------------------------------------ system prompt

SYSTEM_PROMPT = """Sen beslenme ve görsel porsiyon tahmini konusunda uzman bir diyetisyensin.
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
- Sadece JSON döndür; markdown, açıklama, kod bloğu ekleme."""

USER_PROMPT = """Bu fotoğraftaki yiyecek ve içecekleri analiz et.
Önce kadrajdaki referans nesneleri bul, tabak/kap boyutunu onlarla oranla,
hacim üzerinden gramajı hesapla ve her yemeği ayrı kalem olarak döndür."""


# ------------------------------------------------------------------ gorsel isleme


def prepare_image(raw: bytes, max_edge: int = MAX_EDGE) -> bytes:
    """EXIF rotasyonunu duzelt, kucult, JPEG'e cevir.

    Telefon fotograflari EXIF ile dondurulmus gelir; duzeltilmezse model
    tabak/bardak oranlarini yanlis okur.
    """
    with Image.open(io.BytesIO(raw)) as img:
        img = ImageOps.exif_transpose(img)
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
        img.thumbnail((max_edge, max_edge), Image.LANCZOS)
        buf = io.BytesIO()
        img.convert("RGB").save(buf, format="JPEG", quality=JPEG_QUALITY, optimize=True)
        return buf.getvalue()


def make_thumbnail(raw: bytes) -> bytes:
    return prepare_image(raw, max_edge=THUMB_EDGE)


# ------------------------------------------------------------------ Gemini cagrisi


class AIError(Exception):
    """Kullaniciya gosterilebilir hata."""


def _api_key() -> str:
    try:
        import streamlit as st

        if "GEMINI_API_KEY" in st.secrets:
            key = str(st.secrets["GEMINI_API_KEY"]).strip()
            if key:
                return key
    except Exception:
        pass
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not key:
        raise AIError(
            "GEMINI_API_KEY bulunamadı. `.streamlit/secrets.toml` dosyasına ekleyin "
            "(örnek dosya: `.streamlit/secrets.toml.example`)."
        )
    return key


def _client():
    from google import genai

    return genai.Client(api_key=_api_key())


def _extract_json(text: str) -> dict:
    """Model bazen JSON'u markdown blogu icinde dondurur; temizleyip ayristir."""
    cleaned = (text or "").strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("```")[1]
        if cleaned.lstrip().startswith("json"):
            cleaned = cleaned.lstrip()[4:]
    cleaned = cleaned.strip()
    if not cleaned:
        raise AIError("Model boş yanıt döndürdü.")
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        start, end = cleaned.find("{"), cleaned.rfind("}")
        if start == -1 or end <= start:
            raise AIError("Model geçerli JSON döndürmedi.")
        return json.loads(cleaned[start:end + 1])


def _call_model(image_bytes: bytes, model: str, extra_note: str = "") -> tuple[Analysis, str]:
    client = _client()
    prompt = USER_PROMPT + (f"\n\nEK BİLGİ (kullanıcıdan): {extra_note}" if extra_note else "")

    interaction = client.interactions.create(
        model=model,
        system_instruction=SYSTEM_PROMPT,
        input=[
            {"type": "text", "text": prompt},
            {
                "type": "image",
                "data": base64.b64encode(image_bytes).decode("utf-8"),
                "mime_type": "image/jpeg",
                "resolution": "high",
            },
        ],
        response_format={
            "type": "text",
            "mime_type": "application/json",
            "schema": RESPONSE_SCHEMA,
        },
    )
    raw_text = interaction.output_text or ""
    return Analysis.model_validate(_extract_json(raw_text)), raw_text


def analyze_image(raw_image: bytes, model: str = DEFAULT_MODEL, note: str = "") -> tuple[Analysis, str]:
    """Fotografi analiz et. (Analysis, ham_json) dondurur.

    Sema dogrulamasi basarisiz olursa bir kez yeniden dener.
    """
    image_bytes = prepare_image(raw_image)
    last_error: Exception | None = None

    for attempt in range(2):
        try:
            return _call_model(image_bytes, model, note)
        except (ValidationError, json.JSONDecodeError, AIError) as exc:
            if isinstance(exc, AIError) and "GEMINI_API_KEY" in str(exc):
                raise
            last_error = exc
            continue
        except Exception as exc:  # ag / kota / API hatalari
            message = str(exc)
            code = getattr(exc, "code", None)
            if code == 429 or "RESOURCE_EXHAUSTED" in message or "429" in message:
                raise AIError(
                    "Gemini kotası doldu (429). Birkaç dakika bekleyin veya sidebar'dan "
                    "daha hafif bir model seçin."
                ) from exc
            if code in (401, 403) or "API key" in message or "PERMISSION_DENIED" in message:
                raise AIError("API anahtarı geçersiz veya yetkisiz. GEMINI_API_KEY değerini kontrol edin.") from exc
            raise AIError(f"Gemini çağrısı başarısız: {message[:300]}") from exc

    raise AIError(
        f"Model beklenen JSON yapısını iki denemede de döndüremedi ({type(last_error).__name__}). "
        "Fotoğrafı yeniden çekmeyi veya kaydı elle girmeyi deneyin."
    )


def to_ui_items(analysis: Analysis) -> list[dict]:
    """Analiz kalemlerini UI/DB'nin kullandigi ortak sozluk yapisina cevir."""
    return [
        {
            "food_name": item.ad,
            "portion_desc": item.porsiyon_tarifi,
            "grams": round(item.gram, 1),
            "calories": round(item.kalori, 1),
            "protein_g": round(item.protein_g, 1),
            "carbs_g": round(item.karbonhidrat_g, 1),
            "fat_g": round(item.yag_g, 1),
            "confidence": item.guven,
        }
        for item in analysis.items
    ]


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Kullanim: python -m ai <fotograf.jpg> [model]")
        raise SystemExit(1)
    model_name = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_MODEL
    with open(sys.argv[1], "rb") as fh:
        result, raw = analyze_image(fh.read(), model=model_name)
    print(json.dumps(result.model_dump(), ensure_ascii=False, indent=2))
