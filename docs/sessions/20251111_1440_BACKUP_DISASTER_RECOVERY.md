# Backup and Disaster Recovery Plan
**Version:** 1.0
**Date:** 2025-11-11
**Classification:** CONFIDENTIAL
**Owner:** Operations Team

---

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Disaster Recovery Strategy](#disaster-recovery-strategy)
4. [Recovery Time Objectives](#recovery-time-objectives)
5. [Backup Procedures](#backup-procedures)
6. [Recovery Procedures](#recovery-procedures)
7. [Testing and Validation](#testing-and-validation)
8. [Compliance Requirements](#compliance-requirements)

---

## Overview

### Purpose
This document defines backup and disaster recovery procedures for BioMate AI to ensure:
- Business continuity (SOC 2 CC7.3)
- Data integrity and availability
- HIPAA compliance for PHI protection
- Rapid recovery from disasters

### Scope
- Application databases
- User data and PHI
- Configuration files
- Application code
- Infrastructure as Code (IaC)
- Audit logs

---

## Backup Strategy

### Backup Types

#### 1. Database Backups

**PostgreSQL Production Database**
- **Frequency:** Continuous (WAL archiving) + Daily full backup
- **Retention:** 30 days daily, 12 weeks weekly, 7 years annual
- **Location:** AWS S3 (encrypted, versioned, cross-region replication)
- **Encryption:** AES-256
- **Method:** `pg_dump` with compression

**Command:**
```bash
# Full backup
pg_dump -U biomate -h localhost -Fc biomate_prod | \
  openssl enc -aes-256-cbc -salt -pbkdf2 -out backup_$(date +%Y%m%d).sql.enc

# Upload to S3
aws s3 cp backup_$(date +%Y%m%d).sql.enc \
  s3://biomate-backups/database/$(date +%Y/%m/%d)/ \
  --server-side-encryption AES256
```

**SQLite Galaxy Database (if used)**
- **Frequency:** Every 6 hours
- **Retention:** 7 days
- **Location:** Local + S3
- **Encryption:** AES-256

#### 2. File Storage Backups

**User Uploads and Datasets**
- **Frequency:** Real-time (S3 versioning enabled)
- **Retention:** 90 days
- **Location:** AWS S3 with versioning
- **Encryption:** S3-SSE (Server-side encryption)

#### 3. Configuration Backups

**Environment Variables, Secrets**
- **Frequency:** On every change
- **Location:** AWS Secrets Manager (automatic backups)
- **Retention:** Indefinite

**Application Configuration**
- **Frequency:** Git commits (automatic)
- **Location:** GitHub (private repository)
- **Retention:** Indefinite

#### 4. Audit Log Backups

**Security and Compliance Logs**
- **Frequency:** Real-time streaming to SIEM
- **Retention:** 7 years (HIPAA requirement: 6 years minimum)
- **Location:** CloudWatch Logs + S3
- **Encryption:** AES-256
- **Immutability:** Write-once-read-many (WORM) compliance

### Backup Schedule Matrix

| Asset | Frequency | Retention | Encryption | Location |
|-------|-----------|-----------|------------|----------|
| Database (Full) | Daily 2 AM UTC | 30 days | AES-256 | S3 us-west-2 |
| Database (Incremental) | Continuous (WAL) | 7 days | AES-256 | S3 us-west-2 |
| User Files | Real-time | 90 days | S3-SSE | S3 us-west-2 + us-east-1 |
| Audit Logs | Real-time | 7 years | AES-256 | S3 + Glacier |
| Configuration | On change | Indefinite | AWS KMS | Secrets Manager |
| Code | On commit | Indefinite | GitHub | GitHub |

---

## Disaster Recovery Strategy

### Disaster Scenarios

#### Scenario 1: Database Failure
**Impact:** Loss of user data, workflow configurations
**RTO:** 2 hours
**RPO:** 15 minutes

**Recovery Steps:**
1. Spin up new RDS instance
2. Restore from latest backup
3. Apply WAL logs for point-in-time recovery
4. Update DNS/connection strings
5. Validate data integrity
6. Resume operations

#### Scenario 2: Complete AWS Region Failure
**Impact:** Total service outage
**RTO:** 4 hours
**RPO:** 1 hour

**Recovery Steps:**
1. Activate DR region (us-east-1)
2. Restore database from cross-region replica
3. Deploy application from IaC
4. Update DNS to failover region
5. Validate functionality
6. Communicate with users

#### Scenario 3: Ransomware Attack
**Impact:** Encrypted production systems
**RTO:** 8 hours
**RPO:** 24 hours

**Recovery Steps:**
1. Isolate infected systems
2. DO NOT pay ransom
3. Rebuild infrastructure from clean backups
4. Restore database from pre-infection backup
5. Apply all security patches
6. Enhance monitoring
7. Conduct security audit

#### Scenario 4: Data Corruption
**Impact:** Partial data loss or corruption
**RTO:** 4 hours
**RPO:** 15 minutes

**Recovery Steps:**
1. Identify corruption timestamp
2. Use point-in-time recovery to restore to before corruption
3. Validate recovered data
4. Investigate root cause

---

## Recovery Time Objectives

### RTO (Recovery Time Objective)
Maximum acceptable downtime:

| Priority | Service | RTO | Business Impact |
|----------|---------|-----|-----------------|
| P0 | Production Database | 2 hours | Complete service outage |
| P0 | Application Servers | 2 hours | Complete service outage |
| P1 | User File Storage | 4 hours | Degraded functionality |
| P2 | Audit Logs | 24 hours | Compliance risk |
| P2 | Monitoring | 4 hours | Reduced visibility |

### RPO (Recovery Point Objective)
Maximum acceptable data loss:

| Data Type | RPO | Backup Method |
|-----------|-----|---------------|
| Database | 15 minutes | WAL continuous archiving |
| User Files | 0 (real-time) | S3 versioning |
| Audit Logs | 0 (real-time) | CloudWatch streaming |
| Configuration | 0 | Git + Secrets Manager |

---

## Backup Procedures

### Automated Daily Backup Script

Create `/home/biomate/scripts/backup.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/biomate_backups"
S3_BUCKET="s3://biomate-backups"
ENCRYPTION_KEY=$(cat /etc/biomate/backup_encryption.key)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# 1. Database backup
echo "[$(date)] Starting database backup..."
pg_dump -U biomate -h localhost -Fc biomate_prod | \
  openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:<(echo "$ENCRYPTION_KEY") \
  -out "$BACKUP_DIR/database_${BACKUP_DATE}.sql.enc"

# 2. Configuration backup
echo "[$(date)] Backing up configuration..."
tar -czf "$BACKUP_DIR/config_${BACKUP_DATE}.tar.gz" \
  /home/biomate/backend/config/ \
  /home/biomate/frontend/.env

# Encrypt configuration
openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:<(echo "$ENCRYPTION_KEY") \
  -in "$BACKUP_DIR/config_${BACKUP_DATE}.tar.gz" \
  -out "$BACKUP_DIR/config_${BACKUP_DATE}.tar.gz.enc"
rm "$BACKUP_DIR/config_${BACKUP_DATE}.tar.gz"

# 3. Upload to S3
echo "[$(date)] Uploading to S3..."
aws s3 sync "$BACKUP_DIR/" \
  "$S3_BUCKET/daily/$(date +%Y/%m/%d)/" \
  --server-side-encryption AES256 \
  --storage-class STANDARD_IA

# 4. Verify backup
echo "[$(date)] Verifying backup integrity..."
aws s3api head-object \
  --bucket biomate-backups \
  --key "daily/$(date +%Y/%m/%d)/database_${BACKUP_DATE}.sql.enc" \
  > /dev/null && echo "Backup verified"

# 5. Cleanup old local backups
rm -rf "$BACKUP_DIR"

# 6. Log completion
echo "[$(date)] Backup completed successfully" | \
  logger -t biomate-backup -p user.info

# 7. Send notification
curl -X POST https://api.biomate.ai/internal/backup-status \
  -H "Authorization: Bearer $INTERNAL_API_KEY" \
  -d '{"status":"success","date":"'"$BACKUP_DATE"'"}'
```

### Cron Schedule

```cron
# Daily backups at 2 AM UTC
0 2 * * * /home/biomate/scripts/backup.sh >> /var/log/biomate-backup.log 2>&1

# Weekly full backup on Sundays at 3 AM
0 3 * * 0 /home/biomate/scripts/weekly-backup.sh

# Monthly backup retention cleanup
0 4 1 * * /home/biomate/scripts/cleanup-old-backups.sh
```

---

## Recovery Procedures

### Database Recovery

#### Full Database Restore

```bash
#!/bin/bash
# Restore from encrypted backup

BACKUP_FILE="s3://biomate-backups/daily/2025/11/11/database_20251111_020000.sql.enc"
ENCRYPTION_KEY=$(cat /etc/biomate/backup_encryption.key)

# Download backup
aws s3 cp "$BACKUP_FILE" /tmp/restore.sql.enc

# Decrypt backup
openssl enc -aes-256-cbc -d -pbkdf2 -pass file:<(echo "$ENCRYPTION_KEY") \
  -in /tmp/restore.sql.enc -out /tmp/restore.sql

# Stop application
systemctl stop biomate-frontend
systemctl stop biomate-backend

# Drop and recreate database
psql -U postgres -c "DROP DATABASE IF EXISTS biomate_prod;"
psql -U postgres -c "CREATE DATABASE biomate_prod OWNER biomate;"

# Restore database
pg_restore -U biomate -d biomate_prod -j 4 /tmp/restore.sql

# Verify restoration
psql -U biomate -d biomate_prod -c "SELECT COUNT(*) FROM users;"

# Restart application
systemctl start biomate-backend
systemctl start biomate-frontend

# Cleanup
rm /tmp/restore.sql /tmp/restore.sql.enc
```

#### Point-in-Time Recovery (PITR)

```bash
# Restore to specific timestamp
pg_restore_point --target-time "2025-11-11 14:30:00" \
  --backup-file "s3://biomate-backups/daily/2025/11/11/database_20251111_020000.sql.enc" \
  --wal-archive "s3://biomate-backups/wal/"
```

### File Recovery

```bash
# Restore user file from S3 version
aws s3api get-object \
  --bucket biomate-user-data \
  --key "users/12345/dataset.csv" \
  --version-id "abc123..." \
  /tmp/restored_file.csv
```

---

## Testing and Validation

### Backup Testing Schedule

| Test Type | Frequency | Success Criteria |
|-----------|-----------|------------------|
| Backup integrity check | Daily | Checksum validation passes |
| Database restore test | Weekly | Full restore completes in < 30 min |
| DR failover drill | Quarterly | RTO/RPO targets met |
| Full disaster simulation | Annually | Complete recovery in < 8 hours |

### Validation Checklist

**After Every Restore:**
- [ ] Database connection successful
- [ ] User count matches expected
- [ ] Recent workflows present
- [ ] Application starts without errors
- [ ] API endpoints respond
- [ ] Authentication works
- [ ] File uploads work
- [ ] Audit logs present
- [ ] No data corruption

---

## Compliance Requirements

### HIPAA Requirements

**§164.308(a)(7)(ii)(A) - Data Backup Plan**
- ✅ Daily automated backups
- ✅ Encrypted backups (AES-256)
- ✅ Offsite storage (cross-region)
- ✅ 6+ year retention for audit logs

**§164.308(a)(7)(ii)(B) - Disaster Recovery Plan**
- ✅ Documented recovery procedures
- ✅ RTO/RPO defined
- ✅ Tested quarterly
- ✅ Emergency mode operation

**§164.308(a)(7)(ii)(C) - Emergency Access**
- ✅ Break-glass access procedures
- ✅ Emergency contact list
- ✅ 24/7 on-call rotation

### SOC 2 Requirements

**CC7.3 - System Continuity**
- ✅ Defined RTO/RPO
- ✅ Regular backup testing
- ✅ Documented recovery procedures
- ✅ Incident response integration

**CC6.1 - Logical Access**
- ✅ Backup access restricted
- ✅ Encryption key management
- ✅ Audit trail for restores

---

## Emergency Contacts

| Role | Name | Phone | Email |
|------|------|-------|-------|
| DR Coordinator | [TBD] | [TBD] | dr@biomate.ai |
| Database Admin | [TBD] | [TBD] | dba@biomate.ai |
| Cloud Architect | [TBD] | [TBD] | cloud@biomate.ai |
| AWS Support | N/A | 1-800-xxx-xxxx | aws.amazon.com/support |

---

## Next Steps

1. **Implement automated backups** using provided scripts
2. **Configure S3 buckets** with encryption and versioning
3. **Set up cross-region replication**
4. **Schedule first DR drill**
5. **Document actual RTO/RPO** after testing
6. **Train operations team** on recovery procedures

---

**Document Owner:** Operations Team
**Review Frequency:** Quarterly
**Next Review:** 2026-02-11
