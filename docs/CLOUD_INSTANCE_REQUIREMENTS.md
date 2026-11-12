# BioMate Cloud Instance Requirements

> **Applies to:** AWS EC2 instances running the BioMate dev/test/staging stack (not on-prem).  
> **Updated:** 2026-11-12

---

## IAM Role: `BioMateEc2DeployRole`

Every BioMate EC2 instance must be launched with an instance profile that includes this role. The role needs the following **inline policies** (attached by name so they can be audited with `aws iam list-role-policies`):

### Required inline policies

| Policy name | Purpose |
|-------------|---------|
| `NextflowBatchSubmit` | Submit Nextflow workflows as AWS Batch jobs |
| `S3ReadDevSync` | Read deployment artifacts from S3 |
| `S3StructureDbRead` | Read workflow database from S3 |
| `dev-biomate-secrets-read` / `test-biomate-secrets-read` | Read env secrets from Secrets Manager |
| `ECRPullBiomateDevRepos` | Pull backend/frontend images from ECR |
| `BioMateOnpremAssetsWrite` | Write workflow outputs to S3 |

### `NextflowBatchSubmit` — required permissions (complete)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "NextflowBatchOperations",
      "Effect": "Allow",
      "Action": [
        "batch:DescribeJobDefinitions",
        "batch:RegisterJobDefinition",
        "batch:DeregisterJobDefinition",
        "batch:TagResource",
        "batch:UntagResource",
        "batch:DescribeJobs",
        "batch:SubmitJob",
        "batch:TerminateJob",
        "batch:CancelJob",
        "batch:ListJobs",
        "batch:DescribeJobQueues",
        "batch:DescribeComputeEnvironments"
      ],
      "Resource": "*"
    },
    {
      "Sid": "NextflowPassTaskRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::399683337364:role/biomate-nextflow-task-role"
    }
  ]
}
```

> **Critical:** `iam:PassRole` for `biomate-nextflow-task-role` is **required**.  
> Without it, every Nextflow pipeline fails immediately with:  
> `User ... is not authorized to perform: iam:PassRole on resource: .../biomate-nextflow-task-role`  
> The pipeline exits `rc=1`, and the failure only appears in the Nextflow launcher log  
> (`/tmp/nextflow_runs/<run-id>/nextflow.log`) — it does NOT surface in the deploy smoke test.

### How to verify

```bash
# Check current role policies
aws iam get-role-policy \
  --role-name BioMateEc2DeployRole \
  --policy-name NextflowBatchSubmit \
  --region us-west-2

# Verify PassRole is present
aws iam get-role-policy \
  --role-name BioMateEc2DeployRole \
  --policy-name NextflowBatchSubmit \
  --region us-west-2 | grep -q PassRole && echo "OK" || echo "MISSING — workflows will fail"
```

### How to fix (if PassRole is missing)

```bash
aws iam put-role-policy \
  --role-name BioMateEc2DeployRole \
  --policy-name NextflowBatchSubmit \
  --policy-document file:///dev/stdin <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "NextflowBatchOperations",
      "Effect": "Allow",
      "Action": [
        "batch:DescribeJobDefinitions", "batch:RegisterJobDefinition",
        "batch:DeregisterJobDefinition", "batch:TagResource", "batch:UntagResource",
        "batch:DescribeJobs", "batch:SubmitJob", "batch:TerminateJob",
        "batch:CancelJob", "batch:ListJobs", "batch:DescribeJobQueues",
        "batch:DescribeComputeEnvironments"
      ],
      "Resource": "*"
    },
    {
      "Sid": "NextflowPassTaskRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::399683337364:role/biomate-nextflow-task-role"
    }
  ]
}
EOF
```

---

## LLM API Key (`GALAXY_AI_LLM_PROVIDER=openai_compatible`)

When the backend uses Aliyun DashScope (or any OpenAI-compatible API), the key in `.env` must be a valid DashScope API key — **not** a RAM AccessKey.

| Config key | Expected format | Where to get it |
|------------|-----------------|-----------------|
| `LLM_API_KEY` | `sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` (32 hex chars after `sk-`) | [DashScope console](https://dashscope.console.aliyun.com) → API Keys |
| `LLM_API_URL` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | Fixed for DashScope |
| `LLM_MODEL` | `qwen-plus` (recommended) | DashScope model list |

> **Do NOT use Alibaba Cloud RAM AccessKeys** (`LTAI5t...` / `Ld3Jd...`) as LLM_API_KEY.  
> Those are identity credentials, not DashScope API keys.

### How to verify

```bash
LLM_KEY=$(grep LLM_API_KEY /opt/biomate/.env | cut -d= -f2)
curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $LLM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen-plus","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
  https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
# 200 = key valid, 401 = key invalid
```

### How to update (via Secrets Manager)

The correct place to update the key is Secrets Manager, not the host `.env` directly:

```bash
# Get current secret, update LLM_API_KEY, put it back
aws secretsmanager get-secret-value \
  --secret-id "test/biomate/galaxy-env" \
  --region us-west-2 \
  --query SecretString --output text > /tmp/env.json

# Edit /tmp/env.json to update LLM_API_KEY=<new-key>

aws secretsmanager put-secret-value \
  --secret-id "test/biomate/galaxy-env" \
  --region us-west-2 \
  --secret-string file:///tmp/env.json
```

Then re-run `deploy.sh` to pick up the new value.

---

## Automated pre-flight in `deploy.sh`

Both checks above are now run automatically as **Step 1.5** in `scripts/deploy.sh` before containers are started. Failures emit `::warning::` lines (visible in GHA logs) but do NOT abort the deploy — they surface the problem before it manifests as a silent workflow failure.

---

## Incident log

| Date | Issue | Root cause | Resolution |
|------|-------|-----------|------------|
| 2026-11-12 | All workflow runs failed on test with `rc=1` | `iam:PassRole` missing from `BioMateEc2DeployRole/NextflowBatchSubmit` | Added `PassRole` statement to policy; added deploy.sh pre-flight check |
| 2026-11-12 | AI chat findings returned errors on test | `LLM_API_KEY` was a JWT-like token, not a DashScope API key | Pending: needs correct DashScope key set in Secrets Manager |
