# User-Provided S3 Credentials — Current State & Plan
**Date:** 2026-03-12 02:23 UTC

---

## Current State

### What already exists (can reuse directly)

| Component | File | Status |
|---|---|---|
| AES-256-GCM encryption | `frontend/server/encryption.ts` | Ready — PBKDF2 + GCM auth tag, 100k iterations |
| bcrypt password hashing | `frontend/server/auth-service.ts` | Used for passwords; available for credentials |
| Users table (Drizzle/Postgres) | `frontend/shared/schema.ts` | Exists; `galaxyApiKey` column stores API key (currently plaintext) |
| Redis session store | `frontend/server/redis-session.ts` | 24h TTL, distributed |
| `authenticateToken` middleware | `frontend/server/routes.ts` | Protects all user endpoints |
| S3 presigned URL logic | `frontend/server/s3-client.ts` | Works; currently uses shared platform key |

### What is missing

1. **`user_credentials` DB table** — no encrypted key-value store per user
2. **No S3 credential endpoints** — no save / validate / retrieve
3. **`userSettingsSchema`** has `defaultStorageType: "s3"` but no credential fields
4. **Workflow execution ignores user credentials** — always uses platform IAM key; S3 path validation in `nextflow_executor.py` uses platform boto3 chain, not user-provided keys
5. **Galaxy API key** in users table is stored plaintext — same `encrypt()` utility should fix this too

---

## Plan

### A. Database (schema.ts)

New table `userCloudCredentials`:
```typescript
export const userCloudCredentials = pgTable("user_cloud_credentials", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  userId: varchar("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  provider: text("provider").notNull(),           // "s3", "gcs", "azure" — extensible
  label: text("label").notNull(),                 // user-facing name e.g. "My lab bucket"
  encryptedPayload: text("encrypted_payload").notNull(),  // AES-256-GCM JSON blob
  // Plaintext metadata for display (no secrets):
  region: text("region"),
  bucketHint: text("bucket_hint"),                // first 3 chars + *** e.g. "bio***"
  validatedAt: timestamp("validated_at"),         // last successful STS+S3 check
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});
```

`encryptedPayload` stores (via `encrypt()` from encryption.ts):
```json
{ "accessKeyId": "AKIA...", "secretAccessKey": "...", "region": "us-east-1", "bucket": "my-lab-bucket" }
```

### B. API Endpoints (`routes.ts`)

```
POST   /api/user/credentials/s3          Save + validate S3 credentials
GET    /api/user/credentials             List saved credentials (no secrets returned)
DELETE /api/user/credentials/:id         Remove a credential set
POST   /api/user/credentials/:id/validate  Re-run STS + S3 check on saved creds
```

**Save flow (`POST /api/user/credentials/s3`):**
1. Receive `{ label, accessKeyId, secretAccessKey, region, bucket }`
2. Run validation (STS `GetCallerIdentity` + S3 `HeadBucket`) — fail fast with 422 if invalid
3. Encrypt payload with `encrypt(JSON.stringify(creds), process.env.ENCRYPTION_KEY)`
4. Store in `user_cloud_credentials`; return id + masked metadata

**Validation logic:**
```typescript
import { STSClient, GetCallerIdentityCommand } from "@aws-sdk/client-sts";
import { S3Client, HeadBucketCommand } from "@aws-sdk/client-s3";

async function validateS3Credentials(creds) {
  // 1. Check keys are valid (STS call — works regardless of S3 permissions)
  const sts = new STSClient({ region: creds.region, credentials: creds });
  await sts.send(new GetCallerIdentityCommand({}));   // 401 if invalid keys

  // 2. Check bucket is accessible
  const s3 = new S3Client({ region: creds.region, credentials: creds });
  await s3.send(new HeadBucketCommand({ Bucket: creds.bucket }));
  // 403 = valid keys but no access; 404 = bucket doesn't exist; 200 = OK
}
```

Returns structured error:
- `invalid_credentials` — STS rejected keys
- `bucket_not_found` — keys valid, bucket doesn't exist
- `access_denied` — keys valid, bucket exists, IAM policy missing S3 permissions
- `ok` + `{ callerArn, accountId }` — fully validated

### C. Workflow execution wiring

When a user submits a workflow with `input=s3://my-bucket/...` or `outdir=s3://my-bucket/...`:

1. Frontend `POST /api/nextflow/execute` includes `user_credential_id: "uuid"` in `compute_config`
2. Backend route looks up `user_cloud_credentials` for that user + id
3. Decrypts payload → passes `aws_access_key_id`, `aws_secret_access_key` as Nextflow env vars:
   ```
   nextflow run ... -e AWS_ACCESS_KEY_ID=... -e AWS_SECRET_ACCESS_KEY=... -e AWS_DEFAULT_REGION=...
   ```
   OR injects into `biomate_executor_override.config`:
   ```groovy
   aws { accessKey = '...'; secretKey = '...'; region = '...' }
   ```
4. `_validate_s3_url()` in `nextflow_executor.py` uses those creds (passed as env override) instead of instance role

### D. UI

Settings page (new tab "Cloud Storage"):
- Form: Label, Access Key ID, Secret Access Key (masked input), Region, Bucket
- "Validate & Save" button — calls `POST /api/user/credentials/s3`
- Shows validation result: ✓ "Verified — account 399683337364, us-west-2" or ✗ with specific error
- List of saved credential sets with label, bucket hint, last validated date
- Delete button per entry

---

## Security notes

- Secret never returned to client after save (only `bucketHint` + `region` + `validatedAt`)
- `ENCRYPTION_KEY` env var required in production (server throws if absent)
- Credentials decrypted in memory only at workflow execution time — never logged
- Galaxy API key in users table: fix with same `encrypt()` call during this sprint

---

## Session doc
`docs/sessions/20260312_0223_USER_S3_CREDENTIALS_PLAN.md` (this file)
