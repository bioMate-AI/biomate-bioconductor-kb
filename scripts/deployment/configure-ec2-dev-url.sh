#!/usr/bin/env bash
set -euo pipefail

# Configure Nginx on EC2 so a dev URL serves BioMate frontend container.
#
# This script expects the frontend container to be reachable on localhost:5000
# (as defined in docker-compose.ec2.yml).
#
# Usage:
#   sudo bash scripts/deployment/configure-ec2-dev-url.sh --domain <dev-url> [--enable-ssl --email you@example.com]

usage() {
  cat <<'EOF'
Usage:
  configure-ec2-dev-url.sh --domain <dev-url> [--enable-ssl --email <email>]

Required:
  --domain      Dev URL / host name (for example dev-biomate.example.com)

Optional:
  --enable-ssl  Request Let's Encrypt cert and enable HTTPS redirect
  --email       Email used by certbot (required with --enable-ssl)
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command '$1'" >&2
    exit 1
  }
}

DOMAIN=""
ENABLE_SSL=false
EMAIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="$2"; shift 2 ;;
    --enable-ssl)
      ENABLE_SSL=true; shift ;;
    --email)
      EMAIL="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "ERROR: --domain is required" >&2
  usage
  exit 1
fi

if [[ "$ENABLE_SSL" == true && -z "$EMAIL" ]]; then
  echo "ERROR: --email is required when --enable-ssl is set" >&2
  exit 1
fi

require_cmd nginx
require_cmd curl

if ! command -v certbot >/dev/null 2>&1 && [[ "$ENABLE_SSL" == true ]]; then
  echo "==> Installing certbot"
  apt-get update
  apt-get install -y certbot python3-certbot-nginx
fi

NGINX_SITE="/etc/nginx/sites-available/biomate-dev.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/biomate-dev.conf"

echo "==> Writing nginx config for domain: ${DOMAIN}"
cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Proxy all traffic to BioMate frontend container
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300;
    }
}
EOF

ln -sfn "$NGINX_SITE" "$NGINX_ENABLED"
rm -f /etc/nginx/sites-enabled/default

echo "==> Validating nginx config"
nginx -t
systemctl restart nginx
systemctl enable nginx

echo "==> Verifying local proxy path"
curl -fsS -H "Host: ${DOMAIN}" http://127.0.0.1/ >/dev/null

if [[ "$ENABLE_SSL" == true ]]; then
  echo "==> Requesting Let's Encrypt certificate for ${DOMAIN}"
  certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" --redirect
  nginx -t
  systemctl reload nginx
fi

echo
echo "Dev URL configuration complete."
echo "  Domain: ${DOMAIN}"
echo "  Nginx site: ${NGINX_SITE}"
if [[ "$ENABLE_SSL" == true ]]; then
  echo "  TLS: enabled"
else
  echo "  TLS: not enabled (HTTP only)"
fi
