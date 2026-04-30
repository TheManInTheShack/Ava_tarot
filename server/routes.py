import json
import os
from pathlib import Path
from flask import request, jsonify, session
from auth import check_password, login_required
from sessions import create_session, get_session, get_session_by_user, end_session
from readings import list_readings, get_reading, upsert_reading, delete_reading

DATA_DIR = Path(__file__).parent.parent / "Data"


def register_routes(app):

    @app.route("/api/login", methods=["POST"])
    def login():
        data = request.get_json(force=True)
        username = data.get("username", "")
        password = data.get("password", "")
        if not check_password(username, password):
            return jsonify({"error": "invalid credentials"}), 401
        session["admin_user"] = username
        return jsonify({"ok": True, "user": username})

    @app.route("/api/logout", methods=["POST"])
    @login_required
    def logout():
        user = session.pop("admin_user", None)
        s = get_session_by_user(user) if user else None
        if s:
            end_session(s["session_id"])
        return jsonify({"ok": True})

    @app.route("/api/session/start", methods=["POST"])
    @login_required
    def session_start():
        user = session["admin_user"]
        s = create_session(user)
        guest_url = f"?role=guest&session={s['session_id']}&token={s['token']}"
        call_url = os.environ.get("WHEREBY_ROOM_URL", "")
        return jsonify({"session_id": s["session_id"], "guest_url": guest_url, "call_url": call_url})

    @app.route("/api/session/end", methods=["POST"])
    @login_required
    def session_end():
        user = session["admin_user"]
        s = get_session_by_user(user)
        if s:
            end_session(s["session_id"])
        return jsonify({"ok": True})

    @app.route("/api/session/status", methods=["GET"])
    @login_required
    def session_status():
        user = session["admin_user"]
        s = get_session_by_user(user)
        if not s:
            return jsonify({"active": False})
        return jsonify({
            "active": True,
            "session_id": s["session_id"],
            "guest_connected": s["guest_ws"] is not None,
        })

    # ── Card data endpoints ───────────────────────────────────────────────────

    @app.route("/api/cards", methods=["GET"])
    @login_required
    def get_cards():
        return _read_json("cards.json")

    @app.route("/api/cards/<card_id>", methods=["GET"])
    @login_required
    def get_card(card_id):
        data = _read_json_raw("cards.json")
        node = data.get("nodes", {}).get(card_id)
        if node is None:
            return jsonify({"error": "not found"}), 404
        return jsonify(node)

    @app.route("/api/cards/<card_id>", methods=["PUT"])
    @login_required
    def update_card(card_id):
        updates = request.get_json(force=True)
        data = _read_json_raw("cards.json")
        if card_id not in data.get("nodes", {}):
            return jsonify({"error": "not found"}), 404
        data["nodes"][card_id].update(updates)
        _write_json("cards.json", data)
        return jsonify({"ok": True, "card_id": card_id})

    @app.route("/api/cards", methods=["POST"])
    @login_required
    def add_card():
        node = request.get_json(force=True)
        card_id = node.get("card_id") or node.get("id")
        if not card_id:
            return jsonify({"error": "card_id required"}), 400
        data = _read_json_raw("cards.json")
        data.setdefault("nodes", {})[card_id] = node
        _write_json("cards.json", data)
        return jsonify({"ok": True, "card_id": card_id}), 201

    @app.route("/api/edges", methods=["GET"])
    @login_required
    def get_edges():
        data = _read_json_raw("cards.json")
        return jsonify(data.get("edges", []))

    @app.route("/api/edges", methods=["POST"])
    @login_required
    def add_edge():
        edge = request.get_json(force=True)
        data = _read_json_raw("cards.json")
        data.setdefault("edges", []).append(edge)
        _write_json("cards.json", data)
        return jsonify({"ok": True}), 201

    @app.route("/api/edges/<int:index>", methods=["DELETE"])
    @login_required
    def delete_edge(index):
        data = _read_json_raw("cards.json")
        edges = data.get("edges", [])
        if index < 0 or index >= len(edges):
            return jsonify({"error": "not found"}), 404
        edges.pop(index)
        _write_json("cards.json", data)
        return jsonify({"ok": True})

    # ── Reading endpoints ─────────────────────────────────────────────────────

    @app.route("/api/readings", methods=["GET"])
    @login_required
    def get_readings():
        return jsonify(list_readings())

    @app.route("/api/readings/<reading_id>", methods=["GET"])
    @login_required
    def get_reading_route(reading_id):
        r = get_reading(reading_id)
        if r is None:
            return jsonify({"error": "not found"}), 404
        return jsonify(r)

    @app.route("/api/readings", methods=["POST"])
    @login_required
    def create_reading():
        reading = request.get_json(force=True)
        if not reading.get("reading_id"):
            return jsonify({"error": "reading_id required"}), 400
        return jsonify(upsert_reading(reading)), 201

    @app.route("/api/readings/<reading_id>", methods=["PUT"])
    @login_required
    def update_reading(reading_id):
        r = get_reading(reading_id)
        if r is None:
            return jsonify({"error": "not found"}), 404
        r.update(request.get_json(force=True))
        return jsonify(upsert_reading(r))

    @app.route("/api/readings/<reading_id>", methods=["DELETE"])
    @login_required
    def delete_reading_route(reading_id):
        if not delete_reading(reading_id):
            return jsonify({"error": "not found"}), 404
        return jsonify({"ok": True})

    # ── helpers ───────────────────────────────────────────────────────────────

    def _read_json(filename):
        path = DATA_DIR / filename
        with open(path, encoding="utf-8") as f:
            return jsonify(json.load(f))

    def _read_json_raw(filename):
        path = DATA_DIR / filename
        with open(path, encoding="utf-8") as f:
            return json.load(f)

    def _write_json(filename, data):
        path = DATA_DIR / filename
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
