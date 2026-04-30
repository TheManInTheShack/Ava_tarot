from flask import Flask
from flask_sock import Sock

app = Flask(__name__)
app.secret_key = __import__("os").environ.get("FLASK_SECRET", "dev-secret-change-me")
sock = Sock(app)

from routes import register_routes
from sockets import register_sockets

register_routes(app)
register_sockets(sock)
