# EC2 Docker Release Runbook (S3-First) - 2026-03-12

Purpose: release without GitHub-hosted runner dependency by staging artifacts to S3 first, then deploying on EC2 with Docker.

---

## 1) Why this path

- GitHub Actions hosted jobs are currently blocked by account billing/spending status.
- We still need an immediate release path.
- This runbook uses:
  1. local staging to S3
  2. EC2 pull from S3
  3. Docker compose deployment on EC2

---

## 2) Artifacts and scripts

New files:

- `scripts/deployment/stage-release-to-s3.sh`
- `scripts/deployment/ec2-deploy-from-s3.sh`
- `scripts/deployment/validate-ec2-config.sh`
- `docker-compose.ec2.yml`
- `.env.ec2.example`

Make scripts executable:

```bash
chmod +x scripts/deployment/stage-release-to-s3.sh
chmod +x scripts/deployment/ec2-deploy-from-s3.sh
chmod +x scripts/deployment/validate-ec2-config.sh
```

---

## 3) Step A - Stage release to S3 (local machine)

Minimal source bundle:

```bash
./scripts/deployment/stage-release-to-s3.sh \
  --bucket biomate-nextflow-work \
  --release-id aws-release-2026-03-12-r1 \
  --region us-west-2
```

With large-file staging (recommended):

1. create TSV manifest (path<TAB>s3-key), example:

```text
/data/big/input1.fastq.gz	inputs/input1.fastq.gz
/data/big/input2.fastq.gz	inputs/input2.fastq.gz
```

2. run:

```bash
./scripts/deployment/stage-release-to-s3.sh \
  --bucket biomate-nextflow-work \
  --release-id aws-release-2026-03-12-r1 \
  --region us-west-2 \
  --asset-manifest ./release-assets.tsv
```

Outputs:

- `s3://<bucket>/releases/<release-id>/source.tar.gz`
- `s3://<bucket>/releases/<release-id>/source.tar.gz.sha256`
- `s3://<bucket>/releases/<release-id>/release-manifest.txt`
- optional large assets under `s3://<bucket>/assets/<release-id>/...`

---

## 4) Step B - Deploy on EC2 from S3

Prerequisites on EC2:

- IAM role/credentials can read release bucket/prefix
- Docker available (script installs if missing)
- security groups allow required inbound ports (`5000`, optional `8081`)

Run on EC2:

```bash
sudo bash scripts/deployment/ec2-deploy-from-s3.sh \
  --bucket biomate-nextflow-work \
  --release-id aws-release-2026-03-12-r1 \
  --region us-west-2 \
  --assets-prefix assets/aws-release-2026-03-12-r1 \
  --assets-dir /opt/biomate/shared/assets
```

Before first container start, prepare env file:

```bash
sudo mkdir -p /opt/biomate/shared
sudo cp /opt/biomate/current/.env.ec2.example /opt/biomate/shared/.env.ec2
sudo vi /opt/biomate/shared/.env.ec2
```

Validate required config before container startup:

```bash
bash /opt/biomate/current/scripts/deployment/validate-ec2-config.sh \
  --env-file /opt/biomate/shared/.env.ec2 \
  --repo-root /opt/biomate/current
```

Required env keys in `/opt/biomate/shared/.env.ec2`:

- At least one of: `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`
- `JWT_SECRET`
- `SESSION_SECRET`
- `BILLING_INTERNAL_KEY`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `S3_BUCKET_NAME`
- `GALAXY_URL`
- `GALAXY_API_KEY`

Database note:

- `DATABASE_URL` is optional when using bundled compose postgres.
- Set `DATABASE_URL` only if you want external Postgres (for example RDS).

Required Galaxy config files in `/opt/biomate/current/backend/config`:

- `galaxy.yml`
- `tool_conf.xml.sample`
- `shed_tool_conf.xml`

The deploy script will use:

- source from `s3://<bucket>/releases/<release-id>/source.tar.gz`
- compose from `/opt/biomate/current/docker-compose.ec2.yml`
- env from `/opt/biomate/shared/.env.ec2` (if present)

---

## 5) Step C - Bind website to your AWS dev URL

After containers are up, configure Nginx on EC2 to serve the app under your dev URL:

```bash
chmod +x scripts/deployment/configure-ec2-dev-url.sh
sudo bash scripts/deployment/configure-ec2-dev-url.sh --domain <your-dev-url>
```

Optional HTTPS with Let's Encrypt (when DNS already points to EC2):

```bash
sudo bash scripts/deployment/configure-ec2-dev-url.sh --domain <your-dev-url> --enable-ssl --email <ops-email>
```

This config proxies `<your-dev-url>` -> `http://127.0.0.1:5000` (frontend container).

---

## 6) Verification

On EC2:

```bash
docker compose -f /opt/biomate/current/docker-compose.ec2.yml ps
curl -fsS http://127.0.0.1:5000/api/health
curl -fsS http://127.0.0.1:8081/api/version
```

Release contract checks (from operator machine or EC2 with correct URL):

```bash
npm --prefix frontend run check
npm --prefix frontend run test -- server/execution-env-policy.test.ts server/workflow-execution.test.ts
RUN_LIVE_EXECUTE_CONTRACT=1 REQUIRE_AWS_EXEC_200=1 BIOMATE_URL=http://<ec2-host>:5000 npm --prefix frontend run test:live:execute-contract:strict
```

---

## 7) Rollback

List staged releases:

```bash
ls -1 /opt/biomate/releases
```

Rollback to previous release:

```bash
sudo ln -sfn /opt/biomate/releases/<previous-release-id> /opt/biomate/current
sudo docker compose -f /opt/biomate/current/docker-compose.ec2.yml --env-file /opt/biomate/shared/.env.ec2 up -d --build
```

---

## 8) Notes for team parallelization

- Track B can continue app/API gate checks in parallel.
- Track C can monitor AWS infra health and S3 transfer success.
- Track D should enforce day-0 allow-list while ADMET runtime dependency closure is pending.
- Track E owns EC2 deploy + smoke + rollback drill using this runbook.
- Track F CI/CD remains optional until billing gate is restored.
