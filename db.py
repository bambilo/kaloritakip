"""Veritabani katmani.

Yerelde sqlite3 dosyasi, Streamlit Cloud'da Turso (libSQL) kullanilir.
Iki surucu de DB-API 2.0 uyumlu oldugu icin tum CRUD kodu tektir.
"""

from __future__ import annotations

import json
import os
import sqlite3
import threading
from typing import Any, Sequence

import nutrition

LOCAL_DB_PATH = os.environ.get("KALORITAKIP_DB", "kaloritakip.db")

_conn = None
_lock = threading.Lock()

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  pin_hash TEXT NOT NULL,
  pin_salt TEXT NOT NULL,
  remember_token_hash TEXT,
  token_expires_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_profile (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  sex TEXT,
  age INTEGER,
  height_cm REAL,
  weight_kg REAL,
  activity_level TEXT,
  goal_type TEXT,
  calorie_goal REAL,
  protein_goal_g REAL,
  carbs_goal_g REAL,
  fat_goal_g REAL,
  goals_are_manual INTEGER DEFAULT 0,
  updated_at TEXT
);

CREATE TABLE IF NOT EXISTS food_logs (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date TEXT NOT NULL,
  logged_at TEXT NOT NULL,
  meal_type TEXT NOT NULL,
  food_name TEXT NOT NULL,
  portion_desc TEXT,
  grams REAL,
  calories REAL NOT NULL,
  protein_g REAL DEFAULT 0,
  carbs_g REAL DEFAULT 0,
  fat_g REAL DEFAULT 0,
  source TEXT NOT NULL,
  was_edited INTEGER DEFAULT 0,
  ai_model TEXT,
  ai_confidence TEXT,
  reference_objects TEXT,
  scale_reasoning TEXT,
  raw_json TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_logs_user_date ON food_logs(user_id, log_date);

CREATE TABLE IF NOT EXISTS log_images (
  log_id INTEGER PRIMARY KEY REFERENCES food_logs(id) ON DELETE CASCADE,
  thumb BLOB NOT NULL,
  mime TEXT DEFAULT 'image/jpeg'
);

CREATE TABLE IF NOT EXISTS favorites (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  food_name TEXT NOT NULL,
  grams REAL,
  calories REAL NOT NULL,
  protein_g REAL,
  carbs_g REAL,
  fat_g REAL,
  use_count INTEGER DEFAULT 1,
  last_used_at TEXT,
  UNIQUE(user_id, food_name)
);
"""

LOG_COLUMNS = (
    "id, user_id, log_date, logged_at, meal_type, food_name, portion_desc, grams, "
    "calories, protein_g, carbs_g, fat_g, source, was_edited, ai_model, ai_confidence, "
    "reference_objects, scale_reasoning, created_at"
)


# --------------------------------------------------------------- baglanti


def _secret(key: str) -> str | None:
    """Once st.secrets, sonra ortam degiskeni."""
    try:
        import streamlit as st

        if key in st.secrets:
            value = str(st.secrets[key]).strip()
            if value:
                return value
    except Exception:
        pass
    value = os.environ.get(key, "").strip()
    return value or None


def is_remote() -> bool:
    return bool(_secret("TURSO_DATABASE_URL"))


class DatabaseConfigError(Exception):
    """Turso baglanti bilgileri (URL/token) yanlis veya eksik oldugunda kullaniciya
    gosterilecek acik mesaj. Ham libsql hatasi secret degerini icerdigi icin
    Streamlit Cloud onu kullaniciya gizler ("redacted") -- bu yuzden asagida
    mesaji kendimiz, secret degerini icermeyecek sekilde yeniden yaziyoruz."""


def _connect_turso(url: str, token: str | None):
    import libsql

    try:
        conn = libsql.connect(database=url, auth_token=token or "")
        conn.execute("SELECT 1")  # baglantiyi hemen dogrula, ilk gercek sorguda degil
        return conn
    except Exception as exc:
        message = str(exc)
        if "404" in message or "Host not found" in message:
            raise DatabaseConfigError(
                "TURSO_DATABASE_URL geçersiz görünüyor (host bulunamadı). Turso panelinde "
                "veritabanının sayfasına girip 'Database URL' değerini ('libsql://...' ile "
                "başlayan, sonu '.turso.io' ile biten tam adres) tekrar kopyalayın."
            ) from exc
        lowered = message.lower()
        token_markers = ("401", "403", "unauthorized", "invalidtoken", "jwt", "400 bad request")
        if any(marker in lowered for marker in token_markers):
            raise DatabaseConfigError(
                "TURSO_AUTH_TOKEN geçersiz veya eksik görünüyor. Turso panelinde veritabanı "
                "sayfasından 'Create Token' ile yeni bir token üretip secrets'a tekrar yapıştırın "
                "(kopyalarken başına/sonuna boşluk veya tırnak eklenmediğinden emin olun)."
            ) from exc
        raise DatabaseConfigError(f"Turso bağlantısı kurulamadı: {message[:200]}") from exc


def get_conn():
    """Surece bir baglanti. Streamlit yeniden calistirmalarinda korunur."""
    global _conn
    if _conn is not None:
        return _conn
    with _lock:
        if _conn is None:
            url = _secret("TURSO_DATABASE_URL")
            if url:
                _conn = _connect_turso(url, _secret("TURSO_AUTH_TOKEN"))
            else:
                _conn = sqlite3.connect(LOCAL_DB_PATH, check_same_thread=False)
                _conn.execute("PRAGMA foreign_keys = ON")
                _conn.execute("PRAGMA journal_mode = WAL")
    return _conn


def _execute(sql: str, params: Sequence[Any] = ()):
    """Tum sorgular buradan gecer; her zaman parametreli (? placeholder)."""
    with _lock:
        cur = get_conn().execute(sql, tuple(params))
        return cur


def _commit() -> None:
    with _lock:
        get_conn().commit()


def query(sql: str, params: Sequence[Any] = ()) -> list[dict]:
    """SELECT -> dict listesi (iki surucude de calisir)."""
    with _lock:
        cur = get_conn().execute(sql, tuple(params))
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description] if cur.description else []
    return [dict(zip(cols, row)) for row in rows]


def query_one(sql: str, params: Sequence[Any] = ()) -> dict | None:
    rows = query(sql, params)
    return rows[0] if rows else None


def init_db() -> None:
    """Semayi olustur (idempotent)."""
    conn = get_conn()
    with _lock:
        for statement in filter(None, (s.strip() for s in SCHEMA.split(";"))):
            conn.execute(statement)
        conn.commit()


def health() -> dict:
    counts = {}
    for table in ("users", "food_logs", "favorites"):
        row = query_one(f"SELECT COUNT(*) AS n FROM {table}")
        counts[table] = row["n"] if row else 0
    return {"backend": "turso" if is_remote() else f"sqlite ({LOCAL_DB_PATH})", **counts}


def _last_insert_id() -> int:
    row = query_one("SELECT last_insert_rowid() AS id")
    return int(row["id"]) if row else 0


# --------------------------------------------------------------- kullanicilar


def list_users() -> list[dict]:
    return query("SELECT id, name FROM users ORDER BY name")


def get_user_by_name(name: str) -> dict | None:
    return query_one("SELECT * FROM users WHERE name = ?", (name,))


def get_user(user_id: int) -> dict | None:
    return query_one("SELECT * FROM users WHERE id = ?", (user_id,))


def create_user(name: str, pin_hash: str, pin_salt: str) -> int:
    _execute(
        "INSERT INTO users (name, pin_hash, pin_salt, created_at) VALUES (?, ?, ?, ?)",
        (name, pin_hash, pin_salt, nutrition.now().isoformat()),
    )
    _commit()
    user_id = _last_insert_id()
    _execute("INSERT INTO user_profile (user_id, updated_at) VALUES (?, ?)", (user_id, nutrition.now().isoformat()))
    _commit()
    return user_id


def update_pin(user_id: int, pin_hash: str, pin_salt: str) -> None:
    _execute("UPDATE users SET pin_hash = ?, pin_salt = ? WHERE id = ?", (pin_hash, pin_salt, user_id))
    _commit()


def set_remember_token(user_id: int, token_hash: str | None, expires_at: str | None) -> None:
    _execute(
        "UPDATE users SET remember_token_hash = ?, token_expires_at = ? WHERE id = ?",
        (token_hash, expires_at, user_id),
    )
    _commit()


def find_user_by_token_hash(token_hash: str) -> dict | None:
    return query_one(
        "SELECT * FROM users WHERE remember_token_hash = ? AND token_expires_at > ?",
        (token_hash, nutrition.now().isoformat()),
    )


# ------------------------------------------------------------------ profil


def get_profile(user_id: int) -> dict:
    row = query_one("SELECT * FROM user_profile WHERE user_id = ?", (user_id,))
    if row is None:
        _execute("INSERT INTO user_profile (user_id, updated_at) VALUES (?, ?)", (user_id, nutrition.now().isoformat()))
        _commit()
        row = query_one("SELECT * FROM user_profile WHERE user_id = ?", (user_id,))
    return row or {}


def save_profile(user_id: int, **fields) -> None:
    allowed = {
        "sex", "age", "height_cm", "weight_kg", "activity_level", "goal_type",
        "calorie_goal", "protein_goal_g", "carbs_goal_g", "fat_goal_g", "goals_are_manual",
    }
    updates = {k: v for k, v in fields.items() if k in allowed}
    if not updates:
        return
    get_profile(user_id)  # satirin var oldugundan emin ol
    assignments = ", ".join(f"{k} = ?" for k in updates)
    params = list(updates.values()) + [nutrition.now().isoformat(), user_id]
    _execute(f"UPDATE user_profile SET {assignments}, updated_at = ? WHERE user_id = ?", params)
    _commit()


# --------------------------------------------------------------- gunluk kayit


def add_log(user_id: int, item: dict, meal_type: str, source: str, log_date: str | None = None,
            thumb: bytes | None = None, meta: dict | None = None) -> int:
    """Bir yemek kalemini gunluge ekler, satir id'sini dondurur."""
    meta = meta or {}
    now = nutrition.now()
    _execute(
        """INSERT INTO food_logs
           (user_id, log_date, logged_at, meal_type, food_name, portion_desc, grams,
            calories, protein_g, carbs_g, fat_g, source, was_edited, ai_model,
            ai_confidence, reference_objects, scale_reasoning, raw_json, created_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            user_id,
            log_date or nutrition.date_str(),
            now.isoformat(),
            meal_type,
            item.get("food_name") or item.get("ad") or "Bilinmeyen",
            item.get("portion_desc"),
            item.get("grams"),
            float(item.get("calories") or 0),
            float(item.get("protein_g") or 0),
            float(item.get("carbs_g") or 0),
            float(item.get("fat_g") or 0),
            source,
            1 if meta.get("was_edited") else 0,
            meta.get("ai_model"),
            meta.get("ai_confidence"),
            json.dumps(meta.get("reference_objects"), ensure_ascii=False) if meta.get("reference_objects") else None,
            meta.get("scale_reasoning"),
            meta.get("raw_json"),
            now.isoformat(),
        ),
    )
    _commit()
    log_id = _last_insert_id()
    if thumb:
        _execute("INSERT OR REPLACE INTO log_images (log_id, thumb, mime) VALUES (?, ?, ?)",
                 (log_id, thumb, "image/jpeg"))
        _commit()
    return log_id


def get_logs(user_id: int, log_date: str) -> list[dict]:
    return query(
        f"SELECT {LOG_COLUMNS} FROM food_logs WHERE user_id = ? AND log_date = ? ORDER BY logged_at",
        (user_id, log_date),
    )


def get_log_image(log_id: int) -> bytes | None:
    row = query_one("SELECT thumb FROM log_images WHERE log_id = ?", (log_id,))
    return row["thumb"] if row else None


def update_log(log_id: int, user_id: int, **fields) -> None:
    allowed = {"food_name", "grams", "calories", "protein_g", "carbs_g", "fat_g", "meal_type", "portion_desc"}
    updates = {k: v for k, v in fields.items() if k in allowed}
    if not updates:
        return
    assignments = ", ".join(f"{k} = ?" for k in updates)
    params = list(updates.values()) + [log_id, user_id]
    _execute(f"UPDATE food_logs SET {assignments}, was_edited = 1 WHERE id = ? AND user_id = ?", params)
    _commit()


def delete_log(log_id: int, user_id: int) -> None:
    _execute("DELETE FROM log_images WHERE log_id = ?", (log_id,))
    _execute("DELETE FROM food_logs WHERE id = ? AND user_id = ?", (log_id, user_id))
    _commit()


def daily_totals(user_id: int, start_date: str, end_date: str) -> list[dict]:
    """Gun bazinda kalori/makro toplamlari (grafik icin)."""
    return query(
        """SELECT log_date,
                  ROUND(SUM(calories), 1) AS calories,
                  ROUND(SUM(protein_g), 1) AS protein_g,
                  ROUND(SUM(carbs_g), 1) AS carbs_g,
                  ROUND(SUM(fat_g), 1) AS fat_g,
                  COUNT(*) AS entries
           FROM food_logs
           WHERE user_id = ? AND log_date BETWEEN ? AND ?
           GROUP BY log_date ORDER BY log_date""",
        (user_id, start_date, end_date),
    )


def export_rows(user_id: int) -> list[dict]:
    return query(
        f"SELECT {LOG_COLUMNS} FROM food_logs WHERE user_id = ? ORDER BY log_date DESC, logged_at DESC",
        (user_id,),
    )


# ---------------------------------------------------------------- favoriler


def list_favorites(user_id: int, limit: int = 12) -> list[dict]:
    return query(
        "SELECT * FROM favorites WHERE user_id = ? ORDER BY use_count DESC, last_used_at DESC LIMIT ?",
        (user_id, limit),
    )


def save_favorite(user_id: int, item: dict) -> None:
    name = item.get("food_name") or "Bilinmeyen"
    existing = query_one("SELECT id, use_count FROM favorites WHERE user_id = ? AND food_name = ?", (user_id, name))
    now_iso = nutrition.now().isoformat()
    if existing:
        _execute(
            """UPDATE favorites SET grams = ?, calories = ?, protein_g = ?, carbs_g = ?, fat_g = ?,
               use_count = use_count + 1, last_used_at = ? WHERE id = ?""",
            (item.get("grams"), float(item.get("calories") or 0), float(item.get("protein_g") or 0),
             float(item.get("carbs_g") or 0), float(item.get("fat_g") or 0), now_iso, existing["id"]),
        )
    else:
        _execute(
            """INSERT INTO favorites (user_id, food_name, grams, calories, protein_g, carbs_g, fat_g,
               use_count, last_used_at) VALUES (?,?,?,?,?,?,?,1,?)""",
            (user_id, name, item.get("grams"), float(item.get("calories") or 0),
             float(item.get("protein_g") or 0), float(item.get("carbs_g") or 0),
             float(item.get("fat_g") or 0), now_iso),
        )
    _commit()


def touch_favorite(fav_id: int) -> None:
    _execute("UPDATE favorites SET use_count = use_count + 1, last_used_at = ? WHERE id = ?",
             (nutrition.now().isoformat(), fav_id))
    _commit()


def delete_favorite(fav_id: int, user_id: int) -> None:
    _execute("DELETE FROM favorites WHERE id = ? AND user_id = ?", (fav_id, user_id))
    _commit()


if __name__ == "__main__":
    init_db()
    print(health())
