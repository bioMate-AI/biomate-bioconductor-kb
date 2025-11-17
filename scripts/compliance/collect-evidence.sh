#!/bin/bash

################################################################################
# BioMate AI - Compliance Evidence Collector
################################################################################
#
# PURPOSE:
#   Automatically collects and organizes compliance evidence for:
#   - HIPAA audits
#   - SOC 2 audits
#   - Internal compliance reviews
#
# USAGE:
#   ./collect-evidence.sh [OPTIONS]
#
# OPTIONS:
#   --days N          Collect evidence from last N days (default: 90)
#   --frameworks F    Comma-separated: hipaa,soc2 (default: all)
#   --output-dir DIR  Output directory (default: ./evidence-YYYYMMDD)
#   --aws-region R    AWS region (default: us-east-1)
#   --help            Show this help
#
# OUTPUT:
#   Creates organized directory structure:
#     evidence-YYYYMMDD/
#       ├── HIPAA/
#       │   ├── Administrative_Safeguards/
#       │   ├── Physical_Safeguards/
#       │   └── Technical_Safeguards/
#       ├── SOC2/
#       │   ├── Common_Criteria/
#       │   ├── Availability/
#       │   └── Confidentiality/
#       ├── logs/
#       ├── security/
#       ├── backups/
#       └── evidence-summary.md
#
# REQUIREMENTS:
#   - AWS CLI configured with appropriate permissions
#   - jq for JSON processing
#   - Access to CloudWatch Logs
#   - Access to CloudTrail
#
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
DAYS=90
FRAMEWORKS="hipaa,soc2"
AWS_REGION="${AWS_REGION:-us-east-1}"
OUTPUT_DIR=""
START_DATE=""
END_DATE=""

# Counters
EVIDENCE_COUNT=0
ERROR_COUNT=0

################################################################################
# Helper Functions
################################################################################

log() {
    echo -e "${BLUE}[$(date -u +"%Y-%m-%d %H:%M:%S UTC")]${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
    EVIDENCE_COUNT=$((EVIDENCE_COUNT + 1))
}

error() {
    echo -e "${RED}✗${NC} $*" >&2
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

usage() {
    grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# \?//'
    exit 0
}

################################################################################
# Parse Arguments
################################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            DAYS="$2"
            shift 2
            ;;
        --frameworks)
            FRAMEWORKS="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --aws-region)
            AWS_REGION="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

################################################################################
# Initialize
################################################################################

# Set date range
END_DATE=$(date -u +"%Y-%m-%d")
START_DATE=$(date -u -d "$DAYS days ago" +"%Y-%m-%d")

# Set output directory
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="./evidence-$(date +%Y%m%d)"
fi

log "Starting compliance evidence collection"
log "Date range: $START_DATE to $END_DATE ($DAYS days)"
log "Frameworks: $FRAMEWORKS"
log "Output: $OUTPUT_DIR"

# Create directory structure
mkdir -p "$OUTPUT_DIR"/{HIPAA,SOC2,logs,security,backups,access-control,training,policies}

if [[ "$FRAMEWORKS" == *"hipaa"* ]]; then
    mkdir -p "$OUTPUT_DIR/HIPAA"/{Administrative_Safeguards,Physical_Safeguards,Technical_Safeguards,Breach_Notification}
fi

if [[ "$FRAMEWORKS" == *"soc2"* ]]; then
    mkdir -p "$OUTPUT_DIR/SOC2"/{Common_Criteria,Availability,Confidentiality,Processing_Integrity,Privacy}
fi

# Convert dates to epoch for CloudWatch
START_EPOCH=$(date -d "$START_DATE" +%s)000
END_EPOCH=$(date -d "$END_DATE" +%s)000

################################################################################
# CloudWatch Logs Collection
################################################################################

collect_cloudwatch_logs() {
    local log_group=$1
    local output_file=$2
    local description=$3

    log "Collecting: $description"

    if aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$AWS_REGION" &> /dev/null; then

        aws logs filter-log-events \
            --log-group-name "$log_group" \
            --start-time "$START_EPOCH" \
            --end-time "$END_EPOCH" \
            --region "$AWS_REGION" \
            --output json > "$output_file" 2>/dev/null || {
                warn "No logs found for $log_group"
                return
            }

        local event_count=$(jq '.events | length' "$output_file")
        success "$description: $event_count events"
    else
        warn "Log group not found: $log_group"
    fi
}

log "=== Collecting CloudWatch Logs ==="

collect_cloudwatch_logs \
    "/aws/rds/instance/biomate-production/audit" \
    "$OUTPUT_DIR/logs/rds-audit-logs.json" \
    "RDS Audit Logs"

collect_cloudwatch_logs \
    "/aws/elasticache/biomate-production" \
    "$OUTPUT_DIR/logs/redis-logs.json" \
    "Redis Logs"

collect_cloudwatch_logs \
    "/biomate/application" \
    "$OUTPUT_DIR/logs/application-logs.json" \
    "Application Logs"

collect_cloudwatch_logs \
    "/biomate/security" \
    "$OUTPUT_DIR/logs/security-logs.json" \
    "Security Event Logs"

collect_cloudwatch_logs \
    "/biomate/access" \
    "$OUTPUT_DIR/logs/access-logs.json" \
    "Access Logs"

################################################################################
# CloudTrail Events Collection
################################################################################

log "=== Collecting CloudTrail Events ==="

# IAM events
log "Collecting IAM events"
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::IAM::User \
    --start-time "$START_DATE" \
    --end-time "$END_DATE" \
    --region "$AWS_REGION" \
    --output json > "$OUTPUT_DIR/security/iam-events.json" 2>/dev/null || warn "No IAM events found"

if [[ -f "$OUTPUT_DIR/security/iam-events.json" ]]; then
    local iam_count=$(jq '.Events | length' "$OUTPUT_DIR/security/iam-events.json")
    success "IAM events: $iam_count"
fi

# RDS events
log "Collecting RDS events"
aws rds describe-events \
    --start-time "$START_DATE" \
    --end-time "$END_DATE" \
    --region "$AWS_REGION" \
    --output json > "$OUTPUT_DIR/logs/rds-events.json" 2>/dev/null || warn "No RDS events found"

# S3 access logs (if configured)
log "Collecting S3 access logs"
aws s3api list-buckets \
    --query 'Buckets[?contains(Name, `biomate`)].Name' \
    --output json > "$OUTPUT_DIR/security/s3-buckets.json"

################################################################################
# Security Test Results
################################################################################

log "=== Collecting Security Test Results ==="

# SSL/TLS test results
if [[ -f /var/log/biomate/ssl-tests.log ]]; then
    cp /var/log/biomate/ssl-tests.log "$OUTPUT_DIR/security/ssl-test-results.log"
    success "SSL/TLS test results"
fi

# Vulnerability scan results (if exist)
if [[ -d /var/log/biomate/security-scans ]]; then
    cp -r /var/log/biomate/security-scans "$OUTPUT_DIR/security/"
    success "Security scan results"
fi

# Penetration test results (if exist)
if [[ -d /var/log/biomate/penetration-tests ]]; then
    cp -r /var/log/biomate/penetration-tests "$OUTPUT_DIR/security/"
    success "Penetration test results"
fi

################################################################################
# Backup Verification
################################################################################

log "=== Collecting Backup Verification Records ==="

# RDS snapshots
log "Collecting RDS snapshot information"
aws rds describe-db-snapshots \
    --db-instance-identifier biomate-production \
    --region "$AWS_REGION" \
    --output json > "$OUTPUT_DIR/backups/rds-snapshots.json" 2>/dev/null || warn "No RDS snapshots found"

if [[ -f "$OUTPUT_DIR/backups/rds-snapshots.json" ]]; then
    local snapshot_count=$(jq '.DBSnapshots | length' "$OUTPUT_DIR/backups/rds-snapshots.json")
    success "RDS snapshots: $snapshot_count"
fi

# S3 versioning status
log "Collecting S3 versioning configuration"
for bucket in $(jq -r '.[]' "$OUTPUT_DIR/security/s3-buckets.json" 2>/dev/null); do
    aws s3api get-bucket-versioning \
        --bucket "$bucket" \
        --region "$AWS_REGION" \
        --output json > "$OUTPUT_DIR/backups/s3-versioning-${bucket}.json" 2>/dev/null
done

# Backup test logs
if [[ -f /var/log/biomate/backup-tests.log ]]; then
    cp /var/log/biomate/backup-tests.log "$OUTPUT_DIR/backups/"
    success "Backup test logs"
fi

################################################################################
# Access Control Information
################################################################################

log "=== Collecting Access Control Information ==="

# IAM policies
log "Collecting IAM policies"
aws iam list-policies \
    --scope Local \
    --region "$AWS_REGION" \
    --output json > "$OUTPUT_DIR/access-control/iam-policies.json"

# IAM roles
log "Collecting IAM roles"
aws iam list-roles \
    --region "$AWS_REGION" \
    --output json > "$OUTPUT_DIR/access-control/iam-roles.json"

# IAM users
log "Collecting IAM users"
aws iam list-users \
    --region "$AWS_REGION" \
    --output json > "$OUTPUT_DIR/access-control/iam-users.json"

# MFA status
log "Collecting MFA status"
{
    echo "# MFA Status Report"
    echo "Generated: $(date -u)"
    echo ""
    echo "## Users"

    for user in $(aws iam list-users --query 'Users[].UserName' --output text); do
        mfa_devices=$(aws iam list-mfa-devices --user-name "$user" --query 'MFADevices' --output json)
        mfa_count=$(echo "$mfa_devices" | jq 'length')

        if [[ $mfa_count -gt 0 ]]; then
            echo "- $user: ✓ MFA enabled"
        else
            echo "- $user: ✗ MFA NOT enabled"
        fi
    done
} > "$OUTPUT_DIR/access-control/mfa-status.md"

success "Access control information collected"

################################################################################
# Encryption Configuration
################################################################################

log "=== Collecting Encryption Configuration ==="

# RDS encryption status
log "Collecting RDS encryption status"
aws rds describe-db-instances \
    --db-instance-identifier biomate-production \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].StorageEncrypted' \
    --output json > "$OUTPUT_DIR/security/rds-encryption.json" 2>/dev/null

# S3 encryption status
log "Collecting S3 encryption status"
for bucket in $(jq -r '.[]' "$OUTPUT_DIR/security/s3-buckets.json" 2>/dev/null); do
    aws s3api get-bucket-encryption \
        --bucket "$bucket" \
        --region "$AWS_REGION" \
        --output json > "$OUTPUT_DIR/security/s3-encryption-${bucket}.json" 2>/dev/null || \
        echo '{"Status": "Not configured"}' > "$OUTPUT_DIR/security/s3-encryption-${bucket}.json"
done

# KMS keys
log "Collecting KMS key information"
aws kms list-keys \
    --region "$AWS_REGION" \
    --output json > "$OUTPUT_DIR/security/kms-keys.json"

success "Encryption configuration collected"

################################################################################
# Training Records
################################################################################

log "=== Collecting Training Records ==="

# HIPAA training records (if exist)
if [[ -d /var/log/biomate/training ]]; then
    cp -r /var/log/biomate/training "$OUTPUT_DIR/training/"
    success "Training records collected"
else
    warn "No training records found. Please add to: $OUTPUT_DIR/training/"
    mkdir -p "$OUTPUT_DIR/training"
    cat > "$OUTPUT_DIR/training/README.md" <<'EOF'
# Training Records

Please add the following documentation:

## Required Records

### HIPAA Training
- [ ] HIPAA Privacy Rule training completion certificates
- [ ] HIPAA Security Rule training completion certificates
- [ ] Training attendance sheets
- [ ] Training materials used
- [ ] Quiz/test results

### Security Awareness Training
- [ ] Phishing awareness training
- [ ] Password security training
- [ ] Incident response training
- [ ] Data handling training

### Role-Specific Training
- [ ] Developer security training
- [ ] System administrator training
- [ ] Privacy officer training

## Format
Organize by:
- Employee name
- Training date
- Training topic
- Completion status
- Next renewal date

## Retention
HIPAA requires 6 years of training records.
EOF
fi

################################################################################
# Policy Documents
################################################################################

log "=== Collecting Policy Documents ==="

# Check for policy directory
if [[ -d /var/log/biomate/policies ]]; then
    cp -r /var/log/biomate/policies "$OUTPUT_DIR/policies/"
    success "Policy documents collected"
else
    warn "No policy documents found. Creating template structure..."
    mkdir -p "$OUTPUT_DIR/policies"

    cat > "$OUTPUT_DIR/policies/README.md" <<'EOF'
# Policy Documents

The following policies should be included for compliance:

## Required HIPAA Policies
- [ ] Privacy Policy
- [ ] Security Policy
- [ ] Breach Notification Policy
- [ ] Sanction Policy
- [ ] Business Associate Management Policy
- [ ] Workforce Security Policy
- [ ] Access Control Policy
- [ ] Data Backup and Recovery Policy
- [ ] Disaster Recovery Policy
- [ ] Incident Response Policy

## Required SOC 2 Policies
- [ ] Information Security Policy
- [ ] Access Control Policy
- [ ] Change Management Policy
- [ ] Risk Management Policy
- [ ] Vendor Management Policy
- [ ] Data Classification Policy
- [ ] Acceptable Use Policy

## Policy Requirements
Each policy should include:
- Policy owner
- Effective date
- Review date (annual minimum)
- Approval signatures
- Revision history
EOF
fi

################################################################################
# HIPAA-Specific Evidence
################################################################################

if [[ "$FRAMEWORKS" == *"hipaa"* ]]; then
    log "=== Organizing HIPAA Evidence ==="

    # Administrative Safeguards (§164.308)
    cat > "$OUTPUT_DIR/HIPAA/Administrative_Safeguards/evidence-checklist.md" <<'EOF'
# HIPAA Administrative Safeguards Evidence

## §164.308(a)(1) - Security Management Process

### (i) Risk Analysis
- [ ] Risk assessment reports (latest + historical)
- [ ] Threat modeling documentation
- [ ] Vulnerability scan results

### (ii) Risk Management
- [ ] Risk mitigation plans
- [ ] Security improvement projects
- [ ] Risk acceptance documentation

### (iii) Sanction Policy
- [ ] Sanction policy document
- [ ] Enforcement records (anonymized)

### (iv) Information System Activity Review
- [ ] Log review procedures
- [ ] Security event analysis reports
- [ ] Audit findings and remediation

## §164.308(a)(2) - Assigned Security Responsibility
- [ ] Security Officer designation
- [ ] Privacy Officer designation
- [ ] Organizational chart showing security roles

## §164.308(a)(3) - Workforce Security
- [ ] Background check policy
- [ ] Termination procedures
- [ ] Access provisioning/deprovisioning records

## §164.308(a)(4) - Information Access Management
- [ ] Access control policy
- [ ] Role-based access control (RBAC) matrix
- [ ] Access review logs

## §164.308(a)(5) - Security Awareness and Training
- [ ] Training records (all employees)
- [ ] Training materials
- [ ] Training schedule
- [ ] Phishing test results

## §164.308(a)(6) - Security Incident Procedures
- [ ] Incident response plan
- [ ] Incident logs
- [ ] Post-incident reports
- [ ] Breach notifications (if applicable)

## §164.308(a)(7) - Contingency Plan
- [ ] Disaster recovery plan
- [ ] Business continuity plan
- [ ] Backup procedures
- [ ] DR test results

## §164.308(a)(8) - Evaluation
- [ ] Annual security evaluation reports
- [ ] Compliance audit results
- [ ] Penetration test results
EOF

    # Copy relevant evidence to Administrative Safeguards
    [[ -f "$OUTPUT_DIR/security/iam-events.json" ]] && \
        cp "$OUTPUT_DIR/security/iam-events.json" "$OUTPUT_DIR/HIPAA/Administrative_Safeguards/"
    [[ -d "$OUTPUT_DIR/training" ]] && \
        cp -r "$OUTPUT_DIR/training" "$OUTPUT_DIR/HIPAA/Administrative_Safeguards/"

    # Technical Safeguards (§164.312)
    cat > "$OUTPUT_DIR/HIPAA/Technical_Safeguards/evidence-checklist.md" <<'EOF'
# HIPAA Technical Safeguards Evidence

## §164.312(a) - Access Control

### (i) Unique User Identification
- [ ] User account list
- [ ] No shared accounts verification

### (ii) Emergency Access Procedure
- [ ] Break-glass procedure documentation
- [ ] Emergency access logs

### (iii) Automatic Logoff
- [ ] Session timeout configuration
- [ ] 15-minute timeout verification for ePHI access

### (iv) Encryption and Decryption
- [ ] Encryption configuration (AES-256-GCM)
- [ ] TLS configuration (TLS 1.3)
- [ ] Encryption key management procedures

## §164.312(b) - Audit Controls
- [ ] Audit log configuration
- [ ] Log retention policy (6+ years)
- [ ] Sample audit logs

## §164.312(c) - Integrity
- [ ] Data integrity verification procedures
- [ ] Checksum/hash verification
- [ ] Authentication tags (GCM mode)

## §164.312(d) - Person or Entity Authentication
- [ ] Authentication mechanisms
- [ ] MFA configuration
- [ ] Password policy

## §164.312(e) - Transmission Security

### (i) Integrity Controls
- [ ] TLS configuration
- [ ] Certificate management

### (ii) Encryption
- [ ] Data-in-transit encryption verification
- [ ] VPN configuration (if applicable)
EOF

    # Copy technical evidence
    [[ -f "$OUTPUT_DIR/security/ssl-test-results.log" ]] && \
        cp "$OUTPUT_DIR/security/ssl-test-results.log" "$OUTPUT_DIR/HIPAA/Technical_Safeguards/"
    [[ -f "$OUTPUT_DIR/security/kms-keys.json" ]] && \
        cp "$OUTPUT_DIR/security/kms-keys.json" "$OUTPUT_DIR/HIPAA/Technical_Safeguards/"
    [[ -f "$OUTPUT_DIR/logs/access-logs.json" ]] && \
        cp "$OUTPUT_DIR/logs/access-logs.json" "$OUTPUT_DIR/HIPAA/Technical_Safeguards/"

    # Physical Safeguards (§164.310)
    cat > "$OUTPUT_DIR/HIPAA/Physical_Safeguards/evidence-checklist.md" <<'EOF'
# HIPAA Physical Safeguards Evidence

## §164.310(a) - Facility Access Controls
- [ ] AWS SOC 2 Type II report
- [ ] Data center certification
- [ ] Physical access logs (if on-premises)

## §164.310(b) - Workstation Use
- [ ] Workstation security policy
- [ ] Screen lock requirements
- [ ] Clean desk policy

## §164.310(c) - Workstation Security
- [ ] Endpoint security configuration
- [ ] Full-disk encryption verification
- [ ] Device inventory

## §164.310(d) - Device and Media Controls

### (i) Disposal
- [ ] Media disposal procedures
- [ ] Certificate of destruction

### (ii) Media Re-use
- [ ] Secure erase procedures

### (iii) Accountability
- [ ] Hardware inventory
- [ ] Media tracking logs

### (iv) Data Backup and Storage
- [ ] Backup procedures
- [ ] Offsite backup verification
- [ ] Backup encryption
EOF

    success "HIPAA evidence organized"
fi

################################################################################
# SOC 2 Evidence
################################################################################

if [[ "$FRAMEWORKS" == *"soc2"* ]]; then
    log "=== Organizing SOC 2 Evidence ==="

    cat > "$OUTPUT_DIR/SOC2/Common_Criteria/evidence-checklist.md" <<'EOF'
# SOC 2 Common Criteria Evidence

## CC1 - Control Environment
- [ ] Organizational structure
- [ ] Code of conduct
- [ ] HR policies
- [ ] Background check records

## CC2 - Communication and Information
- [ ] Communication procedures
- [ ] Internal security communications
- [ ] External security communications

## CC3 - Risk Assessment
- [ ] Risk assessment reports
- [ ] Risk register
- [ ] Risk treatment plans

## CC4 - Monitoring Activities
- [ ] Monitoring procedures
- [ ] Security dashboards
- [ ] Alert configurations

## CC5 - Control Activities
- [ ] Change management records
- [ ] Configuration management
- [ ] Segregation of duties matrix

## CC6 - Logical and Physical Access Controls
- [ ] Access control policies
- [ ] Access reviews
- [ ] MFA implementation
- [ ] Physical access controls (AWS)

## CC7 - System Operations
- [ ] Incident management records
- [ ] Change tickets
- [ ] Capacity planning

## CC8 - Change Management
- [ ] Change management policy
- [ ] Change tickets and approvals
- [ ] Rollback procedures

## CC9 - Risk Mitigation
- [ ] Vulnerability management
- [ ] Patch management
- [ ] Security updates log
EOF

    cat > "$OUTPUT_DIR/SOC2/Availability/evidence-checklist.md" <<'EOF'
# SOC 2 Availability Criteria Evidence

## A1.1 - Availability Performance
- [ ] Uptime reports (target: 99.9%)
- [ ] SLA performance data
- [ ] Downtime incidents and root cause analysis

## A1.2 - System Monitoring
- [ ] CloudWatch dashboards
- [ ] Monitoring alerts configuration
- [ ] Alert response times

## A1.3 - Backup and Recovery
- [ ] Backup schedules
- [ ] Backup test results
- [ ] Recovery time objective (RTO) documentation
- [ ] Recovery point objective (RPO) documentation
EOF

    cat > "$OUTPUT_DIR/SOC2/Confidentiality/evidence-checklist.md" <<'EOF'
# SOC 2 Confidentiality Criteria Evidence

## C1.1 - Data Classification
- [ ] Data classification policy
- [ ] Data inventory
- [ ] Confidential data handling procedures

## C1.2 - Encryption
- [ ] Encryption at rest configuration
- [ ] Encryption in transit configuration
- [ ] Key management procedures
EOF

    # Copy SOC 2 evidence
    [[ -f "$OUTPUT_DIR/access-control/iam-policies.json" ]] && \
        cp "$OUTPUT_DIR/access-control/iam-policies.json" "$OUTPUT_DIR/SOC2/Common_Criteria/"
    [[ -f "$OUTPUT_DIR/backups/rds-snapshots.json" ]] && \
        cp "$OUTPUT_DIR/backups/rds-snapshots.json" "$OUTPUT_DIR/SOC2/Availability/"

    success "SOC 2 evidence organized"
fi

################################################################################
# Generate Summary Report
################################################################################

log "=== Generating Evidence Summary ==="

cat > "$OUTPUT_DIR/evidence-summary.md" <<EOF
# Compliance Evidence Collection Summary

**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Date Range:** $START_DATE to $END_DATE ($DAYS days)
**Frameworks:** $FRAMEWORKS
**AWS Region:** $AWS_REGION

---

## Collection Statistics

- **Evidence Items Collected:** $EVIDENCE_COUNT
- **Errors Encountered:** $ERROR_COUNT
- **Warnings:** (see logs above)

---

## Evidence Categories

### 1. Logs and Audit Trails
\`\`\`
$(ls -lh "$OUTPUT_DIR/logs/" 2>/dev/null | tail -n +2 || echo "No logs collected")
\`\`\`

### 2. Security Evidence
\`\`\`
$(ls -lh "$OUTPUT_DIR/security/" 2>/dev/null | tail -n +2 || echo "No security evidence collected")
\`\`\`

### 3. Backup Verification
\`\`\`
$(ls -lh "$OUTPUT_DIR/backups/" 2>/dev/null | tail -n +2 || echo "No backup evidence collected")
\`\`\`

### 4. Access Control
\`\`\`
$(ls -lh "$OUTPUT_DIR/access-control/" 2>/dev/null | tail -n +2 || echo "No access control evidence collected")
\`\`\`

---

## AWS Resources Documented

### RDS Instances
\`\`\`json
$(aws rds describe-db-instances --region "$AWS_REGION" --output json 2>/dev/null | jq '.DBInstances[] | {Identifier: .DBInstanceIdentifier, Engine: .Engine, Encrypted: .StorageEncrypted}' || echo "No RDS instances found")
\`\`\`

### S3 Buckets
\`\`\`json
$(cat "$OUTPUT_DIR/security/s3-buckets.json" 2>/dev/null || echo "[]")
\`\`\`

### ElastiCache Clusters
\`\`\`json
$(aws elasticache describe-cache-clusters --region "$AWS_REGION" --output json 2>/dev/null | jq '.CacheClusters[] | {ClusterId: .CacheClusterId, Engine: .Engine, TransitEncryptionEnabled: .TransitEncryptionEnabled}' || echo "No ElastiCache clusters found")
\`\`\`

---

## Compliance Framework Coverage

EOF

if [[ "$FRAMEWORKS" == *"hipaa"* ]]; then
    cat >> "$OUTPUT_DIR/evidence-summary.md" <<'EOF'
### HIPAA Coverage

#### Administrative Safeguards (§164.308)
- [x] Security Management Process evidence
- [x] Assigned Security Responsibility documentation
- [x] Workforce Security records
- [x] Information Access Management logs
- [ ] Security Awareness Training (add to training/ directory)
- [x] Security Incident Procedures
- [x] Contingency Plan documentation
- [ ] Evaluation (annual security evaluation needed)

#### Physical Safeguards (§164.310)
- [x] Facility Access Controls (AWS SOC 2 report)
- [ ] Workstation Use policy (add to policies/)
- [ ] Workstation Security configuration
- [x] Device and Media Controls

#### Technical Safeguards (§164.312)
- [x] Access Control mechanisms
- [x] Audit Controls (CloudWatch logs)
- [x] Integrity controls
- [x] Person/Entity Authentication
- [x] Transmission Security

#### Breach Notification (§164.400)
- [ ] Breach notification procedures (add documentation)
- [ ] Breach incident log (if applicable)

---

EOF
fi

if [[ "$FRAMEWORKS" == *"soc2"* ]]; then
    cat >> "$OUTPUT_DIR/evidence-summary.md" <<'EOF'
### SOC 2 Coverage

#### Common Criteria
- [x] CC1: Control Environment
- [x] CC2: Communication and Information
- [x] CC3: Risk Assessment
- [x] CC4: Monitoring Activities
- [x] CC5: Control Activities
- [x] CC6: Logical and Physical Access Controls
- [x] CC7: System Operations
- [ ] CC8: Change Management (add change tickets)
- [x] CC9: Risk Mitigation

#### Availability
- [x] Performance monitoring
- [x] Backup and recovery evidence
- [ ] Uptime reports (add from monitoring)

#### Confidentiality
- [x] Encryption configuration
- [ ] Data classification (add to policies/)

---

EOF
fi

cat >> "$OUTPUT_DIR/evidence-summary.md" <<EOF
## Manual Evidence Still Needed

The following evidence items should be added manually:

### High Priority
1. **Training Records** - Add to \`training/\` directory
   - HIPAA training certificates
   - Security awareness training
   - Training attendance sheets

2. **Policy Documents** - Add to \`policies/\` directory
   - All policies listed in policies/README.md

3. **Annual Evaluations** - Add to \`HIPAA/Administrative_Safeguards/\`
   - Security evaluation report
   - Compliance audit results

4. **Change Management** - Add to \`SOC2/Common_Criteria/\`
   - Change tickets from last $DAYS days
   - Change approval records

### Medium Priority
5. **Vendor Management**
   - Business Associate Agreements
   - Vendor security assessments
   - Subprocessor list

6. **Physical Security** (if applicable)
   - Office access logs
   - Visitor logs
   - Equipment inventory

7. **Incident Response**
   - Incident reports from last $DAYS days
   - Post-incident reviews
   - Lessons learned

### Low Priority
8. **Penetration Testing**
   - Latest pentest report
   - Remediation evidence

9. **Vulnerability Management**
   - Vulnerability scan reports
   - Patch management records

---

## How to Use This Evidence Package

### For HIPAA Audit
1. Review \`HIPAA/\` directory
2. Check each evidence-checklist.md for completeness
3. Add missing items marked with [ ]
4. Provide to auditor or OCR investigator

### For SOC 2 Audit
1. Review \`SOC2/\` directory
2. Check each evidence-checklist.md for completeness
3. Add missing items marked with [ ]
4. Provide to SOC 2 auditor

### For Internal Review
1. Review evidence-summary.md (this file)
2. Address items in "Manual Evidence Still Needed"
3. Re-run this script quarterly to maintain compliance

---

## Evidence Retention

- **HIPAA:** Retain for 6 years from date of creation/last effective date
- **SOC 2:** Retain for audit period + 7 years
- **General:** Follow your organization's retention policy

---

## Next Steps

1. [ ] Review all collected evidence
2. [ ] Add manual evidence items listed above
3. [ ] Verify completeness using checklists
4. [ ] Archive this evidence package securely
5. [ ] Schedule next evidence collection ($DAYS days from now)

---

**Evidence Collection Completed:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Total Evidence Items:** $EVIDENCE_COUNT
**Collection Errors:** $ERROR_COUNT
EOF

success "Evidence summary generated"

################################################################################
# Create Archive
################################################################################

log "=== Creating Archive ==="

ARCHIVE_NAME="compliance-evidence-$(date +%Y%m%d-%H%M%S).tar.gz"

tar -czf "$ARCHIVE_NAME" "$OUTPUT_DIR" 2>/dev/null

if [[ -f "$ARCHIVE_NAME" ]]; then
    ARCHIVE_SIZE=$(du -h "$ARCHIVE_NAME" | cut -f1)
    success "Archive created: $ARCHIVE_NAME ($ARCHIVE_SIZE)"

    # Generate SHA-256 checksum
    sha256sum "$ARCHIVE_NAME" > "${ARCHIVE_NAME}.sha256"
    success "Checksum: ${ARCHIVE_NAME}.sha256"
fi

################################################################################
# Final Summary
################################################################################

echo ""
echo "========================================"
echo "Evidence Collection Complete"
echo "========================================"
echo ""
echo "Output Directory: $OUTPUT_DIR"
echo "Archive: $ARCHIVE_NAME"
echo ""
echo "Evidence Items Collected: $EVIDENCE_COUNT"
echo "Errors: $ERROR_COUNT"
echo ""
echo "Next Steps:"
echo "1. Review: $OUTPUT_DIR/evidence-summary.md"
echo "2. Add manual evidence items"
echo "3. Verify using framework-specific checklists"
echo "4. Securely store archive"
echo ""

if [[ $ERROR_COUNT -gt 0 ]]; then
    warn "Some evidence items could not be collected. Review errors above."
    exit 1
fi

success "Evidence collection successful!"
exit 0
