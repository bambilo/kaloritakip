"""Kalori Takip — kamera ile AI destekli günlük besin takibi."""

from __future__ import annotations

import uuid

import altair as alt
import pandas as pd
import streamlit as st

import ai
import auth
import db
import nutrition

st.set_page_config(
    page_title="Kalori Takip",
    page_icon="🥗",
    layout="centered",
    initial_sidebar_state="collapsed",
)

ACCENT = "#2E9E5B"
MUTED = "#8A9691"
CAMERA_TIP = "📸 Daha doğru tahmin için tabağın yanına bir bardak veya çatal koyun."
MACRO_FIELDS = [("protein_g", "Protein"), ("carbs_g", "Karbonhidrat"), ("fat_g", "Yağ")]


@st.cache_resource
def _bootstrap() -> bool:
    db.init_db()
    return True


# --------------------------------------------------------------------- oturum


def _auto_login() -> None:
    """URL'deki hatirlama tokeni ile otomatik giris (telefonda ana ekran kisayolu)."""
    if st.session_state.get("user") or st.session_state.get("token_checked"):
        return
    st.session_state["token_checked"] = True
    token = st.query_params.get("t")
    if token:
        user = auth.user_from_token(token)
        if user:
            st.session_state["user"] = user
        else:
            st.query_params.pop("t", None)


def _logout() -> None:
    user = st.session_state.get("user")
    if user:
        auth.clear_remember_token(user["id"])
    st.query_params.pop("t", None)
    for key in list(st.session_state.keys()):
        del st.session_state[key]
    st.rerun()


def render_login() -> None:
    st.title("🥗 Kalori Takip")
    st.caption("Fotoğraftan kalori tahmini ve günlük besin takibi")

    users = db.list_users()
    tab_login, tab_new = st.tabs(["Giriş", "Yeni profil"])

    with tab_login:
        if not users:
            st.info("Henüz profil yok. **Yeni profil** sekmesinden başlayın.")
        else:
            names = {u["name"]: u["id"] for u in users}
            with st.form("login_form"):
                name = st.selectbox("Profil", list(names))
                pin = st.text_input("PIN", type="password", max_chars=12)
                remember = st.checkbox("Bu cihazda beni hatırla (30 gün)", value=True)
                if st.form_submit_button("Giriş yap", type="primary", width="stretch"):
                    try:
                        user = auth.login(names[name], pin)
                    except auth.AuthError as exc:
                        st.error(str(exc))
                    else:
                        st.session_state["user"] = user
                        if remember:
                            st.query_params["t"] = auth.issue_remember_token(user["id"])
                        st.rerun()

    with tab_new:
        with st.form("new_profile_form"):
            new_name = st.text_input("İsim", max_chars=30)
            new_pin = st.text_input("PIN (en az 4 rakam)", type="password", max_chars=12)
            new_pin2 = st.text_input("PIN tekrar", type="password", max_chars=12)
            if st.form_submit_button("Profil oluştur", type="primary", width="stretch"):
                if new_pin != new_pin2:
                    st.error("PIN'ler eşleşmiyor.")
                else:
                    try:
                        user_id = auth.create_profile(new_name, new_pin)
                    except auth.AuthError as exc:
                        st.error(str(exc))
                    else:
                        st.session_state["user"] = {"id": user_id, "name": new_name.strip()}
                        st.success("Profil oluşturuldu.")
                        st.rerun()


# ---------------------------------------------------------------- hedefler


def _goals(user_id: int) -> dict:
    profile = db.get_profile(user_id)
    return {
        "calorie_goal": float(profile.get("calorie_goal") or 2000),
        "protein_goal_g": float(profile.get("protein_goal_g") or 100),
        "carbs_goal_g": float(profile.get("carbs_goal_g") or 250),
        "fat_goal_g": float(profile.get("fat_goal_g") or 65),
        "is_default": profile.get("calorie_goal") is None,
    }


# ------------------------------------------------------- bekleyen analiz kartı


def _new_item(**overrides) -> dict:
    item = {
        "uid": uuid.uuid4().hex[:8],
        "food_name": "",
        "portion_desc": "",
        "grams": 100.0,
        "calories": 0.0,
        "protein_g": 0.0,
        "carbs_g": 0.0,
        "fat_g": 0.0,
        "confidence": None,
        "manual_kcal": False,
    }
    item.update(overrides)
    return item


def _init_item_state(item: dict) -> None:
    """Widget degerlerini session_state'e bir kez yaz (value= kullanmadan)."""
    uid = item["uid"]
    st.session_state.setdefault(f"n_{uid}", item["food_name"])
    st.session_state.setdefault(f"g_{uid}", float(item["grams"] or 0))
    st.session_state.setdefault(f"kcal_{uid}", float(item["calories"] or 0))
    for field, _ in MACRO_FIELDS:
        st.session_state.setdefault(f"{field}_{uid}", float(item[field] or 0))


def _clear_item_state(uid: str) -> None:
    for prefix in ("n_", "g_", "kcal_", "protein_g_", "carbs_g_", "fat_g_"):
        st.session_state.pop(f"{prefix}{uid}", None)


def _pending_item(uid: str) -> dict | None:
    for item in st.session_state.get("pending", {}).get("items", []):
        if item["uid"] == uid:
            return item
    return None


def _on_grams_change(uid: str) -> None:
    """Gramaj degisince kalori ve makrolari orantili guncelle."""
    item = _pending_item(uid)
    if item is None:
        return
    new_grams = float(st.session_state[f"g_{uid}"])
    if item.get("manual_kcal"):
        item["grams"] = new_grams
    else:
        item.update(nutrition.scale_item(item, new_grams))
        st.session_state[f"kcal_{uid}"] = float(item["calories"])
        for field, _ in MACRO_FIELDS:
            st.session_state[f"{field}_{uid}"] = float(item[field])
    st.session_state["pending"]["edited"] = True


def _on_field_change(uid: str, field: str, state_key: str) -> None:
    item = _pending_item(uid)
    if item is None:
        return
    item[field] = st.session_state[state_key]
    if field == "calories":
        item["manual_kcal"] = True  # elle kalori yazildi, oranlama durur
    st.session_state["pending"]["edited"] = True


def _remove_item(uid: str) -> None:
    pending = st.session_state.get("pending")
    if not pending:
        return
    pending["items"] = [i for i in pending["items"] if i["uid"] != uid]
    pending["edited"] = True
    _clear_item_state(uid)


def _add_blank_item() -> None:
    pending = st.session_state.setdefault("pending", {"items": [], "meta": {}, "thumb": None})
    pending["items"].append(_new_item(manual_kcal=True))
    pending["edited"] = True


def _clear_pending() -> None:
    pending = st.session_state.pop("pending", None)
    if pending:
        for item in pending.get("items", []):
            _clear_item_state(item["uid"])


CONFIDENCE_BADGE = {"yuksek": "🟢 yüksek güven", "orta": "🟡 orta güven", "dusuk": "🔴 düşük güven"}


def render_pending_card(user_id: int) -> None:
    pending = st.session_state.get("pending")
    if not pending:
        return

    meta = pending.get("meta", {})
    st.subheader("Tahmin sonucu")

    if meta.get("reference_objects"):
        refs = ", ".join(f"**{r['nesne']}** ({r['varsayilan_olcu']})" for r in meta["reference_objects"])
        st.success(f"📏 Referans alınan nesneler: {refs}")
    elif meta.get("from_ai"):
        st.warning("📏 Kadrajda referans nesne bulunamadı — tahmin daha kaba olabilir.")

    if meta.get("scale_reasoning"):
        with st.expander("Tahmin nasıl yapıldı?", expanded=False):
            st.write(meta["scale_reasoning"])

    for warning in meta.get("uyarilar", []):
        st.caption(f"⚠️ {warning}")

    if not pending["items"]:
        st.info("Kalem kalmadı. Aşağıdan yeni kalem ekleyebilir veya vazgeçebilirsiniz.")

    for item in pending["items"]:
        uid = item["uid"]
        _init_item_state(item)
        title = item["food_name"] or "Yeni kalem"
        badge = CONFIDENCE_BADGE.get(item.get("confidence") or "", "")
        with st.expander(f"{title} · {item['calories']:.0f} kcal  {badge}", expanded=True):
            st.text_input("Yemek", key=f"n_{uid}",
                          on_change=_on_field_change, args=(uid, "food_name", f"n_{uid}"))
            if item.get("portion_desc"):
                st.caption(f"Modelin porsiyon tarifi: {item['portion_desc']}")

            col1, col2 = st.columns(2)
            with col1:
                st.number_input("Gramaj (g)", min_value=0.0, step=10.0, key=f"g_{uid}",
                                on_change=_on_grams_change, args=(uid,),
                                help="Gramajı değiştirince kalori ve makrolar orantılı güncellenir.")
            with col2:
                st.number_input("Kalori (kcal)", min_value=0.0, step=10.0, key=f"kcal_{uid}",
                                on_change=_on_field_change, args=(uid, "calories", f"kcal_{uid}"))

            macro_cols = st.columns(3)
            for col, (field, label) in zip(macro_cols, MACRO_FIELDS):
                with col:
                    st.number_input(f"{label} (g)", min_value=0.0, step=1.0, key=f"{field}_{uid}",
                                    on_change=_on_field_change, args=(uid, field, f"{field}_{uid}"))

            st.button("🗑️ Bu kalemi çıkar", key=f"del_{uid}", on_click=_remove_item, args=(uid,))

    total = nutrition.sum_macros(pending["items"])
    st.markdown(
        f"**Toplam:** {total['calories']:.0f} kcal · P {total['protein_g']:.0f} g · "
        f"K {total['carbs_g']:.0f} g · Y {total['fat_g']:.0f} g"
    )

    meal_type = st.selectbox(
        "Öğün", nutrition.MEAL_TYPES,
        index=nutrition.MEAL_TYPES.index(pending.get("meal_type", nutrition.suggest_meal_type())),
        format_func=lambda m: nutrition.MEAL_LABELS[m],
        key="pending_meal_type",
    )
    save_favorite = st.checkbox("Bu kalemleri favorilere de ekle", value=False)

    col_save, col_add, col_cancel = st.columns([2, 1, 1])
    with col_save:
        if st.button("✅ Bugünüme Ekle", type="primary", width="stretch", disabled=not pending["items"]):
            log_meta = {
                "was_edited": pending.get("edited", False),
                "ai_model": meta.get("model"),
                "reference_objects": meta.get("reference_objects"),
                "scale_reasoning": meta.get("scale_reasoning"),
                "raw_json": meta.get("raw_json"),
            }
            thumb = pending.get("thumb")
            for index, item in enumerate(pending["items"]):
                db.add_log(
                    user_id, item, meal_type,
                    source=meta.get("source", "ai"),
                    thumb=thumb if index == 0 else None,
                    meta={**log_meta, "ai_confidence": item.get("confidence")},
                )
                if save_favorite:
                    db.save_favorite(user_id, item)
            _clear_pending()
            st.toast(f"{total['calories']:.0f} kcal günlüğüne eklendi 🎉", icon="✅")
            st.rerun()
    with col_add:
        st.button("➕ Kalem", width="stretch", on_click=_add_blank_item)
    with col_cancel:
        if st.button("Vazgeç", width="stretch"):
            _clear_pending()
            st.rerun()


# ---------------------------------------------------------------- Ekle sekmesi


def tab_add(user_id: int) -> None:
    st.info(CAMERA_TIP)

    if "pending" not in st.session_state:
        source_tab, upload_tab = st.tabs(["📷 Kamera", "🖼️ Fotoğraf yükle"])
        with source_tab:
            shot = st.camera_input("Yemeğin fotoğrafını çek", label_visibility="collapsed")
        with upload_tab:
            upload = st.file_uploader("Galeriden seç", type=["jpg", "jpeg", "png", "webp", "heic"],
                                      label_visibility="collapsed")

        raw = None
        if shot is not None:
            raw = shot.getvalue()
        elif upload is not None:
            raw = upload.getvalue()

        note = st.text_input("İsteğe bağlı not (modele ipucu)", placeholder="örn. tabak 20 cm, yağsız pişti")

        if raw and st.button("🔍 Analiz et", type="primary", width="stretch"):
            model = st.session_state.get("model", ai.DEFAULT_MODEL)
            with st.spinner("Fotoğraf analiz ediliyor..."):
                try:
                    analysis, raw_json = ai.analyze_image(raw, model=model, note=note)
                except ai.AIError as exc:
                    st.error(str(exc))
                    return
            if not analysis.is_food:
                st.error("Fotoğrafta yiyecek bulunamadı. " + " ".join(analysis.uyarilar))
                return

            st.session_state["pending"] = {
                "items": [_new_item(**item) for item in ai.to_ui_items(analysis)],
                "meta": {
                    "from_ai": True,
                    "source": "ai",
                    "model": model,
                    "reference_objects": [r.model_dump() for r in analysis.reference_objects],
                    "scale_reasoning": analysis.scale_reasoning,
                    "uyarilar": analysis.uyarilar + ([analysis.foto_ipucu] if analysis.foto_ipucu else []),
                    "raw_json": raw_json,
                },
                "thumb": ai.make_thumbnail(raw),
                "meal_type": nutrition.suggest_meal_type(),
                "edited": False,
            }
            st.rerun()
    else:
        render_pending_card(user_id)

    if "pending" not in st.session_state:
        _render_quick_add(user_id)


def _render_quick_add(user_id: int) -> None:
    st.divider()

    favorites = db.list_favorites(user_id)
    if favorites:
        st.markdown("**⭐ Favoriler** — tek dokunuşla bugüne ekle")
        for row in favorites:
            label = f"{row['food_name']} · {row['calories']:.0f} kcal"
            if st.button(label, key=f"fav_{row['id']}", width="stretch"):
                db.add_log(user_id, dict(row), nutrition.suggest_meal_type(), source="favorite")
                db.touch_favorite(row["id"])
                st.toast(f"{row['food_name']} eklendi", icon="⭐")
                st.rerun()

    with st.expander("✍️ Fotoğrafsız elle ekle"):
        with st.form("manual_form", clear_on_submit=True):
            name = st.text_input("Yemek adı")
            col1, col2 = st.columns(2)
            grams = col1.number_input("Gramaj (g)", min_value=0.0, step=10.0, value=100.0)
            calories = col2.number_input("Kalori (kcal)", min_value=0.0, step=10.0, value=0.0)
            col3, col4, col5 = st.columns(3)
            protein = col3.number_input("Protein (g)", min_value=0.0, step=1.0, value=0.0)
            carbs = col4.number_input("Karb. (g)", min_value=0.0, step=1.0, value=0.0)
            fat = col5.number_input("Yağ (g)", min_value=0.0, step=1.0, value=0.0)
            meal = st.selectbox("Öğün", nutrition.MEAL_TYPES,
                                index=nutrition.MEAL_TYPES.index(nutrition.suggest_meal_type()),
                                format_func=lambda m: nutrition.MEAL_LABELS[m])
            as_favorite = st.checkbox("Favorilere ekle")
            if st.form_submit_button("Bugüne ekle", type="primary", width="stretch"):
                if not name.strip():
                    st.error("Yemek adı gerekli.")
                elif calories <= 0:
                    st.error("Kalori 0'dan büyük olmalı.")
                else:
                    item = {"food_name": name.strip(), "grams": grams, "calories": calories,
                            "protein_g": protein, "carbs_g": carbs, "fat_g": fat}
                    db.add_log(user_id, item, meal, source="manual")
                    if as_favorite:
                        db.save_favorite(user_id, item)
                    st.toast(f"{name} eklendi", icon="✅")
                    st.rerun()


# --------------------------------------------------------------- Bugün sekmesi


def _progress_block(totals: dict, goals: dict) -> None:
    consumed = totals["calories"]
    goal = goals["calorie_goal"]
    remaining = goal - consumed

    col1, col2 = st.columns(2)
    col1.metric("Bugün alınan", f"{consumed:.0f} kcal", border=True)
    col2.metric("Kalan" if remaining >= 0 else "Aşım",
                f"{abs(remaining):.0f} kcal",
                delta=f"hedef {goal:.0f}", delta_color="off", border=True)

    ratio = min(consumed / goal, 1.0) if goal else 0.0
    st.progress(ratio, text=f"Kalori: {consumed:.0f} / {goal:.0f} kcal (%{consumed / goal * 100:.0f})"
                if goal else "Kalori hedefi tanımsız")
    if remaining < 0:
        st.caption(f"⚠️ Günlük hedefi {abs(remaining):.0f} kcal aştın.")

    macro_cols = st.columns(3)
    for col, (field, label) in zip(macro_cols, MACRO_FIELDS):
        goal_value = goals[f"{field[:-2]}_goal_g"]
        with col:
            value = totals[field]
            st.progress(min(value / goal_value, 1.0) if goal_value else 0.0,
                        text=f"{label} {value:.0f}/{goal_value:.0f} g")


def _render_log_rows(user_id: int, rows: list[dict], editable: bool = True, scope: str = "today") -> None:
    """scope: ayni gun birden fazla sekmede render edilebildigi icin widget key oneki."""
    by_meal: dict[str, list[dict]] = {}
    for row in rows:
        by_meal.setdefault(row["meal_type"], []).append(row)

    for meal in nutrition.MEAL_TYPES:
        meal_rows = by_meal.get(meal)
        if not meal_rows:
            continue
        meal_total = nutrition.sum_macros(meal_rows)
        st.markdown(f"##### {nutrition.MEAL_LABELS[meal]} · {meal_total['calories']:.0f} kcal")
        for row in meal_rows:
            grams_text = f"{row['grams']:.0f} g · " if row["grams"] else ""
            header = f"{row['food_name']} — {grams_text}{row['calories']:.0f} kcal"
            with st.expander(header):
                st.caption(
                    f"P {row['protein_g']:.0f} g · K {row['carbs_g']:.0f} g · Y {row['fat_g']:.0f} g"
                    + (f" · {row['portion_desc']}" if row["portion_desc"] else "")
                )
                if row["scale_reasoning"]:
                    st.caption(f"📏 {row['scale_reasoning']}")
                thumb = db.get_log_image(row["id"])
                if thumb:
                    st.image(thumb, width=220)
                if not editable:
                    continue

                col1, col2 = st.columns(2)
                new_grams = col1.number_input("Gramaj (g)", min_value=0.0, step=10.0,
                                              value=float(row["grams"] or 0), key=f"{scope}_eg_{row['id']}")
                new_cal = col2.number_input("Kalori (kcal)", min_value=0.0, step=10.0,
                                            value=float(row["calories"]), key=f"{scope}_ec_{row['id']}")
                col_save, col_del = st.columns(2)
                if col_save.button("Kaydet", key=f"{scope}_save_{row['id']}", width="stretch"):
                    updates = {"calories": new_cal, "grams": new_grams}
                    if new_grams and row["grams"] and new_cal == row["calories"]:
                        # sadece gramaj degistiyse makrolari da orantila
                        updates = nutrition.scale_item(dict(row), new_grams)
                        updates = {k: updates[k] for k in ("grams", "calories", "protein_g", "carbs_g", "fat_g")}
                    db.update_log(row["id"], user_id, **updates)
                    st.toast("Güncellendi", icon="✏️")
                    st.rerun()

                confirm_key = f"{scope}_confirm_del_{row['id']}"
                if st.session_state.get(confirm_key):
                    if col_del.button("Silinsin mi? Evet", key=f"{scope}_yes_{row['id']}",
                                      type="primary", width="stretch"):
                        db.delete_log(row["id"], user_id)
                        st.session_state.pop(confirm_key, None)
                        st.toast("Kayıt silindi", icon="🗑️")
                        st.rerun()
                elif col_del.button("🗑️ Sil", key=f"{scope}_del_log_{row['id']}", width="stretch"):
                    st.session_state[confirm_key] = True
                    st.rerun()


def tab_today(user_id: int) -> None:
    goals = _goals(user_id)
    rows = db.get_logs(user_id, nutrition.date_str())
    totals = nutrition.sum_macros(rows)

    st.subheader(f"Bugün · {nutrition.today().strftime('%d.%m.%Y')}")
    if goals["is_default"]:
        st.caption("⚙️ Hedefler varsayılan. **Profil** sekmesinden kendi hedefini hesaplat.")

    _progress_block(totals, goals)
    st.divider()

    if not rows:
        st.info("Bugün henüz kayıt yok. **Ekle** sekmesinden fotoğraf çekerek başla.")
        return
    _render_log_rows(user_id, rows)


# -------------------------------------------------------------- Geçmiş sekmesi


def _calorie_chart(frame: pd.DataFrame, goal: float) -> alt.LayerChart:
    """Gunluk kalori sutunlari + hedef referans cizgisi (tek seri, tek renk)."""
    bars = (
        alt.Chart(frame)
        .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4, color=ACCENT, size=18)
        .encode(
            x=alt.X("gun:O", title=None, axis=alt.Axis(labelAngle=0, labelColor=MUTED,
                                                       domainColor=MUTED, ticks=False)),
            y=alt.Y("kalori:Q", title="kcal",
                    axis=alt.Axis(grid=True, gridColor="#EDF1EE", labelColor=MUTED,
                                  titleColor=MUTED, domain=False, ticks=False)),
            tooltip=[
                alt.Tooltip("tarih:N", title="Tarih"),
                alt.Tooltip("kalori:Q", title="Kalori", format=".0f"),
                alt.Tooltip("protein_g:Q", title="Protein (g)", format=".0f"),
                alt.Tooltip("carbs_g:Q", title="Karbonhidrat (g)", format=".0f"),
                alt.Tooltip("fat_g:Q", title="Yağ (g)", format=".0f"),
            ],
        )
    )
    goal_line = (
        alt.Chart(pd.DataFrame({"hedef": [goal]}))
        .mark_rule(color="#4A5551", strokeDash=[6, 4], size=2)
        .encode(y="hedef:Q", tooltip=alt.Tooltip("hedef:Q", title="Günlük hedef", format=".0f"))
    )
    return (bars + goal_line).properties(height=240).configure_view(strokeWidth=0)


def tab_history(user_id: int) -> None:
    goals = _goals(user_id)

    st.subheader("Geçmiş")
    window = st.radio("Aralık", [7, 30], horizontal=True,
                      format_func=lambda n: f"Son {n} gün", label_visibility="collapsed")

    days = nutrition.last_n_days(window)
    totals_by_date = {row["log_date"]: row for row in
                      db.daily_totals(user_id, days[0].isoformat(), days[-1].isoformat())}

    frame = pd.DataFrame([
        {
            "tarih": day.strftime("%d.%m.%Y"),
            "gun": day.strftime("%d.%m") if window == 7 else day.strftime("%d"),
            "kalori": float(totals_by_date.get(day.isoformat(), {}).get("calories") or 0),
            "protein_g": float(totals_by_date.get(day.isoformat(), {}).get("protein_g") or 0),
            "carbs_g": float(totals_by_date.get(day.isoformat(), {}).get("carbs_g") or 0),
            "fat_g": float(totals_by_date.get(day.isoformat(), {}).get("fat_g") or 0),
        }
        for day in days
    ])

    logged = frame[frame["kalori"] > 0]
    st.markdown(f"**Günlük kalori** — kesikli çizgi {goals['calorie_goal']:.0f} kcal hedefi")
    st.altair_chart(_calorie_chart(frame, goals["calorie_goal"]), width="stretch", theme=None)

    col1, col2, col3 = st.columns(3)
    col1.metric("Kayıtlı gün", f"{len(logged)}/{window}", border=True)
    col2.metric("Ortalama", f"{logged['kalori'].mean():.0f} kcal" if len(logged) else "—", border=True)
    on_target = int((logged["kalori"] <= goals["calorie_goal"]).sum()) if len(logged) else 0
    col3.metric("Hedefte gün", f"{on_target}", border=True)

    with st.expander("Tablo görünümü"):
        st.dataframe(
            frame.rename(columns={"tarih": "Tarih", "kalori": "Kalori", "protein_g": "Protein (g)",
                                  "carbs_g": "Karbonhidrat (g)", "fat_g": "Yağ (g)"})
            .drop(columns=["gun"]).iloc[::-1],
            hide_index=True, width="stretch",
        )

    st.divider()
    selected = st.date_input("Bir günü aç", value=nutrition.today(),
                             max_value=nutrition.today(), format="DD.MM.YYYY")
    rows = db.get_logs(user_id, selected.isoformat())
    if not rows:
        st.info("Bu günde kayıt yok.")
    else:
        day_totals = nutrition.sum_macros(rows)
        st.markdown(
            f"**{selected.strftime('%d.%m.%Y')}** · {day_totals['calories']:.0f} kcal · "
            f"P {day_totals['protein_g']:.0f} g · K {day_totals['carbs_g']:.0f} g · Y {day_totals['fat_g']:.0f} g"
        )
        _render_log_rows(user_id, rows, editable=selected == nutrition.today(), scope="hist")


# --------------------------------------------------------------- Profil sekmesi


def tab_profile(user_id: int) -> None:
    profile = db.get_profile(user_id)
    st.subheader("Profil ve hedefler")

    with st.form("profile_form"):
        col1, col2 = st.columns(2)
        sex = col1.selectbox("Cinsiyet", list(nutrition.SEX_LABELS),
                             index=list(nutrition.SEX_LABELS).index(profile.get("sex") or "kadin"),
                             format_func=lambda s: nutrition.SEX_LABELS[s])
        age = col2.number_input("Yaş", min_value=10, max_value=100, step=1,
                                value=int(profile.get("age") or 30))
        col3, col4 = st.columns(2)
        height = col3.number_input("Boy (cm)", min_value=100.0, max_value=230.0, step=1.0,
                                   value=float(profile.get("height_cm") or 170))
        weight = col4.number_input("Kilo (kg)", min_value=30.0, max_value=250.0, step=0.5,
                                   value=float(profile.get("weight_kg") or 70))
        activity = st.selectbox("Aktivite düzeyi", list(nutrition.ACTIVITY_LABELS),
                                index=list(nutrition.ACTIVITY_LABELS).index(
                                    profile.get("activity_level") or "hafif"),
                                format_func=lambda a: nutrition.ACTIVITY_LABELS[a])
        goal_type = st.selectbox("Hedef", list(nutrition.GOAL_LABELS),
                                 index=list(nutrition.GOAL_LABELS).index(profile.get("goal_type") or "koru"),
                                 format_func=lambda g: nutrition.GOAL_LABELS[g])

        manual = st.checkbox("Hedefleri elle gireceğim", value=bool(profile.get("goals_are_manual")))
        manual_calories = st.number_input("Günlük kalori hedefi (kcal)", min_value=1000.0, step=50.0,
                                          value=float(profile.get("calorie_goal") or 2000))
        col5, col6, col7 = st.columns(3)
        manual_protein = col5.number_input("Protein (g)", min_value=0.0, step=5.0,
                                           value=float(profile.get("protein_goal_g") or 100))
        manual_carbs = col6.number_input("Karb. (g)", min_value=0.0, step=5.0,
                                         value=float(profile.get("carbs_goal_g") or 250))
        manual_fat = col7.number_input("Yağ (g)", min_value=0.0, step=5.0,
                                       value=float(profile.get("fat_goal_g") or 65))
        st.caption("Elle giriş kapalıysa hedefler Mifflin-St Jeor formülüyle hesaplanır.")

        if st.form_submit_button("Kaydet", type="primary", width="stretch"):
            fields = {"sex": sex, "age": int(age), "height_cm": float(height),
                      "weight_kg": float(weight), "activity_level": activity,
                      "goal_type": goal_type, "goals_are_manual": 1 if manual else 0}
            if manual:
                fields.update(calorie_goal=float(manual_calories), protein_goal_g=float(manual_protein),
                              carbs_goal_g=float(manual_carbs), fat_goal_g=float(manual_fat))
            else:
                fields.update(nutrition.calculate_goals(sex, int(age), float(height),
                                                        float(weight), activity, goal_type))
            db.save_profile(user_id, **fields)
            st.success("Hedefler kaydedildi.")
            st.rerun()

    goals = _goals(user_id)
    bmr = nutrition.bmr_mifflin(profile.get("sex") or "kadin", int(profile.get("age") or 30),
                                float(profile.get("height_cm") or 170), float(profile.get("weight_kg") or 70))
    st.caption(f"BMR ≈ {bmr:.0f} kcal · Günlük hedef {goals['calorie_goal']:.0f} kcal · "
               f"P {goals['protein_goal_g']:.0f} g / K {goals['carbs_goal_g']:.0f} g / Y {goals['fat_goal_g']:.0f} g")

    st.divider()
    with st.expander("🔐 PIN değiştir"):
        with st.form("pin_form", clear_on_submit=True):
            old_pin = st.text_input("Mevcut PIN", type="password")
            new_pin = st.text_input("Yeni PIN", type="password")
            new_pin2 = st.text_input("Yeni PIN tekrar", type="password")
            if st.form_submit_button("Değiştir", width="stretch"):
                if new_pin != new_pin2:
                    st.error("Yeni PIN'ler eşleşmiyor.")
                else:
                    try:
                        auth.change_pin(user_id, old_pin, new_pin)
                    except auth.AuthError as exc:
                        st.error(str(exc))
                    else:
                        st.success("PIN değiştirildi. Tekrar giriş yapmanız gerekecek.")

    rows = db.export_rows(user_id)
    if rows:
        csv = pd.DataFrame(rows).to_csv(index=False).encode("utf-8-sig")
        st.download_button("⬇️ Kayıtlarımı CSV indir", csv,
                           file_name=f"kaloritakip-{nutrition.date_str()}.csv",
                           mime="text/csv", width="stretch")


# ------------------------------------------------------------------------ main


def render_sidebar(user: dict) -> None:
    with st.sidebar:
        st.markdown(f"### 👤 {user['name']}")
        goals = _goals(user["id"])
        totals = nutrition.sum_macros(db.get_logs(user["id"], nutrition.date_str()))
        st.metric("Bugün", f"{totals['calories']:.0f} / {goals['calorie_goal']:.0f} kcal")

        st.selectbox("Model", ai.AVAILABLE_MODELS,
                     index=ai.AVAILABLE_MODELS.index(st.session_state.get("model", ai.DEFAULT_MODEL)),
                     key="model", help="Analiz için kullanılacak Gemini modeli")
        st.caption(ai.MODEL_NOTES[st.session_state.get("model", ai.DEFAULT_MODEL)])

        st.divider()
        st.caption(f"Veri: {'Turso (bulut)' if db.is_remote() else 'yerel SQLite'}")
        if st.button("Çıkış yap", width="stretch"):
            _logout()


def main() -> None:
    _bootstrap()
    _auto_login()

    user = st.session_state.get("user")
    if not user:
        render_login()
        return

    render_sidebar(user)
    st.title("🥗 Kalori Takip")
    tabs = st.tabs(["📷 Ekle", "📊 Bugün", "📈 Geçmiş", "⚙️ Profil"])
    with tabs[0]:
        tab_add(user["id"])
    with tabs[1]:
        tab_today(user["id"])
    with tabs[2]:
        tab_history(user["id"])
    with tabs[3]:
        tab_profile(user["id"])


main()
