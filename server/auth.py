import os
import bcrypt
from functools import wraps
from flask import request, jsonify, session


def _get_hash(env_key: str) -> bytes | None:
    val = os.environ.get(env_key)
    return val.encode() if val else None


ADMIN_HASHES = {
    "admin": lambda: _get_hash("ADMIN_PASSWORD_HASH"),
    "dev":   lambda: _get_hash("DEV_PASSWORD_HASH"),
}


def check_password(username: str, password: str) -> bool:
    get_hash = ADMIN_HASHES.get(username)
    if not get_hash:
        return False
    stored = get_hash()
    if not stored:
        return False
    return bcrypt.checkpw(password.encode(), stored)


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("admin_user"):
            return jsonify({"error": "unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated
