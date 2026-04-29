#!/usr/bin/env python3
"""
Exports audit_log rows older than 90 days to S3 Glacier IR, then deletes them.
Run daily via systemd timer. Requires: psycopg2-binary, boto3.
"""
import os, sys, json, gzip, datetime, logging
import psycopg2
import boto3

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger("audit-glacier")

DB_URL     = os.environ["DATABASE_URL"]
S3_BUCKET  = os.environ.get("AUDIT_GLACIER_BUCKET", "biomate-production-data-399683337364")
S3_PREFIX  = "audit-logs-glacier"
RETAIN_DAYS = int(os.environ.get("AUDIT_RETAIN_DAYS", "90"))

def export():
    cutoff = datetime.datetime.utcnow() - datetime.timedelta(days=RETAIN_DAYS)
    date_tag = cutoff.strftime("%Y%m%d")
    s3_key = f"{S3_PREFIX}/{date_tag}/audit_logs_{datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}.jsonl.gz"

    conn = psycopg2.connect(DB_URL)
    conn.autocommit = False
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) FROM audit_logs WHERE timestamp < %s", (cutoff,))
    count = cur.fetchone()[0]
    if count == 0:
        log.info("No audit log rows older than %d days — nothing to export.", RETAIN_DAYS)
        conn.close()
        return

    log.info("Exporting %d rows older than %s to s3://%s/%s", count, cutoff.date(), S3_BUCKET, s3_key)

    # Fetch rows
    cur.execute("""
        SELECT id, timestamp, action, user_id, resource_type, resource_id,
               ip_address, user_agent, request_id, session_id,
               details, phi_types, rule_name, severity, metadata
        FROM audit_logs
        WHERE timestamp < %s
        ORDER BY timestamp ASC
    """, (cutoff,))
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()

    # Write gzip JSONL to S3 Glacier IR
    s3 = boto3.client("s3", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    body = gzip.compress(
        b"\n".join(json.dumps(dict(zip(cols, [
            str(v) if isinstance(v, (datetime.datetime, datetime.date)) else v
            for v in row
        ])), default=str).encode() for row in rows)
    )
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=s3_key,
        Body=body,
        StorageClass="GLACIER_IR",
        ContentEncoding="gzip",
        ContentType="application/x-ndjson",
        Metadata={
            "exported-at": datetime.datetime.utcnow().isoformat(),
            "row-count": str(count),
            "cutoff-date": str(cutoff.date()),
        }
    )
    log.info("Uploaded %d bytes to s3://%s/%s (GLACIER_IR)", len(body), S3_BUCKET, s3_key)

    # Delete exported rows atomically
    cur.execute("DELETE FROM audit_logs WHERE timestamp < %s", (cutoff,))
    deleted = cur.rowcount
    conn.commit()
    log.info("Deleted %d rows from audit_logs (exported %d, deleted %d).", deleted, count, deleted)

    if count != deleted:
        log.warning("Row count mismatch: exported %d but deleted %d", count, deleted)

    conn.close()

if __name__ == "__main__":
    try:
        export()
    except Exception as e:
        log.error("Export failed: %s", e, exc_info=True)
        sys.exit(1)
