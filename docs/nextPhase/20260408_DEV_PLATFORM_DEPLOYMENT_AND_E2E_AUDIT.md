# Dev Platform Deployment & E2E Audit — 2026-04-08

## Summary

Session to deploy updated frontend to `https://dev-public.biomate.ai` (EC2 `i-06696b0d91f4346e0`, t3.large, `52.42.49.175`) and validate drug discovery + cryo-EM workflows via E2E tests.

---

## EC2 Infrastructure

| Item | Value |
|------|-------|
| Instance | `i-06696b0d91f4346e0` (t3.large, us-west-2a) |
| Elastic IP | `52.42.49.175` |
| SSH | EC2 Instance Connect (no PEM needed) — 60s window per key injection |
| SSH cmd | `aws ec2-instance-connect send-ssh-public-key --instance-id i-06696b0d91f4346e0 --availability-zone us-west-2a --instance-os-user ubuntu --ssh-public-key file:///tmp/biomate_ec2_key.pub --region us-west-2` |

### Docker containers

| Container | Image | Port | Network |
|-----------|-------|------|---------|
| `biomate-dev-frontend` | `biomate-dev-frontend:latest` | 3000 | `biomate-dev-net` |
| `biomate-galaxy-dev` | Galaxy backend | 8080 | `biomate-dev-net` |
| `biomate-dev-postgres` | Postgres | 5432 | `biomate-dev-net` |

### Frontend container run command (canonical)

```bash
docker run -d --name biomate-dev-frontend --network biomate-dev-net \
  -p 3000:3000 \
  --env-file /opt/biomate/.env \
  -e NODE_ENV=production \
  -e PORT=3000 \
  -e FORCE_HTTPS=0 \
  --restart unless-stopped \
  --health-cmd="curl -sf http://127.0.0.1:3000/api/health || exit 1" \
  --health-interval=30s --health-timeout=10s --health-start-period=30s --health-retries=3 \
  biomate-dev-frontend:latest
# After start — restore logo (not baked into image):
docker cp /tmp/logo.png biomate-dev-frontend:/app/dist/public/logo.png
```

---

## Bugs Found and Fixed This Session

### 1. CORS blocked `dev-public.biomate.ai` — **ROOT CAUSE of blank page**

- **Symptom**: React app never rendered (blank white page). JS bundle returned HTTP 500 with `application/json` in browser but 200 from curl.
- **Root cause**: `security-config.ts` production CORS whitelist = `["https://biomate.ai"]`. When browser loads `https://dev-public.biomate.ai` and requests `/assets/index--RB6Jjk7.js` with `Origin: https://dev-public.biomate.ai`, Express CORS middleware rejects it and returns `{"error":"Not allowed by CORS"}` with status 500.
- **Fix**: Add `CORS_ORIGINS=https://biomate.ai,https://dev-public.biomate.ai` to `/opt/biomate/.env`. The server reads this env var: `corsOrigins: process.env.CORS_ORIGINS?.split(',') || defaultOrigins`.
- **Why curl worked**: curl doesn't send `Origin` header by default → CORS check skipped → 200 returned.

### 2. GALAXY_API_URL wrong hostname

- **Symptom**: AI chat responses never came back (Galaxy backend unreachable).
- **Root cause**: `/opt/biomate/.env` had `GALAXY_API_URL=http://galaxy-backend:8080` but container is named `biomate-galaxy-dev`. Docker DNS resolves by container name.
- **Fix**: `GALAXY_API_URL=http://biomate-galaxy-dev:8080` and `GALAXY_URL=http://biomate-galaxy-dev:8080`.

### 3. ANTHROPIC_API_KEY was a placeholder

- **Symptom**: AI calls silently failing (no workflow cards).
- **Fix**: Replace `dev-plac...` with real `sk-ant-api03-...` key from `frontend/.env`.

### 4. E2E_TEST_TOKEN missing

- **Symptom**: Registration rate-limited during E2E tests (429), JWT never obtained.
- **Fix**: Add `E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only` to `/opt/biomate/.env`.

### 5. FORCE_HTTPS=0 required

- **Symptom**: Docker health check returning 301 (Express redirects HTTP→HTTPS in production mode, even for internal health checks).
- **Fix**: `FORCE_HTTPS=0` env var disables Express HTTPS redirect. Nginx handles SSL externally.

### 6. nginx proxy buffers insufficient for 2.2MB JS bundle

- **Symptom**: Initially suspected, but actual root cause was CORS (see #1).
- **Fix applied anyway**: Increased nginx `proxy_buffer_size 128k`, `proxy_buffers 8 128k`, `proxy_busy_buffers_size 256k`. Also added `gzip on` at nginx level and `proxy_set_header Accept-Encoding ""` to prevent Express from double-compressing.
- **Note**: Express compression middleware crashes with 500 on the 2.2MB bundle when `Accept-Encoding: gzip` is sent. Nginx's gzip handles compression instead.

### 7. Logo not baked into Docker image

- **Symptom**: Logo not visible after container restart.
- **Root cause**: `logo.png` is in `frontend/client/public/` (dev path) → compiled into `dist/public/logo.png` during build, but the build used the old logo. New logo must be `docker cp`'d after each restart.
- **Permanent fix pending**: Rebuild Docker image with new logo included.

---

## `/opt/biomate/.env` Required Keys

```
ANTHROPIC_API_KEY=sk-ant-api03-...   # Real key, not placeholder
E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only
FORCE_HTTPS=0
CORS_ORIGINS=https://biomate.ai,https://dev-public.biomate.ai
GALAXY_API_URL=http://biomate-galaxy-dev:8080
GALAXY_URL=http://biomate-galaxy-dev:8080
GALAXY_API_KEY=f17c618a6d8a9b0c397d6cc847a7f658
NODE_ENV=production
PORT=3000
DATABASE_URL=postgresql://biomate:biomate@biomate-dev-postgres:5432/biomate
```

---

## nginx config — `/etc/nginx/sites-enabled/biomate-dev.conf`

```nginx
server {
    server_name dev-public.biomate.ai;

    gzip on;
    gzip_types application/javascript text/css text/plain application/json;
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
```

---

## E2E Test Results — dev-public.biomate.ai (2026-04-08)

### Drug Discovery Pilot (S1–S6)

| Session | H1 (workflow card) | Execution | Notes |
|---------|-------------------|-----------|-------|
| S1 ADMET | ✅ 44.5s | ❌ 400 | SMILES-as-path bug in dev platform (fixed locally, not yet deployed) |
| S2 IVIVE | ✅ 39.4s | ❌ 400 | Same — DB entry points to wrong path |
| S3 Pocket | ✅ 40.5s | ❌ 400 | pdb_input param UI not rendering (not blocking H1) |
| S4 Pharma | ✅ | ❌ 400 | File params not filling |
| S5 Ranking | ✅ | ❌ 400 | assay_csv param not filling |
| S6 CRO | pending | pending | |

### Cryo-EM

| Test | Result | Notes |
|------|--------|-------|
| T0 QC profiles | ❌ | `/api/qc/profiles` endpoint not in Galaxy backend on dev |
| T1 Full SPA workflow | in progress | |

### Known Execution Failures (Not Dev-Environment Specific — Real Bugs)

The `Execute API status=400` errors are **not** AWS Batch issues. They are rejected at the API level due to:
1. **SMILES-as-path bug**: `smiles_input` field being passed as a file path rather than inline SMILES string (fixed locally for S1, S2)
2. **Missing DB file paths**: `drug_discovery` DB entries (id=12825 etc.) registered later point to `.nf` files not present on disk in dev platform's code version
3. **Param UI mismatch**: `pdb_input`, `reference_actives`, `assay_csv` params expected by test not rendering in workflow viewer for current code version

**Action required**: Deploy the local fixes (SMILES-as-path fix, DB path corrections) to dev-public before execution tests can pass.

---

## Deployment Process

### Deploy frontend code update to dev-public

```bash
# 1. On local machine — build tar of frontend source
cd /home/yzhang/biomate
tar -czf /tmp/biomate_frontend.tar.gz \
  frontend/client/ frontend/server/ frontend/shared/ \
  frontend/package.json frontend/package-lock.json \
  frontend/tsconfig.json frontend/vite.config.ts \
  frontend/Dockerfile

# 2. Inject SSH key
ssh-keygen -t ed25519 -f /tmp/biomate_ec2_key -N "" -q
aws ec2-instance-connect send-ssh-public-key \
  --instance-id i-06696b0d91f4346e0 --availability-zone us-west-2a \
  --instance-os-user ubuntu --ssh-public-key file:///tmp/biomate_ec2_key.pub \
  --region us-west-2

# 3. Upload and build
scp -i /tmp/biomate_ec2_key ubuntu@52.42.49.175:/tmp/frontend_update.tar.gz /tmp/biomate_frontend.tar.gz
ssh -i /tmp/biomate_ec2_key ubuntu@52.42.49.175 '
  mkdir -p /opt/biomate/frontend_new
  tar -xzf /tmp/frontend_update.tar.gz -C /opt/biomate/frontend_new
  cp /opt/biomate/frontend/Dockerfile /opt/biomate/frontend_new/frontend/  # if needed
  cd /opt/biomate && docker build -t biomate-dev-frontend:latest -f frontend/Dockerfile frontend_new/frontend/
  # Then restart container (see canonical run command above)
'
```

---

## Marketing Site — biomate.ai

- **Files**: `/var/www/biomate-marketing/index.html`, `/var/www/biomate-marketing/images/logo.png`
- **Update**: `scp -i /tmp/biomate_ec2_key /home/yzhang/biomate/webpage_design/index.html ubuntu@52.42.49.175:/tmp/ && ssh ... sudo cp /tmp/index.html /var/www/biomate-marketing/`
- **SSL**: Let's Encrypt, expires 2026-07-07
- **Changes made**: Removed platform link cards, replaced "Open Platform" with "Log In", all URLs point to `https://dev-public.biomate.ai`
