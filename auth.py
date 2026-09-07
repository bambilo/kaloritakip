"""Profil olusturma, PIN dogrulama ve 'beni hatirla' token yonetimi."""

from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import timedelta

import db
import nutrition

PBKDF2_ROUNDS = 200_000
REMEMBER_DAYS = 30
MIN_PIN_LEN = 4


class AuthError(Exception):
    """Kullaniciya gosterilebilir kimlik dogrulama hatasi."""


def _hash_pin(pin: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", pin.encode(), bytes.fromhex(salt), PBKDF2_ROUNDS).hex()


def _hash_token(token: str) -> str:
    """Token DB'de duz saklanmaz; sadece SHA-256 ozeti tutulur."""
    return hashlib.sha256(token.encode()).hexdigest()


def _validate_pin(pin: str) -> None:
    if not pin or not pin.isdigit() or len(pin) < MIN_PIN_LEN:
        raise AuthError(f"PIN en az {MIN_PIN_LEN} haneli ve sadece rakamlardan oluşmalı.")


def create_profile(name: str, pin: str) -> int:
    name = (name or "").strip()
    if len(name) < 2:
        raise AuthError("İsim en az 2 karakter olmalı.")
    _validate_pin(pin)
    if db.get_user_by_name(name):
        raise AuthError(f"'{name}' adında bir profil zaten var.")
    salt = secrets.token_hex(16)
    return db.create_user(name, _hash_pin(pin, salt), salt)


def verify_pin(user_id: int, pin: str) -> bool:
    user = db.get_user(user_id)
    if not user:
        return False
    return hmac.compare_digest(_hash_pin(pin or "", user["pin_salt"]), user["pin_hash"])


def login(user_id: int, pin: str) -> dict:
    if not verify_pin(user_id, pin):
        raise AuthError("PIN hatalı.")
    user = db.get_user(user_id)
    return {"id": user["id"], "name": user["name"]}


def change_pin(user_id: int, old_pin: str, new_pin: str) -> None:
    if not verify_pin(user_id, old_pin):
        raise AuthError("Mevcut PIN hatalı.")
    _validate_pin(new_pin)
    salt = secrets.token_hex(16)
    db.update_pin(user_id, _hash_pin(new_pin, salt), salt)
    db.set_remember_token(user_id, None, None)  # eski oturumlari dusur


def issue_remember_token(user_id: int) -> str:
    """Yeni bir hatirlama tokeni uret, ozetini kaydet, tokenin kendisini dondur."""
    token = secrets.token_urlsafe(32)
    expires = (nutrition.now() + timedelta(days=REMEMBER_DAYS)).isoformat()
    db.set_remember_token(user_id, _hash_token(token), expires)
    return token


def user_from_token(token: str) -> dict | None:
    if not token:
        return None
    user = db.find_user_by_token_hash(_hash_token(token))
    return {"id": user["id"], "name": user["name"]} if user else None


def clear_remember_token(user_id: int) -> None:
    db.set_remember_token(user_id, None, None)
