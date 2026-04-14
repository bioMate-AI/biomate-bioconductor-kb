# EC2 Dev Platform State — What Lives Only on EC2 vs What Syncs From Local

## Context

The sync script (`scripts/sync_to_dev.sh`) pushes 4 layers from local to EC2:
- Frontend (Docker rebuild)
- Backend Python files (docker cp into Galaxy container)
- Nextflow workflow files (docker cp into Galaxy container)
- Databases (galaxy_ai_tools.db, universe.sqlite via S3)

This document captures everything that lives **only on EC2** and would be lost or need
manual recreation if the EC2 instance is rebuilt, or that would be overwritten by a sync.

---

## EC2 Instance: i-06696b0d91f4346e0 (dev-public.biomate.ai)

**IP**: 52.42.49.175 (Elastic IP)
**OS**: Ubuntu
**Key access**: EC2 Instance Connect (no PEM — inject key via `aws ec2-instance-connect send-ssh-public-key`)

---

## 1. `/opt/biomate/.env` — EC2-ONLY, NOT SYNCED

**Risk**: If the EC2 instance is rebuilt, this file must be recreated manually.
**The sync script never touches this file.**

Current required contents (secrets redacted — obtain from AWS Secrets Manager or team):

```bash
# Galaxy Backend Configuration
GALAXY_CONFIG_FILE=/app/config/galaxy.yml
NODE_ENV=production
PORT=3000
GALAXY_API_URL=http://biomate-galaxy-dev:8080
GALAXY_URL=http://biomate-galaxy-dev:8080
GALAXY_API_KEY=<from Galaxy>
AWS_REGION=us-west-2
S3_BUCKET_NAME=biomate-nextflow-work
DATABASE_URL=postgresql://biomate:biomate@biomate-dev-postgres:5432/biomate

# Security / Auth
BILLING_INTERNAL_KEY=<key>
E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only
CORS_ORIGINS=https://biomate.ai,https://dev-public.biomate.ai
FORCE_HTTPS=0
JWT_SECRET=<key>

# AI
ANTHROPIC_API_KEY=<sk-ant-...>

# Billing — Lago
LAGO_API_URL=http://35.86.137.71:3000
LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157

# AWS Batch
AWS_ACCESS_KEY_ID=<key>
AWS_SECRET_ACCESS_KEY=<key>
NEXTFLOW_USE_AWS=true
```

**Key additions made this session**: `LAGO_API_URL`, `LAGO_API_KEY`

---

## 2. nginx Config — EC2-ONLY, NOT SYNCED

**File**: `/etc/nginx/sites-enabled/biomate-dev.conf`
**Risk**: If nginx is reconfigured or the instance rebuilt, this must be restored.

```nginx
server {
    server_name dev-public.biomate.ai;

    # Nginx handles gzip — strip Accept-Encoding so Express does not double-compress
    gzip on;
    gzip_types application/javascript text/css text/plain application/json text/html;
    gzip_min_length 1000;
    gzip_comp_level 5;

    proxy_buffer_size       128k;
    proxy_buffers           8 128k;
    proxy_busy_buffers_size 256k;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Accept-Encoding "";   # nginx handles gzip, not Express
        proxy_read_timeout 300;
    }

    listen [::]:443 ssl ipv6only=on;
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/dev-public.biomate.ai/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dev-public.biomate.ai/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

# HTTP → HTTPS redirect
server {
    if ($host = dev-public.biomate.ai) { return 301 https://$host$request_uri; }
    listen 80; listen [::]:80;
    server_name dev-public.biomate.ai;
    return 404;
}
```

**SSL**: Let's Encrypt, `/etc/letsencrypt/live/dev-public.biomate.ai/`, expires 2026-07-07.
Renew: `sudo certbot renew`

**Critical settings**:
- `proxy_set_header Accept-Encoding ""` — prevents Express compression crash on 2.2MB JS bundle
- `gzip on` — nginx handles compression, not Express
- `proxy_read_timeout 300` — needed for long AI/workflow requests

---

## 3. Docker Infrastructure — EC2-ONLY, NOT SYNCED

### Network
```bash
docker network create biomate-dev-net
```

### PostgreSQL Container
```bash
# Named volume (created this session — replaces anonymous volume)
docker volume create biomate-postgres-data

docker run -d --name biomate-dev-postgres \
  --network biomate-dev-net \
  -e POSTGRES_USER=biomate \
  -e POSTGRES_PASSWORD=biomate \
  -e POSTGRES_DB=biomate \
  -v biomate-postgres-data:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:15
```

**Data**: 9MB, stored in named volume `biomate-postgres-data`.
**NOT affected by sync** — the sync never touches this container.
**DO NOT** run `docker rm -v biomate-dev-postgres` — `-v` would delete the volume.

### Galaxy Container
The sync script restarts Galaxy but uses the existing image (built Mar 31 2026 from the Galaxy repo).
Galaxy is launched with all env vars from `/opt/biomate/.env` via `--env-file`.

### Frontend Container
**Rebuilt and restarted on every sync cycle** — the sync script builds a new image from local source
and does `docker stop/rm/run` each time. The container is stateless (all data in PostgreSQL).

---

## 4. `/opt/biomate/backup_postgres.sh` — EC2-ONLY, NOT SYNCED

**Risk**: Exists only on EC2. Lost if instance rebuilt.

```bash
#!/bin/bash
set -euo pipefail
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
S3_PREFIX="s3://biomate-nextflow-work/db-backups/postgres"
BACKUP_FILE="/tmp/biomate_pg_${TIMESTAMP}.sql.gz"

docker exec biomate-dev-postgres pg_dumpall -U biomate | gzip > "$BACKUP_FILE"
aws s3 cp "$BACKUP_FILE" "${S3_PREFIX}/biomate_pg_${TIMESTAMP}.sql.gz" --no-progress
rm -f "$BACKUP_FILE"
echo "[$(date)] Backup uploaded: biomate_pg_${TIMESTAMP}.sql.gz"
```

**Location**: `/opt/biomate/backup_postgres.sh`
**Cron**: `0 2 * * * /opt/biomate/backup_postgres.sh >> /var/log/biomate_backup.log 2>&1`

**Backups in S3**: `s3://biomate-nextflow-work/db-backups/postgres/`

**To restore from backup**:
```bash
aws s3 cp s3://biomate-nextflow-work/db-backups/postgres/<backup>.sql.gz /tmp/
zcat /tmp/<backup>.sql.gz | docker exec -i biomate-dev-postgres psql -U biomate
```

---

## 5. What Sync WILL Override

| Layer | What gets replaced | Safe? |
|-------|--------------------|-------|
| Frontend | Docker image rebuilt from local `frontend/` | Yes — stateless |
| Backend Python | ~19 Python files `docker cp`'d into Galaxy container | Yes — same as local |
| Nextflow workflows | All `biomni_workflows/` `.nf` files | Yes — same as local |
| `galaxy_ai_tools.db` | Replaced with local copy via S3 | Yes — local is authoritative |
| `universe.sqlite` | Replaced with local copy via S3 | Yes — local is authoritative |

**Sync never touches**: `.env`, nginx config, PostgreSQL data, SSL certs, backup scripts, crontab.

---

## 6. What Was Uniquely Done On EC2 This Session

| Item | Done on EC2 | Risk if overwritten |
|------|-------------|---------------------|
| Added `LAGO_API_URL` / `LAGO_API_KEY` to `.env` | Yes, via SSH | Billing stops working. Recreate from this doc. |
| Migrated Postgres to named volume | Yes, via SSH | None — already migrated. Don't undo. |
| Created `backup_postgres.sh` | Yes, via SSH | Backups stop. Recreate from this doc. |
| Installed daily backup cron | Yes, via SSH | Backups stop. Reinstall via `crontab -e`. |
| nginx config changes (gzip, buffers, Accept-Encoding) | Yes, on EC2 | CSS/JS breaks in browser. Restore from this doc. |

---

## 7. EC2 Full Rebuild Checklist

If the EC2 instance must be rebuilt from scratch:

1. **Docker network**: `docker network create biomate-dev-net`
2. **PostgreSQL**: Run container with `biomate-postgres-data` named volume; restore from S3 backup
3. **Galaxy**: Run from existing ECR image with `--env-file /opt/biomate/.env`
4. **Frontend**: Sync script will build and deploy
5. **Create `/opt/biomate/.env`** from this doc + secrets from AWS Secrets Manager
6. **nginx**: Restore config from this doc; `sudo certbot certonly` for SSL (or copy from old instance if available before deletion)
7. **Backup script**: Restore `backup_postgres.sh` from this doc; reinstall cron
8. **Run sync**: `nohup bash scripts/sync_to_dev.sh &` — will do full sync

---

## 8. Lago Instance (bill, 35.86.137.71)

Lago runs on **separate** EC2 `i-069fbdf5d2c30eb1b` (us-west-2b, private IP 172.31.18.185).
If that instance is rebuilt:
- Run Lago via docker-compose from `/home/ubuntu/app/lago/`
- API key is stored in Lago's PostgreSQL — retrieve via `docker exec lago-api bundle exec rails runner "puts ApiKey.first&.value"`
- Update `LAGO_API_URL` / `LAGO_API_KEY` in dev EC2 `.env` and Lambda env vars

Lambda `biomate-batch-billing` env vars (also need updating if Lago moves):
```
LAGO_API_URL=http://172.31.18.185:3000   # private IP
LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
```
