# BioMate Billing — Real-Time Monitoring Guide

**Audience:** Backend programmer setting up the billing infrastructure
**Prerequisite:** Billing system deployed per `README.md` and `TECHNICAL_REFERENCE.md`

---

## 0. Administration Tools to Install

These are the actual software tools your colleague needs to have running. Install them in this order.

### 0.1 RedisInsight (Redis GUI — required)

The primary admin tool for inspecting live cost data, quotas, and job state in Redis.

**Install:**
```bash
# Ubuntu/Debian
wget https://download.redis.io/redisinsight/latest/linux/RedisInsight-latest.deb
sudo dpkg -i RedisInsight-latest.deb
# Or: download from https://redis.io/insight (free)
```

**Connect:**
- Host: `biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com`
- Port: `6379`
- No TLS (internal VPC only — connect via SSH tunnel or from EC2)

**SSH tunnel to connect from laptop:**
```bash
ssh -L 6380:biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379 \
  -i ~/.ssh/your-ec2-key.pem ubuntu@35.89.57.94 -N
# Then connect RedisInsight to localhost:6380
```

**Key namespaces to monitor in RedisInsight:**
| Pattern | Meaning |
|---------|---------|
| `cost:*:month:*` | All user cost breakdowns |
| `quota:*:month:*:limit` | All user quota limits |
| `cost:*:job:*:running` | In-flight Batch job state (JSON string, TTL 35 days) |
| `billing:last_batch_event_ts` | Last Lambda heartbeat |

---

### 0.2 AWS Console Dashboards (required)

**Lambda monitoring:**
1. Go to **AWS Console → Lambda → batch_event_handler** (us-west-2)
2. Click **Monitor** tab → view Invocations, Errors, Duration graphs
3. Do the same for **s3_event_handler** (us-east-1)
4. Set up alarms per Section 4 below

**ElastiCache monitoring:**
1. **AWS Console → ElastiCache → Redis clusters → biomate-billing-redis**
2. Key metrics to watch: `CurrConnections`, `DatabaseMemoryUsagePercentage`, `CacheHits`

**CloudWatch Logs (Lambda output):**
```bash
# View batch_event_handler Lambda logs
aws logs tail /aws/lambda/batch_event_handler --follow --region us-west-2

# View s3_event_handler Lambda logs
aws logs tail /aws/lambda/s3_event_handler --follow --region us-east-1
```

---

### 0.3 Lago Admin UI (required for billing)

Lago is the metered billing platform that generates invoices. You must deploy it before going live.

**Option A — Lago Cloud (fastest):**
1. Sign up at https://app.getlago.com
2. Create organization `biomate`
3. Note your API key → set `LAGO_API_KEY` on Galaxy EC2
4. Note your webhook secret → set `LAGO_WEBHOOK_SECRET` on Galaxy EC2

**Option B — Self-hosted (Docker):**
```bash
git clone https://github.com/getlago/lago.git
cd lago
docker-compose up -d
# Admin UI at http://localhost:3000
# API at http://localhost:3000/api/v1
```

**Post-install: create the 9 billable metrics** (see `TECHNICAL_REFERENCE.md` Section 3.4 for exact JSON payloads):
```bash
# Example: create llm_input_tokens metric
curl -X POST https://api.getlago.com/api/v1/billable_metrics \
  -H "Authorization: Bearer $LAGO_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"billable_metric": {"name": "LLM Input Tokens", "code": "llm_input_tokens",
       "aggregation_type": "sum_agg", "field_name": "tokens"}}'
```

---

### 0.4 Stripe Dashboard (required for payments)

1. Go to https://dashboard.stripe.com
2. Create the 5 subscription products (see `README.md` → Stripe section)
3. Configure webhook endpoint: `https://api.biomate.dev/webhooks/stripe`
   - Events to listen for: `checkout.session.completed`, `customer.subscription.updated`,
     `customer.subscription.deleted`, `invoice.payment_failed`, `invoice.payment_succeeded`,
     `payment_intent.payment_failed`
4. Copy webhook signing secret → set `STRIPE_WEBHOOK_SECRET` on Node.js server

**Stripe billing dashboard** (live revenue view):
- https://dashboard.stripe.com/billing → shows all subscriptions, MRR, churn

---

### 0.5 Grafana (optional, recommended for team dashboards)

```bash
# Docker
docker run -d -p 3000:3000 --name grafana grafana/grafana

# Or install on EC2
sudo apt-get install -y grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
# Admin UI at http://localhost:3000 (default: admin/admin)
```

**Connect to Redis:**
1. Install plugin: `grafana-cli plugins install redis-datasource`
2. Add datasource → Redis → URL: `redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379` (via SSH tunnel)

**Connect to CloudWatch:**
1. Add datasource → CloudWatch → use EC2 instance role (no keys needed if running on EC2)

---

## 1. What Gets Monitored

| Layer | What it tracks | Where data lives |
|-------|---------------|-----------------|
| LLM costs | Tokens + USD per model per user | Redis `cost:{uid}:month:{YY-MM}:llm` |
| Compute costs | AWS Batch vCPU, GPU, memory seconds | Redis `cost:{uid}:month:{YY-MM}:compute` |
| Storage costs | S3 GB-months | Redis `cost:{uid}:month:{YY-MM}:storage` |
| Quota usage | % of monthly limit consumed | Redis `quota:{uid}:month:{YY-MM}:limit` |
| Running jobs | In-flight Batch jobs with live cost | Redis `job:{job_id}:*` |
| Lambda health | Last event timestamp | Redis `billing:last_batch_event_ts` |

---

## 2. Admin API Endpoints

Both require the `X-Internal-Key` header (value = `BILLING_INTERNAL_KEY` env var).

### 2.1 All Users — Live Costs

```bash
curl -s -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  http://localhost:8081/internal/billing/admin/users | python3 -m json.tool
```

Response:
```json
{
  "month": "2026-02",
  "user_count": 42,
  "users": [
    { "user_id": "7", "total_usd": 12.34, "quota_usd": 30.0, "pct": 41.1,
      "llm_usd": 5.20, "compute_usd": 6.80, "storage_usd": 0.34 },
    ...
  ]
}
```

Users are sorted by total spend descending. Use this to spot high spenders.

### 2.2 System Health

```bash
curl -s -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  http://localhost:8081/internal/billing/admin/health | python3 -m json.tool
```

Response:
```json
{
  "redis": "ok",
  "active_jobs": 3,
  "last_batch_event_age_sec": 145,
  "lago": "ok",
  "total_users_tracked": 42,
  "month": "2026-02"
}
```

**Alarm thresholds:**

| Field | Warn | Critical |
|-------|------|----------|
| `redis` | — | anything other than `"ok"` |
| `last_batch_event_age_sec` | > 600s (10 min) | > 3600s (1 hr) — Lambda may be down |
| `lago` | `"disabled"` | `"error: ..."` |

---

## 3. Redis Monitoring Commands

Connect to the ElastiCache cluster:
```bash
redis-cli -u $REDIS_URL
```

### Inspect a specific user

```bash
# Current month costs
MONTH=$(date +%Y-%m)
USER_ID=7

redis-cli -u $REDIS_URL HGETALL "cost:${USER_ID}:month:${MONTH}:llm"
redis-cli -u $REDIS_URL HGETALL "cost:${USER_ID}:month:${MONTH}:compute"
redis-cli -u $REDIS_URL GET     "cost:${USER_ID}:month:${MONTH}:total"
redis-cli -u $REDIS_URL GET     "quota:${USER_ID}:month:${MONTH}:limit"
```

### Find all users over 80% quota this month

```bash
MONTH=$(date +%Y-%m)
redis-cli -u $REDIS_URL KEYS "quota:*:month:${MONTH}:limit" | while read key; do
  uid=$(echo $key | cut -d: -f2)
  limit=$(redis-cli -u $REDIS_URL GET "$key")
  total=$(redis-cli -u $REDIS_URL GET "cost:${uid}:month:${MONTH}:total")
  pct=$(python3 -c "print(f'{float(\"${total:-0}\")/float(\"${limit:-1}\")*100:.0f}%')" 2>/dev/null)
  echo "$pct  user=$uid  used=$total  limit=$limit"
done | sort -rn
```

### Check Redis memory pressure

```bash
redis-cli -u $REDIS_URL INFO memory | grep -E "used_memory_human|maxmemory_human|mem_fragmentation_ratio"
```

**Alert if:** `used_memory` > 80% of `maxmemory`, or `mem_fragmentation_ratio` > 1.5.

---

## 4. AWS CloudWatch Alarms

Set these up in the AWS Console or via CLI after deploying the Lambda functions.

### 4.1 batch_event_handler Lambda errors

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "billing-batch-lambda-errors" \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=batch_event_handler \
  --statistic Sum --period 300 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-west-2:399683337364:billing-alerts
```

### 4.2 s3_event_handler Lambda errors

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "billing-s3-lambda-errors" \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=s3_event_handler \
  --statistic Sum --period 300 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:399683337364:billing-alerts
```

### 4.3 ElastiCache memory alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "billing-redis-memory-high" \
  --namespace AWS/ElastiCache \
  --metric-name DatabaseMemoryUsagePercentage \
  --dimensions Name=CacheClusterId,Value=biomate-billing-redis \
  --statistic Average --period 300 --threshold 80 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:us-west-2:399683337364:billing-alerts
```

> **Note:** Replace the SNS ARN with your actual alerts topic. Create it with:
> ```bash
> aws sns create-topic --name billing-alerts --region us-west-2
> aws sns subscribe --topic-arn <arn> --protocol email --notification-endpoint ops@biomate.dev
> ```

---

## 5. Monitoring Script (Daily Cron)

Save as `scripts/billing_health_check.sh` and run via cron:

```bash
#!/bin/bash
# Daily billing health check — email ops if anything is wrong
# Cron: 0 9 * * * /path/to/billing_health_check.sh

BILLING_URL="http://172.31.8.116:8081"
KEY="${BILLING_INTERNAL_KEY}"

# Health check
HEALTH=$(curl -s -H "X-Internal-Key: $KEY" \
  "${BILLING_URL}/internal/billing/admin/health")

REDIS=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['redis'])")
LAGO=$(echo "$HEALTH"  | python3 -c "import sys,json; print(json.load(sys.stdin)['lago'])")
LAST=$(echo "$HEALTH"  | python3 -c "import sys,json; print(json.load(sys.stdin).get('last_batch_event_age_sec','null'))")

ERRORS=""
[ "$REDIS" != "ok" ]   && ERRORS+="REDIS ERROR: $REDIS\n"
[ "$LAGO"  != "ok" ]   && ERRORS+="LAGO ERROR: $LAGO\n"
[ "$LAST"  != "null" ] && [ "$LAST" -gt 3600 ] && \
  ERRORS+="LAMBDA STALE: last_batch_event was ${LAST}s ago\n"

if [ -n "$ERRORS" ]; then
  echo -e "BioMate billing alert:\n$ERRORS" | \
    mail -s "[BioMate] Billing system alert" ops@biomate.dev
fi

# Top spenders report
echo "=== Top 10 spenders this month ==="
curl -s -H "X-Internal-Key: $KEY" \
  "${BILLING_URL}/internal/billing/admin/users" | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'Month: {d[\"month\"]}  Users: {d[\"user_count\"]}')
for u in d['users'][:10]:
    print(f'  user={u[\"user_id\"]:>6}  \${u[\"total_usd\"]:6.2f} / \${u[\"quota_usd\"]:5.1f}  ({u[\"pct\"]:5.1f}%)')
"
```

---

## 6. Lago Analytics Dashboard

Once Lago is deployed, navigate to:

- **Lago UI:** `https://app.getlago.com` (or your self-hosted URL)
- **Analytics → Usage** — see per-metric consumption per customer
- **Customers → [user]** — full billing history, invoices, subscriptions
- **Webhooks → Logs** — verify events are being received

Key Lago billable metric codes (must be created before going live):

| Code | Properties field | Description |
|------|-----------------|-------------|
| `llm_input_tokens` | `tokens` | LLM input token usage |
| `llm_output_tokens` | `tokens` | LLM output token usage |
| `batch_vcpu_seconds` | `seconds` | AWS Batch vCPU × duration |
| `batch_gpu_seconds` | `seconds` | AWS Batch GPU × duration |
| `batch_memory_gb_sec` | `gb_seconds` | AWS Batch memory GB × duration |
| `s3_storage_gb_hours` | `gb_hours` | S3 storage (30-day retention estimate) |
| `s3_get_requests` | `count` | S3 GET request count |
| `s3_put_requests` | `count` | S3 PUT request count |
| `s3_data_transfer_gb` | `gb` | S3 cross-region transfer GB |

Full setup details: `TECHNICAL_REFERENCE.md` Section 4.

---

## 7. Grafana Dashboard (Optional)

If you want a visual dashboard, connect Grafana to Redis using the **Redis Data Source** plugin:

1. Install plugin: `grafana-cli plugins install redis-datasource`
2. Add data source: `redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379`
3. Import dashboard JSON from `docs/billing/grafana_dashboard.json` (template — create as needed)

Useful panel queries:
- **Total cost trend:** `GET cost:*:month:*:total` → time series
- **Active jobs:** `KEYS cost:*:job:*:running` → stat panel (count)
- **Quota utilization:** scatter plot of `total/limit` per user

---

## 8. Quick Diagnostic Checklist

Run this after initial setup to confirm everything is wired:

```bash
BILLING_URL="http://localhost:8081"
KEY="${BILLING_INTERNAL_KEY}"

echo "1. Redis reachable?"
redis-cli -u $REDIS_URL PING

echo "2. Billing API up?"
curl -s "${BILLING_URL}/api/version" | python3 -m json.tool

echo "3. Health check?"
curl -s -H "X-Internal-Key: $KEY" "${BILLING_URL}/internal/billing/admin/health" \
  | python3 -m json.tool

echo "4. Seed test user (user_id=1) and read back?"
MONTH=$(date +%Y-%m)
redis-cli -u $REDIS_URL SET "quota:1:month:${MONTH}:limit" 30.0
redis-cli -u $REDIS_URL HSET "cost:1:month:${MONTH}:llm" input_usd 1.23 output_usd 0.45
redis-cli -u $REDIS_URL SET  "cost:1:month:${MONTH}:total" 1.68
curl -s -H "Authorization: 1" "${BILLING_URL}/api/billing/usage"

echo "5. Admin users endpoint shows user 1?"
curl -s -H "X-Internal-Key: $KEY" "${BILLING_URL}/internal/billing/admin/users" \
  | python3 -c "import sys,json; [print(u) for u in json.load(sys.stdin)['users']]"
```

Expected: step 5 shows `user_id: "1"` with `total_usd: 1.68`.

---

*See also: `README.md` for infrastructure checklist, `TECHNICAL_REFERENCE.md` for full API reference.*
