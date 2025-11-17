#!/bin/bash
# Setup Let's Encrypt SSL Certificate for BioMate AI
# SOC 2 CC6.7 - Transmission Security
# HIPAA §164.312(e)(2)(ii) - Encryption
# Version: 1.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "BioMate SSL Certificate Setup"
echo "========================================="
echo ""

# Configuration
DOMAIN="${DOMAIN:-biomate.ai}"
DOMAIN_WWW="${DOMAIN_WWW:-www.biomate.ai}"
EMAIL="${SSL_EMAIL:-admin@biomate.ai}"
WEBROOT="${WEBROOT:-/var/www/letsencrypt}"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "Certbot not found. Installing..."
    apt update
    apt install -y certbot python3-certbot-nginx
fi

# Check DNS configuration
echo "Checking DNS configuration..."
CURRENT_IP=$(curl -s https://api.ipify.org)
DOMAIN_IP=$(dig +short $DOMAIN @8.8.8.8 | tail -n1)
DOMAIN_WWW_IP=$(dig +short $DOMAIN_WWW @8.8.8.8 | tail -n1)

echo "Server IP: $CURRENT_IP"
echo "$DOMAIN resolves to: $DOMAIN_IP"
echo "$DOMAIN_WWW resolves to: $DOMAIN_WWW_IP"
echo ""

if [[ "$CURRENT_IP" != "$DOMAIN_IP" ]]; then
    echo -e "${YELLOW}Warning: $DOMAIN does not resolve to this server${NC}"
    echo "Expected: $CURRENT_IP"
    echo "Got: $DOMAIN_IP"
    echo ""
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [[ "$CONTINUE" != "yes" ]]; then
        echo "Exiting. Please configure DNS first."
        exit 1
    fi
fi

# Create webroot directory
echo "Creating webroot directory..."
mkdir -p "$WEBROOT"
chmod 755 "$WEBROOT"

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "Nginx not found. Installing..."
    apt update
    apt install -y nginx
fi

# Create temporary nginx config for certificate verification
echo "Setting up temporary nginx configuration..."
cat > /etc/nginx/sites-available/temp-ssl-setup <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN $DOMAIN_WWW;

    root $WEBROOT;

    location /.well-known/acme-challenge/ {
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 200 "BioMate SSL Setup in Progress";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable temporary config
ln -sf /etc/nginx/sites-available/temp-ssl-setup /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
nginx -t

# Reload nginx
systemctl reload nginx

echo ""
echo "========================================="
echo "Obtaining SSL Certificate"
echo "========================================="
echo ""
echo "Domains: $DOMAIN, $DOMAIN_WWW"
echo "Email: $EMAIL"
echo "Webroot: $WEBROOT"
echo ""

# Check if certificate already exists
if [[ -d "$CERT_PATH" ]]; then
    echo -e "${YELLOW}Certificate already exists at $CERT_PATH${NC}"
    read -p "Renew certificate? (yes/no): " RENEW

    if [[ "$RENEW" == "yes" ]]; then
        echo "Renewing certificate..."
        certbot renew --force-renewal
    else
        echo "Using existing certificate"
    fi
else
    # Obtain new certificate
    echo "Obtaining new certificate from Let's Encrypt..."

    certbot certonly \
        --webroot \
        --webroot-path "$WEBROOT" \
        -d "$DOMAIN" \
        -d "$DOMAIN_WWW" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --verbose

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Certificate obtained successfully${NC}"
    else
        echo -e "${RED}✗ Failed to obtain certificate${NC}"
        echo "Check errors above and try again"
        exit 1
    fi
fi

# Verify certificate
echo ""
echo "========================================="
echo "Verifying Certificate"
echo "========================================="
echo ""

if [[ -f "$CERT_PATH/fullchain.pem" ]]; then
    echo -e "${GREEN}✓ Certificate found${NC}"

    # Display certificate info
    echo ""
    echo "Certificate Information:"
    openssl x509 -in "$CERT_PATH/fullchain.pem" -noout -subject -dates -issuer

    # Check expiration
    EXPIRY_DATE=$(openssl x509 -in "$CERT_PATH/fullchain.pem" -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

    echo ""
    echo "Days until expiry: $DAYS_UNTIL_EXPIRY"

    if [[ $DAYS_UNTIL_EXPIRY -lt 30 ]]; then
        echo -e "${YELLOW}⚠ Certificate expires soon!${NC}"
    else
        echo -e "${GREEN}✓ Certificate valid${NC}"
    fi
else
    echo -e "${RED}✗ Certificate not found${NC}"
    exit 1
fi

# Set up automatic renewal
echo ""
echo "========================================="
echo "Setting Up Automatic Renewal"
echo "========================================="
echo ""

# Create renewal hook script
cat > /etc/letsencrypt/renewal-hooks/post/reload-services.sh <<'EOF'
#!/bin/bash
# Reload services after certificate renewal
systemctl reload nginx
systemctl reload biomate-frontend || true
systemctl reload biomate-backend || true

# Log renewal
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - SSL certificate renewed" >> /var/log/biomate/ssl-renewal.log

# Send notification
HOSTNAME=$(hostname)
curl -X POST https://biomate.ai/api/admin/notifications \
    -H "Content-Type: application/json" \
    -d "{\"type\": \"ssl_renewed\", \"message\": \"SSL certificate renewed on $HOSTNAME\"}" || true
EOF

chmod +x /etc/letsencrypt/renewal-hooks/post/reload-services.sh

# Test automatic renewal
echo "Testing automatic renewal..."
certbot renew --dry-run

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Automatic renewal configured successfully${NC}"
else
    echo -e "${YELLOW}⚠ Automatic renewal test failed, but certificate is valid${NC}"
fi

# Set up systemd timer for renewal
echo "Configuring renewal timer..."

cat > /etc/systemd/system/certbot-renewal.service <<EOF
[Unit]
Description=Certbot SSL Certificate Renewal
Documentation=https://certbot.eff.org/docs/
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet
EOF

cat > /etc/systemd/system/certbot-renewal.timer <<EOF
[Unit]
Description=Timer for Certbot SSL Certificate Renewal
Documentation=https://certbot.eff.org/docs/

[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable timer
systemctl daemon-reload
systemctl enable certbot-renewal.timer
systemctl start certbot-renewal.timer

echo ""
echo "========================================="
echo "Deployment Information"
echo "========================================="
echo ""

echo "Certificate files location:"
echo "  - Certificate: $CERT_PATH/fullchain.pem"
echo "  - Private Key: $CERT_PATH/privkey.pem"
echo "  - Chain: $CERT_PATH/chain.pem"
echo ""

echo "Nginx SSL configuration (add to your server block):"
echo ""
cat <<NGINXCONF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN $DOMAIN_WWW;

    # SSL Certificate
    ssl_certificate $CERT_PATH/fullchain.pem;
    ssl_certificate_key $CERT_PATH/privkey.pem;
    ssl_trusted_certificate $CERT_PATH/chain.pem;

    # TLS 1.3 only
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers off;

    # SSL session cache
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # ... rest of your configuration
}
NGINXCONF

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Remove temporary nginx configuration:"
echo "   rm /etc/nginx/sites-enabled/temp-ssl-setup"
echo ""
echo "2. Deploy production nginx configuration:"
echo "   cp deployment/nginx/biomate.conf /etc/nginx/sites-available/"
echo "   ln -sf /etc/nginx/sites-available/biomate.conf /etc/nginx/sites-enabled/"
echo ""
echo "3. Test nginx configuration:"
echo "   nginx -t"
echo ""
echo "4. Reload nginx:"
echo "   systemctl reload nginx"
echo ""
echo "5. Test SSL configuration:"
echo "   curl -I https://$DOMAIN"
echo "   ./scripts/ssl/test-ssl-config.sh"
echo ""
echo "6. Submit to HSTS preload (optional):"
echo "   https://hstspreload.org/"
echo ""

# Create monitoring script
cat > /usr/local/bin/check-ssl-expiry <<'EOFSCRIPT'
#!/bin/bash
# Check SSL certificate expiration

DOMAIN="biomate.ai"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
ALERT_DAYS=30

if [[ -f "$CERT_PATH/fullchain.pem" ]]; then
    EXPIRY_DATE=$(openssl x509 -in "$CERT_PATH/fullchain.pem" -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

    echo "SSL Certificate Expiry: $DAYS_UNTIL_EXPIRY days"

    if [[ $DAYS_UNTIL_EXPIRY -lt $ALERT_DAYS ]]; then
        echo "WARNING: Certificate expires in $DAYS_UNTIL_EXPIRY days!"
        # Send alert
        logger -t ssl-check "SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
        exit 1
    else
        echo "OK: Certificate valid for $DAYS_UNTIL_EXPIRY days"
        exit 0
    fi
else
    echo "ERROR: Certificate not found"
    exit 2
fi
EOFSCRIPT

chmod +x /usr/local/bin/check-ssl-expiry

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}SSL Certificate Setup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Certificate expires: $(date -d "$EXPIRY_DATE" '+%Y-%m-%d')"
echo "Automatic renewal: Enabled (daily check)"
echo "Renewal hook: /etc/letsencrypt/renewal-hooks/post/reload-services.sh"
echo "Expiry check: /usr/local/bin/check-ssl-expiry"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} Complete steps 1-6 above to finish deployment"
