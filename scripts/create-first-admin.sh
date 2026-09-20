#!/bin/bash
# create-first-admin.sh — BioMate On-Premises Initial Setup
# ==========================================================
# Creates the first admin user on a fresh BioMate on-prem deployment.
#
# Usage:
#   bash scripts/create-first-admin.sh <email> <password> [full_name]
#
# Example:
#   bash scripts/create-first-admin.sh admin@company.com MySecret123! "BioMate Admin"
#
# Requirements:
#   - docker or docker compose must be running (the biomate-postgres container)
#   - OR: set DATABASE_URL env var to connect directly to Postgres
#
# What it does:
#   1. Registers the user via the BioMate API (handles password hashing)
#   2. Grants admin privileges directly in Postgres (subscription_tier = 'admin')
#   3. Marks email as verified (skips email verification step)

set -euo pipefail

EMAIL="${1:-}"
PASSWORD="${2:-}"
FULL_NAME="${3:-Admin}"
APP_URL="${APP_URL:-http://localhost:5000}"

# ── Validate inputs ────────────────────────────────────────────────────────────
if [[ -z "$EMAIL" || -z "$PASSWORD" ]]; then
  echo "Usage: $0 <email> <password> [full_name]"
  echo "Example: $0 admin@company.com MySecret123! 'Admin User'"
  exit 1
fi

if [[ ${#PASSWORD} -lt 8 ]]; then
  echo "ERROR: Password must be at least 8 characters."
  exit 1
fi

echo ""
echo "Creating admin user: $EMAIL"
echo "App URL: $APP_URL"
echo ""

# ── Step 1: Register via API ───────────────────────────────────────────────────
echo "Step 1/3: Registering user..."

REG_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${APP_URL}/api/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"fullName\":\"${FULL_NAME}\"}" \
  2>/dev/null)

HTTP_CODE=$(echo "$REG_RESPONSE" | tail -1)
REG_BODY=$(echo "$REG_RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
  echo "  ✓ User registered successfully."
elif echo "$REG_BODY" | grep -qi "already.*exists\|already.*registered\|duplicate"; then
  echo "  ✓ User already exists — skipping registration."
else
  echo "  WARNING: Registration returned HTTP $HTTP_CODE"
  echo "  Response: $REG_BODY"
  echo "  Proceeding to grant admin in DB (user may already exist)."
fi

# ── Step 2: Grant admin + verify email in Postgres ─────────────────────────────
echo "Step 2/3: Granting admin privileges in database..."

DB_SQL="
UPDATE users
SET subscription_tier = 'admin',
    email_verified = true,
    updated_at = NOW()
WHERE LOWER(email) = LOWER('${EMAIL}');
"

# Detect how to connect to Postgres
if [[ -n "${DATABASE_URL:-}" ]]; then
  echo "  Using DATABASE_URL..."
  UPDATED=$(psql "$DATABASE_URL" -t -c "$DB_SQL" 2>&1)
  echo "  $UPDATED"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "biomate-postgres"; then
  echo "  Using biomate-postgres container..."
  UPDATED=$(docker exec biomate-postgres psql -U "${POSTGRES_USER:-biomate}" -d "${POSTGRES_DB:-biomate}" -t -c "$DB_SQL" 2>&1)
  echo "  $UPDATED"
else
  echo ""
  echo "  ERROR: Cannot connect to Postgres."
  echo "  Neither DATABASE_URL is set nor biomate-postgres container is running."
  echo ""
  echo "  Manual fix — run this SQL in your Postgres:"
  echo "  $DB_SQL"
  exit 1
fi

# ── Step 3: Verify ────────────────────────────────────────────────────────────
echo "Step 3/3: Verifying..."

VERIFY_SQL="SELECT email, subscription_tier, email_verified FROM users WHERE LOWER(email) = LOWER('${EMAIL}');"

if [[ -n "${DATABASE_URL:-}" ]]; then
  psql "$DATABASE_URL" -t -c "$VERIFY_SQL" 2>/dev/null | grep -v "^$" | sed 's/^/  /'
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "biomate-postgres"; then
  docker exec biomate-postgres psql -U "${POSTGRES_USER:-biomate}" -d "${POSTGRES_DB:-biomate}" -t -c "$VERIFY_SQL" 2>/dev/null | grep -v "^$" | sed 's/^/  /'
fi

echo ""
echo "─────────────────────────────────────────────────"
echo "Done! Admin account ready:"
echo "  Email:    $EMAIL"
echo "  Password: (as provided)"
echo "  Role:     admin"
echo ""
echo "Log in at: ${APP_URL}"
echo "Admin dashboard: ${APP_URL}/admin"
echo "─────────────────────────────────────────────────"
echo ""
