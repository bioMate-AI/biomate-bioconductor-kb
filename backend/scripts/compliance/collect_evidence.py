#!/usr/bin/env python3
"""
BioMate SOC2/HIPAA Evidence Collector
Runs monthly via Lambda or cron. Saves timestamped JSON to S3.
Each check returns: { control, status, detail, evidence, passed }
"""
import json, datetime, os, sys, gzip
import boto3
from botocore.exceptions import ClientError

ACCOUNT_ID  = "399683337364"
REGION      = os.environ.get("AWS_REGION", "us-west-2")
BUCKET      = f"biomate-compliance-evidence-{ACCOUNT_ID}"
SNS_ARN     = f"arn:aws:sns:{REGION}:{ACCOUNT_ID}:biomate-compliance-alerts"
PROD_INSTANCE = "i-06696b0d91f4346e0"

session = boto3.Session(region_name=REGION)

def check(control: str, passed: bool, detail: str, evidence: dict) -> dict:
    return {"control": control, "passed": passed, "detail": detail,
            "evidence": evidence, "timestamp": datetime.datetime.utcnow().isoformat()}

# ── 1. CloudTrail enabled and logging ─────────────────────────────────────────
def check_cloudtrail():
    ct = session.client("cloudtrail")
    trails = ct.describe_trails(includeShadowTrails=False).get("trailList", [])
    if not trails:
        return check("cloudtrail_enabled", False,
                     "No CloudTrail trail configured in us-west-2",
                     {"trails": []})
    statuses = []
    for t in trails:
        try:
            s = ct.get_trail_status(Name=t["TrailARN"])
            statuses.append({"name": t["Name"], "logging": s.get("IsLogging", False)})
        except ClientError:
            statuses.append({"name": t["Name"], "logging": None})
    all_logging = all(s["logging"] for s in statuses)
    return check("cloudtrail_enabled", all_logging,
                 f"{len(statuses)} trail(s); all logging: {all_logging}", {"trails": statuses})

# ── 2. S3 public access blocked on all buckets ────────────────────────────────
def check_s3_public_access():
    s3 = session.client("s3")
    buckets = [b["Name"] for b in s3.list_buckets()["Buckets"]]
    failures = []
    for b in buckets:
        try:
            cfg = s3.get_public_access_block(Bucket=b)["PublicAccessBlockConfiguration"]
            if not all(cfg.get(k) for k in [
                "BlockPublicAcls","IgnorePublicAcls","BlockPublicPolicy","RestrictPublicBuckets"
            ]):
                failures.append(b)
        except ClientError as e:
            if "NoSuchPublicAccessBlockConfiguration" in str(e):
                failures.append(b)
    return check("s3_public_access_blocked", len(failures) == 0,
                 f"{len(buckets)} buckets checked; {len(failures)} not fully blocked",
                 {"total": len(buckets), "failures": failures})

# ── 3. S3 versioning on compliance evidence bucket ────────────────────────────
def check_s3_versioning():
    s3 = session.client("s3")
    v = s3.get_bucket_versioning(Bucket=BUCKET).get("Status", "Disabled")
    return check("s3_evidence_versioning", v == "Enabled",
                 f"Compliance bucket versioning: {v}", {"bucket": BUCKET, "status": v})

# ── 4. KMS key rotation enabled on all customer-managed keys ─────────────────
def check_kms_rotation():
    kms = session.client("kms")
    keys = kms.list_keys()["Keys"]
    results = []
    for k in keys:
        try:
            meta = kms.describe_key(KeyId=k["KeyId"])["KeyMetadata"]
            if meta["KeyManager"] != "CUSTOMER":
                continue
            rotation = kms.get_key_rotation_status(KeyId=k["KeyId"])["KeyRotationEnabled"]
            results.append({"keyId": k["KeyId"][:8]+"...", "rotation": rotation, "state": meta["KeyState"]})
        except ClientError:
            pass
    failed = [r for r in results if not r["rotation"]]
    return check("kms_key_rotation", len(failed) == 0,
                 f"{len(results)} CMKs checked; {len(failed)} without rotation",
                 {"keys": results})

# ── 5. IAM root access keys absent ───────────────────────────────────────────
def check_root_access_keys():
    iam = session.client("iam")
    report = iam.generate_credential_report()
    import time; time.sleep(2)
    content = iam.get_credential_report()["Content"].decode()
    for line in content.splitlines()[1:]:
        cols = line.split(",")
        if cols[0] == "<root_account>":
            key1 = cols[8] == "true"
            key2 = cols[13] == "true"
            return check("root_no_access_keys", not key1 and not key2,
                         f"Root key1_active={key1} key2_active={key2}",
                         {"key1_active": key1, "key2_active": key2})
    return check("root_no_access_keys", True, "Root account row not found in report", {})

# ── 6. MFA on root account ────────────────────────────────────────────────────
def check_root_mfa():
    iam = session.client("iam")
    summary = iam.get_account_summary()["SummaryMap"]
    mfa = summary.get("AccountMFAEnabled", 0)
    return check("root_mfa_enabled", mfa == 1,
                 f"Root MFA enabled: {bool(mfa)}", {"AccountMFAEnabled": mfa})

# ── 7. ElastiCache encryption (at-rest + in-transit) ─────────────────────────
def check_elasticache_encryption():
    ec = session.client("elasticache")
    groups = ec.describe_replication_groups().get("ReplicationGroups", [])
    clusters = ec.describe_cache_clusters().get("CacheClusters", [])
    findings = []
    for g in groups:
        at_rest = g.get("AtRestEncryptionEnabled", False)
        transit = g.get("TransitEncryptionEnabled", False)
        findings.append({"id": g["ReplicationGroupId"], "at_rest": at_rest, "transit": transit,
                          "passed": at_rest and transit})
    for c in clusters:
        if c.get("ReplicationGroupId"):
            continue
        at_rest = c.get("AtRestEncryptionEnabled", False)
        transit = c.get("TransitEncryptionEnabled", False)
        findings.append({"id": c["CacheClusterId"], "at_rest": at_rest, "transit": transit,
                          "passed": at_rest and transit})
    failed = [f for f in findings if not f["passed"]]
    return check("elasticache_encrypted", len(failed) == 0,
                 f"{len(findings)} cache(s); {len(failed)} without full encryption",
                 {"clusters": findings})

# ── 8. EC2 IMDSv2 required on production instance ────────────────────────────
def check_imdsv2():
    ec2 = session.client("ec2")
    r = ec2.describe_instances(InstanceIds=[PROD_INSTANCE])
    inst = r["Reservations"][0]["Instances"][0]
    tokens = inst.get("MetadataOptions", {}).get("HttpTokens", "optional")
    return check("ec2_imdsv2_required", tokens == "required",
                 f"Production EC2 IMDSv2 HttpTokens={tokens}", {"HttpTokens": tokens, "instanceId": PROD_INSTANCE})

# ── 9. Security groups — no 0.0.0.0/0 on dangerous ports ────────────────────
def check_security_groups():
    ec2 = session.client("ec2")
    sgs = ec2.describe_security_groups()["SecurityGroups"]
    DANGER_PORTS = {22, 3306, 5432, 6379, 27017}
    violations = []
    for sg in sgs:
        for perm in sg.get("IpPermissions", []):
            from_p = perm.get("FromPort", 0)
            to_p   = perm.get("ToPort", 65535)
            danger = DANGER_PORTS.intersection(range(from_p, to_p + 1))
            if not danger:
                continue
            for r in perm.get("IpRanges", []):
                if r.get("CidrIp") == "0.0.0.0/0":
                    violations.append({"sg": sg["GroupId"], "name": sg.get("GroupName"), "ports": list(danger)})
    return check("sg_no_public_dangerous_ports", len(violations) == 0,
                 f"{len(violations)} security group(s) expose dangerous ports to 0.0.0.0/0",
                 {"violations": violations})

# ── 10. S3 server-side encryption on production data buckets ─────────────────
def check_s3_encryption():
    s3 = session.client("s3")
    target_buckets = [b for b in [b["Name"] for b in s3.list_buckets()["Buckets"]]
                      if "biomate" in b and "compliance" not in b]
    results = []
    for b in target_buckets:
        try:
            enc = s3.get_bucket_encryption(Bucket=b)
            rules = enc["ServerSideEncryptionConfiguration"]["Rules"]
            algo = rules[0]["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"]
            results.append({"bucket": b, "algorithm": algo, "passed": True})
        except ClientError as e:
            if "ServerSideEncryptionConfigurationNotFoundError" in str(e):
                results.append({"bucket": b, "algorithm": None, "passed": False})
    failed = [r for r in results if not r["passed"]]
    return check("s3_default_encryption", len(failed) == 0,
                 f"{len(results)} buckets; {len(failed)} without default encryption",
                 {"buckets": results})

# ── 11. Lambda — no plaintext secrets in env vars ────────────────────────────
def check_lambda_secrets():
    lm = session.client("lambda")
    fns = lm.list_functions()["Functions"]
    SECRET_PATTERNS = ["secret", "password", "key", "token", "api_key"]
    findings = []
    for fn in fns:
        env = fn.get("Environment", {}).get("Variables", {})
        for k, v in env.items():
            if any(p in k.lower() for p in SECRET_PATTERNS) and len(v) > 8:
                findings.append({"function": fn["FunctionName"], "key": k})
    return check("lambda_no_plaintext_secrets", len(findings) == 0,
                 f"{len(fns)} Lambda(s); {len(findings)} potential plaintext secret(s) in env",
                 {"findings": findings})

# ── 12. RDS / PostgreSQL backup retention ≥ 7 days ───────────────────────────
def check_rds_backup():
    rds = session.client("rds")
    instances = rds.describe_db_instances().get("DBInstances", [])
    if not instances:
        return check("rds_backup_retention", None,
                     "No RDS instances found — PostgreSQL runs on EC2 (Docker). Manual backup process required.",
                     {"note": "Backup covered by EC2 EBS snapshots or pg_dump cron"})
    results = []
    for db in instances:
        ret = db.get("BackupRetentionPeriod", 0)
        results.append({"id": db["DBInstanceIdentifier"], "retention_days": ret, "passed": ret >= 7})
    failed = [r for r in results if not r["passed"]]
    return check("rds_backup_retention", len(failed) == 0,
                 f"{len(results)} RDS instance(s); {len(failed)} with retention < 7 days",
                 {"instances": results})

# ── 13. CloudWatch alarm — auth failures ──────────────────────────────────────
def check_cloudwatch_alarms():
    cw = session.client("cloudwatch")
    alarms = cw.describe_alarms()["MetricAlarms"]
    auth_alarms = [a["AlarmName"] for a in alarms if "auth" in a["AlarmName"].lower()]
    return check("cloudwatch_auth_alarm", len(auth_alarms) > 0,
                 f"{len(auth_alarms)} auth-related alarm(s) found",
                 {"alarms": auth_alarms})

# ── 14. IAM password policy ───────────────────────────────────────────────────
def check_iam_password_policy():
    iam = session.client("iam")
    try:
        pol = iam.get_account_password_policy()["PasswordPolicy"]
        passed = (pol.get("MinimumPasswordLength", 0) >= 12 and
                  pol.get("RequireUppercaseCharacters") and
                  pol.get("RequireLowercaseCharacters") and
                  pol.get("RequireNumbers") and
                  pol.get("RequireSymbols") and
                  pol.get("MaxPasswordAge", 999) <= 90)
        return check("iam_password_policy", passed,
                     f"MinLen={pol.get('MinimumPasswordLength')} MaxAge={pol.get('MaxPasswordAge')} MFA={pol.get('HardExpiry')}",
                     pol)
    except ClientError:
        return check("iam_password_policy", False, "No account password policy set", {})

# ── Runner ────────────────────────────────────────────────────────────────────

CHECKS = [
    check_cloudtrail,
    check_s3_public_access,
    check_s3_versioning,
    check_kms_rotation,
    check_root_access_keys,
    check_root_mfa,
    check_elasticache_encryption,
    check_ec2_imdsv2 := check_imdsv2,
    check_security_groups,
    check_s3_encryption,
    check_lambda_secrets,
    check_rds_backup,
    check_cloudwatch_alarms,
    check_iam_password_policy,
]

def run(upload=True, alert=True):
    results = []
    for fn in CHECKS:
        try:
            r = fn()
        except Exception as e:
            r = check(fn.__name__, False, f"Check error: {e}", {"error": str(e)})
        results.append(r)
        status = "✅" if r["passed"] else ("⚠️" if r["passed"] is None else "❌")
        print(f"  {status} {r['control']}: {r['detail']}")

    passed  = sum(1 for r in results if r["passed"] is True)
    failed  = sum(1 for r in results if r["passed"] is False)
    unknown = sum(1 for r in results if r["passed"] is None)
    print(f"\nSummary: {passed} passed / {failed} failed / {unknown} N/A of {len(results)} checks")

    date_tag = datetime.datetime.utcnow().strftime("%Y-%m")
    run_ts   = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    payload  = {"run_at": run_ts, "account": ACCOUNT_ID, "region": REGION,
                "summary": {"passed": passed, "failed": failed, "unknown": unknown},
                "checks": results}

    if upload:
        s3 = session.client("s3")
        key = f"{date_tag}/{run_ts}_evidence.json.gz"
        s3.put_object(
            Bucket=BUCKET, Key=key,
            Body=gzip.compress(json.dumps(payload, default=str).encode()),
            ContentEncoding="gzip", ContentType="application/json",
            StorageClass="STANDARD",
        )
        print(f"Uploaded: s3://{BUCKET}/{key}")

    if alert and failed > 0:
        sns = session.client("sns")
        failing = [r["control"] for r in results if r["passed"] is False]
        sns.publish(
            TopicArn=SNS_ARN,
            Subject=f"[BioMate Compliance] {failed} control(s) FAILING — {run_ts}",
            Message=f"Failed controls:\n" + "\n".join(f"  ❌ {c}" for c in failing) +
                    f"\n\nSee evidence: s3://{BUCKET}/{date_tag}/\n\nAccount: {ACCOUNT_ID} / {REGION}"
        )
        print(f"SNS alert sent for {failed} failure(s)")

    return payload

def lambda_handler(event, context):
    return run(upload=True, alert=True)

if __name__ == "__main__":
    run(upload="--no-upload" not in sys.argv, alert="--no-alert" not in sys.argv)
