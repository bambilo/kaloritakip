"""Beslenme hesaplari, hedef belirleme ve tarih/saat dilimi yardimcilari."""

from __future__ import annotations

import os
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

# ---------------------------------------------------------------- saat dilimi

DEFAULT_TZ = "Europe/Istanbul"


def _tz_name() -> str:
    """Saat dilimi: once st.secrets, sonra ortam degiskeni, sonra varsayilan."""
    try:
        import streamlit as st

        if "TIMEZONE" in st.secrets:
            return str(st.secrets["TIMEZONE"])
    except Exception:
        pass
    return os.environ.get("TIMEZONE", DEFAULT_TZ)


def tz() -> ZoneInfo:
    try:
        return ZoneInfo(_tz_name())
    except Exception:
        return ZoneInfo(DEFAULT_TZ)


def now() -> datetime:
    """Yerel saat dilimindeki su an."""
    return datetime.now(tz())


def today() -> date:
    """Yerel gun. Sunucu UTC oldugunda gece yenilen ogunlerin yanlis
    gune yazilmamasi icin her yerde bu kullanilir."""
    return now().date()


def date_str(d: date | None = None) -> str:
    return (d or today()).isoformat()


def last_n_days(n: int, end: date | None = None) -> list[date]:
    end = end or today()
    return [end - timedelta(days=i) for i in range(n - 1, -1, -1)]


def suggest_meal_type(when: datetime | None = None) -> str:
    """Saate gore ogun etiketi onerisi."""
    hour = (when or now()).hour
    if 4 <= hour < 10:
        return "kahvalti"
    if 10 <= hour < 15:
        return "ogle"
    if 15 <= hour < 21:
        return "aksam"
    return "atistirmalik"


MEAL_TYPES = ["kahvalti", "ogle", "aksam", "atistirmalik"]
MEAL_LABELS = {
    "kahvalti": "🍳 Kahvaltı",
    "ogle": "🥗 Öğle",
    "aksam": "🍽️ Akşam",
    "atistirmalik": "🍎 Atıştırmalık",
}

# ------------------------------------------------------------- hedef hesaplari

ACTIVITY_FACTORS = {
    "sedanter": 1.2,
    "hafif": 1.375,
    "orta": 1.55,
    "aktif": 1.725,
    "cok_aktif": 1.9,
}
ACTIVITY_LABELS = {
    "sedanter": "Sedanter (masa başı, spor yok)",
    "hafif": "Hafif aktif (haftada 1-3 gün spor)",
    "orta": "Orta aktif (haftada 3-5 gün spor)",
    "aktif": "Çok aktif (haftada 6-7 gün spor)",
    "cok_aktif": "Ekstra aktif (ağır iş / günde 2 antrenman)",
}
GOAL_LABELS = {
    "kilo_ver": "Kilo ver (-%15 kalori)",
    "koru": "Kiloyu koru",
    "kilo_al": "Kilo al (+%15 kalori)",
}
GOAL_FACTORS = {"kilo_ver": 0.85, "koru": 1.0, "kilo_al": 1.15}

SEX_LABELS = {"kadin": "Kadın", "erkek": "Erkek"}


def bmr_mifflin(sex: str, age: int, height_cm: float, weight_kg: float) -> float:
    """Mifflin-St Jeor bazal metabolizma hizi (kcal/gun)."""
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    return base + 5 if sex == "erkek" else base - 161


def tdee(sex: str, age: int, height_cm: float, weight_kg: float, activity: str) -> float:
    """Gunluk toplam enerji harcamasi."""
    return bmr_mifflin(sex, age, height_cm, weight_kg) * ACTIVITY_FACTORS.get(activity, 1.2)


def calculate_goals(
    sex: str, age: int, height_cm: float, weight_kg: float, activity: str, goal_type: str
) -> dict:
    """Kalori ve makro hedefleri.

    Protein 1.6 g/kg, yag toplam kalorinin %25'i, kalani karbonhidrat.
    Guvenlik icin kalori hedefi 1200 kcal altina dusurulmez.
    """
    calories = max(1200.0, tdee(sex, age, height_cm, weight_kg, activity) * GOAL_FACTORS.get(goal_type, 1.0))
    protein_g = round(1.6 * weight_kg)
    fat_g = round(calories * 0.25 / 9)
    carbs_kcal = calories - (protein_g * 4 + fat_g * 9)
    carbs_g = max(0, round(carbs_kcal / 4))
    return {
        "calorie_goal": round(calories),
        "protein_goal_g": float(protein_g),
        "carbs_goal_g": float(carbs_g),
        "fat_goal_g": float(fat_g),
    }


# ----------------------------------------------------------- porsiyon olcekleme


def scale_item(item: dict, new_grams: float) -> dict:
    """Gramaj degisince kalori ve makrolari orantili guncelle.

    Kalem 100 g bazina normalize edilip yeni gramajla yeniden carpilir.
    Eski gramaj yoksa/sifirsa oranlama yapilamaz, kalem oldugu gibi doner.
    """
    old_grams = float(item.get("grams") or 0)
    if old_grams <= 0 or new_grams is None or new_grams < 0:
        return dict(item, grams=new_grams)

    ratio = float(new_grams) / old_grams
    scaled = dict(item)
    scaled["grams"] = float(new_grams)
    for key in ("calories", "protein_g", "carbs_g", "fat_g"):
        scaled[key] = round(float(item.get(key) or 0) * ratio, 1)
    return scaled


def sum_macros(rows) -> dict:
    """Kayit listesinin kalori/makro toplami. rows: dict benzeri diziler."""
    totals = {"calories": 0.0, "protein_g": 0.0, "carbs_g": 0.0, "fat_g": 0.0}
    for row in rows:
        for key in totals:
            totals[key] += float(row[key] or 0)
    return {k: round(v, 1) for k, v in totals.items()}
