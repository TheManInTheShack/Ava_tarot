import json
from sessions import get_session, end_session, validate_guest_token

# Message protocol:
#   admin → server:  {"type": "state", "payload": {...}}   (broadcast to guest)
#   server → guest:  {"type": "state", "payload": {...}}   (mirror of admin state)
#   server → client: {"type": "error", "message": "..."}
#   server → client: {"type": "connected"}
#   server → client: {"type": "guest_joined"} / {"type": "guest_left"}


def _send(ws, msg: dict):
    try:
        ws.send(json.dumps(msg))
    except Exception:
        pass


def register_sockets(sock):

    @sock.route("/ws/admin/<session_id>")
    def admin_socket(ws, session_id):
        s = get_session(session_id)
        if s is None:
            _send(ws, {"type": "error", "message": "session not found"})
            return

        s["admin_ws"] = ws
        _send(ws, {"type": "connected", "role": "admin"})
        if s["guest_ws"]:
            _send(ws, {"type": "guest_joined"})

        try:
            while True:
                raw = ws.receive()
                if raw is None:
                    break
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue

                if msg.get("type") == "state":
                    s["state"] = msg.get("payload", {})
                    guest_ws = s.get("guest_ws")
                    if guest_ws:
                        _send(guest_ws, {"type": "state", "payload": s["state"]})
        finally:
            s["admin_ws"] = None
            # admin disconnect ends the session
            guest_ws = s.get("guest_ws")
            if guest_ws:
                _send(guest_ws, {"type": "error", "message": "admin disconnected"})
            end_session(session_id)

    @sock.route("/ws/guest/<session_id>")
    def guest_socket(ws, session_id):
        token = _get_query_param(ws, "token")
        if not validate_guest_token(session_id, token):
            _send(ws, {"type": "error", "message": "invalid token"})
            return

        s = get_session(session_id)
        if s is None:
            _send(ws, {"type": "error", "message": "session not found"})
            return

        s["guest_ws"] = ws
        _send(ws, {"type": "connected", "role": "guest"})

        # send current state snapshot immediately
        if s["state"]:
            _send(ws, {"type": "state", "payload": s["state"]})

        admin_ws = s.get("admin_ws")
        if admin_ws:
            _send(admin_ws, {"type": "guest_joined"})

        try:
            while True:
                raw = ws.receive()
                if raw is None:
                    break
                # guests are read-only; ignore all messages
        finally:
            s["guest_ws"] = None
            admin_ws = s.get("admin_ws")
            if admin_ws:
                _send(admin_ws, {"type": "guest_left"})


def _get_query_param(ws, param: str) -> str:
    """Extract a query parameter from the WebSocket's HTTP environ."""
    try:
        qs = ws.environ.get("QUERY_STRING", "")
        for part in qs.split("&"):
            if "=" in part:
                k, v = part.split("=", 1)
                if k == param:
                    return v
    except Exception:
        pass
    return ""
