# BioMate — Security Changes: Code Impact & Required Modifications

**Date:** 2026-04-28
**Companion to:** `docs/20260428_SECURITY_REMEDIATION_TEAM_BRIEF.md`
**Purpose:** Exact code changes required so the system continues working after each security fix

---

## Overview

Three security items are being remediated. The table below summarises how much code each one touches:

| Item | Code changes needed | Effort |
|---|---|---|
| Root IAM key → IAM user | **Zero** — env var swap only | 10 min |
| Port 22 restriction | **Zero** — infrastructure only | 15 min |
| Lambda secrets → Secrets Manager | **3 Python files** in the Lambda package | 2 hours |

---

## 1. Root IAM Key Migration — No Code Changes Required

### Why no code changes are needed

Every place in the codebase that talks to AWS uses one of two patterns:

**Pattern A — boto3 (Python):** `boto3.client("s3")`, `boto3.client("lambda")`, etc.
boto3 automatically discovers credentials in this order:
1. Explicit `aws_access_key_id` / `aws_secret_access_key` arguments (none in our code)
2. Environment variables `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
3. `~/.aws/credentials` file
4. EC2 instance profile / ECS task role

All calls in the codebase use the implicit form. Changing the env var in `.env` is sufficient.

**Pattern B — Node.js AWS SDK (`s3-client.ts`):**

```typescript
// frontend/server/s3-client.ts  lines 37–52
const accessKeyId     = config?.accessKeyId || process.env.AWS_ACCESS_KEY_ID;
const secretAccessKey = config?.secretAccessKey || process.env.AWS_SECRET_ACCESS_KEY;
```

Same pattern — reads from `process.env`, which is populated from `/opt/biomate/.env` at startup.

### What to change

**On the production EC2 only** — edit `/opt/biomate/.env`:

```bash
# BEFORE
AWS_ACCESS_KEY_ID=AKIAV2DX3XSKGYVKVDET
AWS_SECRET_ACCESS_KEY=<root secret>

# AFTER
AWS_ACCESS_KEY_ID=AKIAV2DX3XSKLG5H4HQ6
AWS_SECRET_ACCESS_KEY=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
```

Then restart the app:
```bash
# Restart Node.js frontend (finds the process by port)
sudo systemctl restart biomate-frontend   # or however it is managed
# Restart Galaxy backend
kill -HUP $(pgrep -f "gunicorn.*8081" | head -1)
```

**On the dev machine** — edit `~/.aws/credentials`:
```ini
[default]
aws_access_key_id     = AKIAV2DX3XSKLG5H4HQ6
aws_secret_access_key = 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
```

No other files touch these credentials. No redeployment of application code required.

### Verification

```bash
# On the EC2, after restart:
curl -s http://localhost:5000/api/health   # app still responding
aws sts get-caller-identity               # returns biomate-admin, not root

# Test S3 access still works (used by Nextflow output fetching):
aws s3 ls s3://biomate-production-data-399683337364/ | head -5
```

---

## 2. Port 22 Restriction — No Code Changes Required

Removing port 22 from security groups is a network change only. The application code does not open or accept SSH connections — SSH is used only by engineers for manual access.

If the team switches to SSM Session Manager exclusively, no code changes are needed. The SSM agent communicates outbound on port 443, which is already open.

---

## 3. Lambda Secrets → Secrets Manager — 3 Files to Change

### Affected files

| File | What it reads from env | Change type |
|---|---|---|
| `backend/lib/galaxy/ai/billing/lambda/s3_event_handler.py` | `BILLING_API_KEY` | Module-level read → Secrets Manager |
| `backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py` | `LAGO_API_KEY` | Module-level read → Secrets Manager |
| `backend/lib/galaxy/ai/billing/core/lago_client.py` | `LAGO_API_KEY` | Module-level read → Secrets Manager |

`billing_router.py` reads `BILLING_INTERNAL_KEY` (a different key, not stored in Secrets Manager — leave as-is).

### Shared helper to add once

Add this to a new file `backend/lib/galaxy/ai/billing/lambda/secrets.py` (used by both Lambda handlers):

```python
# backend/lib/galaxy/ai/billing/lambda/secrets.py
import boto3, functools, logging

log = logging.getLogger(__name__)
_SM_REGION = "us-west-2"

@functools.lru_cache(maxsize=None)
def get_secret(name: str) -> str:
    """
    Fetch a secret from AWS Secrets Manager.
    Result is cached for the lifetime of the Lambda execution environment
    (warm invocations reuse the cached value — zero overhead after first call).
    Falls back to empty string and logs a warning if the fetch fails,
    preserving the existing behaviour where missing keys cause a no-op emit.
    """
    try:
        sm = boto3.client("secretsmanager", region_name=_SM_REGION)
        return sm.get_secret_value(SecretId=name)["SecretString"]
    except Exception as e:
        log.warning("Could not fetch secret '%s' from Secrets Manager: %s", name, e)
        return ""
```

The `lru_cache` is the key detail — it makes the first call fetch from SM (≈50ms) and all subsequent calls within the same warm Lambda instance return the cached value instantly.

### Change 1 of 3 — `s3_event_handler.py`

**File:** `backend/lib/galaxy/ai/billing/lambda/s3_event_handler.py`

```python
# BEFORE (lines 43–44)
BILLING_API_URL = os.environ.get("BILLING_API_URL", "")
BILLING_API_KEY = os.environ.get("BILLING_API_KEY", "")

# AFTER
from .secrets import get_secret   # or: from secrets import get_secret (if flat package)

BILLING_API_URL = os.environ.get("BILLING_API_URL", "")          # not a secret — keep in env
BILLING_API_KEY = get_secret("biomate/billing/api-key")           # from Secrets Manager
```

Nothing else in `s3_event_handler.py` changes. The variable `BILLING_API_KEY` is used on line 77:
```python
headers={"X-Internal-Key": BILLING_API_KEY}
```
This line is unchanged — it already references the module-level variable.

### Change 2 of 3 — `batch_event_handler.py`

**File:** `backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py`

```python
# BEFORE (lines 116–117)
_LAGO_URL = os.environ.get("LAGO_API_URL", "").rstrip("/")
_LAGO_KEY = os.environ.get("LAGO_API_KEY", "")

# AFTER
from .secrets import get_secret

_LAGO_URL = os.environ.get("LAGO_API_URL", "").rstrip("/")        # not a secret — keep in env
_LAGO_KEY = get_secret("biomate/lago/api-key")                    # from Secrets Manager
```

The guard on line 129 that checks `if not _LAGO_URL or not _LAGO_KEY` still works correctly — `get_secret` returns `""` on failure, so the existing no-op behaviour is preserved if SM is unreachable.

### Change 3 of 3 — `lago_client.py`

**File:** `backend/lib/galaxy/ai/billing/core/lago_client.py`

This file is imported by `billing_router.py` (the Galaxy backend process, not a Lambda). The Galaxy backend runs on EC2, not in Lambda, so it has access to the same Secrets Manager via boto3.

```python
# BEFORE (lines 36–44)
LAGO_BASE_URL = os.environ.get("LAGO_API_URL", "http://lago:3000")
LAGO_API_KEY = os.environ.get("LAGO_API_KEY")
if not LAGO_API_KEY:
    if _ALLOW_INSECURE_DEV_MODE:
        LAGO_API_KEY = "dev-insecure-lago-key"
        log.warning("BILLING_DEV_MODE enabled: using insecure default LAGO_API_KEY")
    else:
        raise RuntimeError(
            "LAGO_API_KEY environment variable is required for billing event submission. "
        )

# AFTER
import functools as _functools

LAGO_BASE_URL = os.environ.get("LAGO_API_URL", "http://lago:3000")   # not a secret — keep in env

@_functools.lru_cache(maxsize=None)
def _fetch_lago_api_key() -> str:
    # In dev mode, allow env var override or insecure default
    env_key = os.environ.get("LAGO_API_KEY")
    if env_key:
        return env_key   # local dev: still works via env var
    if _ALLOW_INSECURE_DEV_MODE:
        log.warning("BILLING_DEV_MODE enabled: using insecure default LAGO_API_KEY")
        return "dev-insecure-lago-key"
    try:
        import boto3
        sm = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-west-2"))
        return sm.get_secret_value(SecretId="biomate/lago/api-key")["SecretString"]
    except Exception as e:
        raise RuntimeError(f"Could not fetch LAGO_API_KEY from Secrets Manager: {e}") from e

# Keep the module-level name for backward compatibility with imports
# (billing_router.py does: from ..core.lago_client import LAGO_API_KEY as _LAGO_API_KEY)
# Use a property-like pattern via a lazy wrapper
class _LazyKey(str):
    """Str subclass that fetches the real value on first use."""
    _resolved: str = ""
    def __new__(cls):
        return super().__new__(cls, "")   # placeholder
    def __str__(self):
        if not self._resolved:
            self.__class__._resolved = _fetch_lago_api_key()
        return self._resolved
    def __bool__(self):
        return bool(str(self))

LAGO_API_KEY: str = _LazyKey()
```

> **Simpler alternative** if the lazy wrapper feels over-engineered: just call `_fetch_lago_api_key()` at the module level directly. The lru_cache ensures it only hits Secrets Manager once per process lifetime. The only drawback is that import fails if SM is unreachable at startup. In production this is acceptable; in unit tests, mock `boto3.client`.

The simpler version:
```python
# Simplest correct version
LAGO_BASE_URL = os.environ.get("LAGO_API_URL", "http://lago:3000")
LAGO_API_KEY = (
    os.environ.get("LAGO_API_KEY")           # env var takes precedence (dev/test)
    or _fetch_from_secrets_manager("biomate/lago/api-key")   # production
)
```

Where `_fetch_from_secrets_manager` handles the dev mode fallback.

### IAM permission required on the Lambda execution role

Before deploying, add this inline policy to `biomate-lambda-billing-role`:

```bash
cat > /tmp/sm-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "ReadBillingSecrets",
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": [
      "arn:aws:secretsmanager:us-west-2:399683337364:secret:biomate/billing/api-key-*",
      "arn:aws:secretsmanager:us-west-2:399683337364:secret:biomate/lago/api-key-*"
    ]
  }]
}
EOF

aws iam put-role-policy \
  --role-name biomate-lambda-billing-role \
  --policy-name BillingSecretsReadPolicy \
  --policy-document file:///tmp/sm-policy.json
```

The Galaxy backend (EC2) already has broad IAM permissions via `galaxy-dev` user credentials — it can reach Secrets Manager without policy changes. Confirm with:
```bash
aws secretsmanager get-secret-value \
  --secret-id biomate/lago/api-key \
  --region us-west-2 \
  --query SecretString --output text
```

### Deployment sequence

1. Add `secrets.py` helper to the Lambda package
2. Apply the three file changes above
3. Add the IAM inline policy to `biomate-lambda-billing-role` (Step 1 in the team brief)
4. Redeploy both Lambda functions:
   ```bash
   cd backend/lib/galaxy/ai/billing/lambda
   zip -r /tmp/s3_billing.zip . && \
   aws lambda update-function-code --region us-east-1 \
     --function-name biomate-s3-billing \
     --zip-file fileb:///tmp/s3_billing.zip

   zip -r /tmp/batch_billing.zip . && \
   aws lambda update-function-code --region us-west-2 \
     --function-name biomate-batch-billing \
     --zip-file fileb:///tmp/batch_billing.zip
   ```
5. Invoke each Lambda with a test event and confirm billing events reach Lago
6. Remove `BILLING_API_KEY` and `LAGO_API_KEY` from Lambda env vars (Step 4 in the team brief)
7. Run evidence collector — expect `✅ lambda_no_plaintext_secrets`

### Backward compatibility

- **Dev environment:** `lago_client.py` checks `os.environ.get("LAGO_API_KEY")` first — existing `.env` files in dev still work with no changes
- **Unit tests:** Mock `boto3.client("secretsmanager")` or set `LAGO_API_KEY` in the test environment — both paths are supported
- **If Secrets Manager is unreachable** (network partition): `get_secret()` logs a warning and returns `""`, which causes the billing emit to be skipped — same behaviour as today when the env var is missing

---

## Summary — What Breaks Without Each Change

| If you skip | What breaks |
|---|---|
| Updating `.env` AWS keys | Nothing breaks immediately. Breaks when the root key is deleted. |
| Adding SM read permission to Lambda role | Lambda crashes with `AccessDeniedException` on first invocation after key removal |
| Updating `s3_event_handler.py` | S3 billing events stop reaching Galaxy backend — S3 usage goes unbilled |
| Updating `batch_event_handler.py` | Batch job events stop reaching Lago — compute goes unbilled |
| Updating `lago_client.py` | Galaxy backend billing router stops emitting LLM tokens to Lago — LLM usage goes unbilled |

---

*See also:*
- *`docs/20260428_SECURITY_REMEDIATION_TEAM_BRIEF.md` — operational steps*
- *`docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md` — full compliance framework*
- *`backend/scripts/compliance/collect_evidence.py` — automated evidence collector*
