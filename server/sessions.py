import secrets
import threading
import time

SESSION_TTL = 5 * 3600  # 5 hours

_sessions: dict = {}
_lock = threading.Lock()


def _cleanup_loop():
    while True:
        time.sleep(300)
        now = time.time()
        with _lock:
            expired = [sid for sid, s in _sessions.items() if now - s["created_at"] > SESSION_TTL]
            for sid in expired:
                _sessions.pop(sid, None)


threading.Thread(target=_cleanup_loop, daemon=True).start()


def create_session(admin_user: str) -> dict:
    """Create a new session for admin_user, replacing any existing one."""
    token = secrets.token_urlsafe(32)
    session_id = secrets.token_urlsafe(16)
    entry = {
        "session_id": session_id,
        "admin_user": admin_user,
        "token": token,
        "created_at": time.time(),
        "guest_ws": None,   # active guest WebSocket connection
        "admin_ws": None,   # active admin WebSocket connection
        "state": {},        # last broadcast state snapshot
    }
    with _lock:
        # expire any existing session for this user
        old = [sid for sid, s in _sessions.items() if s["admin_user"] == admin_user]
        for sid in old:
            _sessions.pop(sid, None)
        _sessions[session_id] = entry
    return entry


def get_session(session_id: str) -> dict | None:
    with _lock:
        s = _sessions.get(session_id)
        if s and time.time() - s["created_at"] <= SESSION_TTL:
            return s
        if s:
            _sessions.pop(session_id, None)
        return None


def get_session_by_user(admin_user: str) -> dict | None:
    with _lock:
        for s in _sessions.values():
            if s["admin_user"] == admin_user:
                return s
        return None


def end_session(session_id: str) -> None:
    with _lock:
        _sessions.pop(session_id, None)


def validate_guest_token(session_id: str, token: str) -> bool:
    s = get_session(session_id)
    return s is not None and s["token"] == token
