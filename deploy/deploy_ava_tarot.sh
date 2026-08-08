#!/bin/bash
# deploy_ava_tarot.sh
#
# Run on the droplet as the 'deploy' user AFTER provision_droplet.sh.
# Safe to re-run — it will update an existing deployment.
#
# Usage:
#   1. Copy this file to the droplet:
#      scp dev/bin/deploy_ava_tarot.sh deploy@<IP>:~
#   2. SSH in and run:
#      bash deploy_ava_tarot.sh
#
# Before running, edit the CONFIG section below.

set -euo pipefail

# ── CONFIG ────────────────────────────────────────────────────────────────────
DOMAIN="avareads.com"          # ← your domain (must point to this droplet)
REPO_URL="https://github.com/TheManInTheShack/ava_tarot.git"
APP_DIR="/srv/ava_tarot"
SERVER_DIR="${APP_DIR}/server"
STATIC_DIR="${APP_DIR}/export"    # ← Godot HTML5 export goes here
VENV_DIR="${APP_DIR}/venv"
SOCKET_PATH="/run/ava_tarot/ava_tarot.sock"
SERVICE_NAME="ava_tarot"
NGINX_CONF="/etc/nginx/sites-available/${SERVICE_NAME}"
CERTBOT_EMAIL="thmanintheshack@gmail.com"
# ─────────────────────────────────────────────────────────────────────────────

echo "==> [1/7] Clone or update repo"
if [ -d "${APP_DIR}/.git" ]; then
    git -C "${APP_DIR}" pull
else
    sudo git clone "${REPO_URL}" "${APP_DIR}"
    sudo chown -R deploy:deploy "${APP_DIR}"
fi

echo "==> [2/7] Python venv + dependencies"
python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install --quiet --upgrade pip
"${VENV_DIR}/bin/pip" install --quiet -r "${SERVER_DIR}/requirements.txt"

echo "==> [3/7] .env file"
ENV_FILE="${SERVER_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
    echo "  Creating blank .env — YOU MUST FILL THIS IN before starting the service."
    cat > "${ENV_FILE}" <<'EOF'
FLASK_SECRET=CHANGE_ME
ADMIN_PASSWORD_HASH=CHANGE_ME
DEV_PASSWORD_HASH=CHANGE_ME
WHEREBY_ROOM_URL=CHANGE_ME
EOF
    echo "  Edit ${ENV_FILE} now, then re-run this script (or: sudo systemctl start ${SERVICE_NAME})"
fi

echo "==> [4/7] systemd service"
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Ava Tarot Flask/gunicorn backend
After=network.target

[Service]
User=deploy
Group=deploy
WorkingDirectory=${SERVER_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_DIR}/bin/gunicorn \\
    --worker-class gevent \\
    --workers 1 \\
    --bind unix:${SOCKET_PATH} \\
    --umask 007 \\
    --log-level info \\
    --access-logfile /var/log/ava_tarot_access.log \\
    --error-logfile /var/log/ava_tarot_error.log \\
    wsgi:application
RuntimeDirectory=ava_tarot
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"
echo "  Service status:"
sudo systemctl is-active "${SERVICE_NAME}" && echo "  RUNNING" || echo "  FAILED — check: sudo journalctl -u ${SERVICE_NAME} -n 50"

echo "==> [5/7] Static export directory"
mkdir -p "${STATIC_DIR}"
echo "  Godot HTML5 export files go in: ${STATIC_DIR}"
echo "  (scp your export/ folder here when ready)"

echo "==> [6/7] nginx vhost"
sudo tee "${NGINX_CONF}" > /dev/null <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    # Godot PWA — requires COOP/COEP headers for SharedArrayBuffer
    root ${STATIC_DIR};
    index index.html;

    # Security headers for Godot 4 PWA
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    # Static PWA files
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Flask REST API
    location /api/ {
        proxy_pass http://unix:${SOCKET_PATH};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # WebSocket (flask-sock)
    location /ws/ {
        proxy_pass http://unix:${SOCKET_PATH};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

sudo ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/${SERVICE_NAME}
sudo nginx -t && sudo systemctl reload nginx

echo "==> [7/7] TLS certificate (Let's Encrypt)"
if sudo certbot certificates 2>/dev/null | grep -q "${DOMAIN}"; then
    echo "  Certificate already exists — skipping."
else
    sudo certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos \
        --email "${CERTBOT_EMAIL}" --redirect
fi

echo ""
echo "============================================"
echo "  Ava Tarot deployed."
echo "  Backend:  https://${DOMAIN}/api/"
echo "  Frontend: https://${DOMAIN}/"
echo ""
echo "  Next steps:"
echo "  1. Fill in ${ENV_FILE} if not done"
echo "  2. Upload Godot export to ${STATIC_DIR}/"
echo "     scp -r export/* deploy@${DOMAIN}:${STATIC_DIR}/"
echo "  3. sudo systemctl restart ${SERVICE_NAME}"
echo "============================================"
