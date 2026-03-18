# BioMate AI - Compliance Evidence Collection Guide

**Document Version:** 1.0
**Last Updated:** 2025-11-11
**Purpose:** Guide for collecting, organizing, and maintaining compliance evidence for HIPAA and SOC 2 audits

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Evidence Collection Schedule](#evidence-collection-schedule)
4. [Automated vs Manual Evidence](#automated-vs-manual-evidence)
5. [HIPAA Evidence Requirements](#hipaa-evidence-requirements)
6. [SOC 2 Evidence Requirements](#soc2-evidence-requirements)
7. [Evidence Organization](#evidence-organization)
8. [Audit Preparation](#audit-preparation)
9. [Evidence Retention](#evidence-retention)
10. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose

This guide documents how to collect, organize, and maintain compliance evidence for:
- **HIPAA audits** (Office for Civil Rights investigations, Business Associate audits)
- **SOC 2 audits** (Type I and Type II)
- **Internal compliance reviews**

### What is Compliance Evidence?

Compliance evidence demonstrates that your organization is following required security and privacy practices. Evidence includes:

- **Logs:** Audit trails, access logs, security event logs
- **Documentation:** Policies, procedures, plans
- **Records:** Training records, incident reports, risk assessments
- **Technical Evidence:** Configuration screenshots, test results, encryption verification
- **Attestations:** Sign-offs, approvals, acknowledgments

### Automated Collection Tool

The `scripts/compliance/collect-evidence.sh` script automates collection of:
- CloudWatch logs (90+ days)
- AWS CloudTrail events
- Security test results
- Backup verification records
- Access control configurations
- Encryption settings
- Infrastructure inventory

It also creates organized directory structures with checklists for manual evidence.

---

## Quick Start

### Prerequisites

1. **AWS CLI configured** with appropriate permissions:
   ```bash
   aws configure
   # Verify access
   aws sts get-caller-identity
   ```

2. **Required IAM permissions:**
   - `logs:DescribeLogGroups`
   - `logs:FilterLogEvents`
   - `cloudtrail:LookupEvents`
   - `rds:DescribeDBInstances`
   - `rds:DescribeDBSnapshots`
   - `rds:DescribeEvents`
   - `s3:ListBuckets`
   - `s3:GetBucketVersioning`
   - `s3:GetBucketEncryption`
   - `iam:ListPolicies`
   - `iam:ListRoles`
   - `iam:ListUsers`
   - `iam:ListMFADevices`
   - `kms:ListKeys`
   - `elasticache:DescribeCacheClusters`

3. **jq installed:**
   ```bash
   sudo apt-get install jq
   ```

### Basic Usage

```bash
# Collect all evidence (last 90 days)
./scripts/compliance/collect-evidence.sh

# Collect for specific period
./scripts/compliance/collect-evidence.sh --days 180

# Collect only HIPAA evidence
./scripts/compliance/collect-evidence.sh --frameworks hipaa

# Collect only SOC 2 evidence
./scripts/compliance/collect-evidence.sh --frameworks soc2

# Specify output directory
./scripts/compliance/collect-evidence.sh --output-dir /audit/Q4-2025
```

### Output

The script creates:
```
evidence-YYYYMMDD/
├── HIPAA/
│   ├── Administrative_Safeguards/
│   │   └── evidence-checklist.md
│   ├── Physical_Safeguards/
│   │   └── evidence-checklist.md
│   ├── Technical_Safeguards/
│   │   └── evidence-checklist.md
│   └── Breach_Notification/
├── SOC2/
│   ├── Common_Criteria/
│   │   └── evidence-checklist.md
│   ├── Availability/
│   │   └── evidence-checklist.md
│   ├── Confidentiality/
│   │   └── evidence-checklist.md
│   ├── Processing_Integrity/
│   └── Privacy/
├── logs/
│   ├── rds-audit-logs.json
│   ├── redis-logs.json
│   ├── application-logs.json
│   ├── security-logs.json
│   └── access-logs.json
├── security/
│   ├── iam-events.json
│   ├── ssl-test-results.log
│   ├── kms-keys.json
│   └── s3-buckets.json
├── backups/
│   └── rds-snapshots.json
├── access-control/
│   ├── iam-policies.json
│   ├── iam-roles.json
│   ├── iam-users.json
│   └── mfa-status.md
├── training/
│   └── README.md (instructions for manual addition)
├── policies/
│   └── README.md (instructions for manual addition)
├── evidence-summary.md
└── compliance-evidence-YYYYMMDD-HHMMSS.tar.gz
```

---

## Evidence Collection Schedule

### Continuous Collection

These items are collected automatically by the system:

| Evidence Type | Collection Method | Retention |
|---------------|-------------------|-----------|
| CloudWatch Logs | Automatic | 6 years (2555 days) |
| CloudTrail Events | Automatic | 90 days (AWS default) |
| Access Logs | Automatic | 6 years |
| Security Events | Automatic | 6 years |
| Backup Snapshots | Automatic | 30 days + long-term |

### Quarterly Collection (Every 90 Days)

Run the evidence collector script:

```bash
./scripts/compliance/collect-evidence.sh --days 90
```

**Activities:**
1. Run automated evidence collection
2. Review evidence-summary.md
3. Add manual evidence items
4. Archive evidence package
5. Store securely (encrypted, access-controlled)

**Timeline:**
- Q1: January 15
- Q2: April 15
- Q3: July 15
- Q4: October 15

### Annual Collection

**Activities:**
1. Complete quarterly collection
2. Add annual-specific items:
   - Annual security evaluation report
   - Annual risk assessment
   - Annual HIPAA training records
   - Annual policy reviews
   - Annual DR test results
   - Penetration test results
3. Prepare for external audit
4. Archive full year of evidence

**Timeline:** December 1 (fiscal year end)

### Pre-Audit Collection

When notified of an audit:

```bash
# Collect comprehensive evidence
./scripts/compliance/collect-evidence.sh --days 365

# Review all checklists
find evidence-* -name "evidence-checklist.md" -exec cat {} \;
```

---

## Automated vs Manual Evidence

### Fully Automated (Script Collects)

✅ **CloudWatch Logs**
- Application logs
- Security event logs
- Access logs
- Database audit logs
- Redis logs

✅ **AWS Infrastructure**
- RDS configuration and encryption
- S3 bucket configuration
- ElastiCache configuration
- CloudTrail events
- IAM policies, roles, users
- KMS keys

✅ **Security Configuration**
- SSL/TLS test results (if run)
- Encryption status
- MFA status
- Backup snapshots

### Semi-Automated (Script Creates Template)

⚠️ **Policies and Procedures**
- Script creates README with required list
- You add actual policy documents

⚠️ **Training Records**
- Script creates directory structure
- You add training certificates and records

### Fully Manual (You Must Add)

❌ **Human-Generated Records**
- Training attendance sheets
- Incident reports and post-mortems
- Risk assessment reports
- Annual security evaluations
- Change management tickets
- Meeting minutes
- Sign-offs and approvals

❌ **External Documents**
- Business Associate Agreements
- Vendor security assessments
- Penetration test reports
- SOC 2 audit reports from vendors
- Insurance policies

❌ **Physical Security** (if applicable)
- Office access logs
- Visitor logs
- Equipment disposal certificates

---

## HIPAA Evidence Requirements

### Administrative Safeguards (§164.308)

#### §164.308(a)(1) - Security Management Process

**Risk Analysis (Required)**
- [ ] Latest risk assessment report (annually)
- [ ] Historical risk assessments
- [ ] Threat modeling documentation
- [ ] Vulnerability scan results

**How to Add:**
```bash
cp risk-assessment-2025.pdf evidence-YYYYMMDD/HIPAA/Administrative_Safeguards/
```

**Risk Management (Required)**
- [ ] Risk mitigation plans
- [ ] Security improvement project plans
- [ ] Risk acceptance documentation (signed)

**Sanction Policy (Required)**
- [ ] Sanction policy document
- [ ] Enforcement records (anonymized if containing PII)

**Information System Activity Review (Required)**
- [ ] Log review procedures
- [ ] Security event analysis reports
- [ ] Quarterly audit findings
- [ ] Remediation tracking

**Automated Collection:**
```bash
# Script automatically collects:
# - Access logs from CloudWatch
# - Security event logs
# - IAM events from CloudTrail
```

---

#### §164.308(a)(2) - Assigned Security Responsibility (Required)

**Evidence:**
- [ ] Security Officer designation letter
- [ ] Privacy Officer designation letter
- [ ] Organizational chart showing security roles
- [ ] Job descriptions for security roles

**Template:**
```
[Company Letterhead]

SECURITY OFFICER DESIGNATION

Date: [DATE]

This letter designates [NAME] as the Security Officer for [COMPANY NAME]
effective [DATE].

Responsibilities:
- Develop and maintain security policies
- Oversee HIPAA Security Rule compliance
- Conduct security risk assessments
- Manage security incident response
- Report to executive management

Signed: _____________________
        [CEO/Executive]
```

---

#### §164.308(a)(3) - Workforce Security (Required)

**Evidence:**
- [ ] Background check policy
- [ ] Background check records (summary, not full reports)
- [ ] Employee termination checklist
- [ ] Access provisioning procedure
- [ ] Access de-provisioning logs

**Automated Collection:**
```bash
# Script collects:
# - IAM user list
# - Access control policies
# - Recent IAM events (user creation/deletion)
```

---

#### §164.308(a)(4) - Information Access Management (Required)

**Evidence:**
- [ ] Access control policy
- [ ] Role-based access control (RBAC) matrix
- [ ] Access request forms
- [ ] Access review logs (quarterly)
- [ ] Minimum necessary policy

**RBAC Matrix Template:**

| Role | Database Access | PHI Access | Admin Access | AWS Console | Production Deploy |
|------|----------------|-----------|--------------|-------------|-------------------|
| Developer | Read-only dev | No | No | No | No |
| DevOps | Read prod | No | Yes | Yes | Yes |
| Admin | Full | No | Yes | Yes | Yes |
| HIPAA Admin | Full | Yes (logged) | Yes | Yes | Yes |

**Automated Collection:**
```bash
# Script collects:
# - IAM policies
# - IAM roles
# - IAM users
```

---

#### §164.308(a)(5) - Security Awareness and Training (Required)

**Evidence:**
- [ ] HIPAA Privacy Rule training records (all employees)
- [ ] HIPAA Security Rule training records (all employees)
- [ ] Training materials/curriculum
- [ ] Training schedule
- [ ] Training completion certificates
- [ ] Phishing test results
- [ ] Security awareness training

**Training Record Template:**

```csv
Employee,Training_Type,Training_Date,Completion_Date,Certificate,Next_Due
John Doe,HIPAA Privacy,2025-01-15,2025-01-20,CERT-001,2026-01-15
John Doe,HIPAA Security,2025-01-15,2025-01-20,CERT-002,2026-01-15
Jane Smith,HIPAA Privacy,2025-02-01,2025-02-05,CERT-003,2026-02-01
```

**Required Training:**
- All employees: Annual HIPAA Privacy and Security training
- Developers: Secure coding, PHI handling
- System admins: Security best practices
- Privacy/Security Officers: Advanced HIPAA training

**How to Add:**
```bash
# Add to training/ directory
cp training-records-2025.xlsx evidence-YYYYMMDD/training/
cp training-certificates/*.pdf evidence-YYYYMMDD/training/certificates/
```

---

#### §164.308(a)(6) - Security Incident Procedures (Required)

**Evidence:**
- [ ] Incident response plan
- [ ] Incident response team roster
- [ ] Incident log (all incidents, not just breaches)
- [ ] Post-incident reports
- [ ] Breach notifications (if applicable)
- [ ] Breach risk assessments

**Incident Log Template:**

```csv
Incident_ID,Date,Type,Severity,Description,PHI_Involved,Response,Resolved_Date
INC-001,2025-03-15,Unauthorized Access Attempt,Medium,Failed login attempts from unknown IP,No,IP blocked,2025-03-15
INC-002,2025-06-20,Malware Detection,Low,Malware detected on endpoint,No,Endpoint quarantined,2025-06-20
```

**Automated Collection:**
```bash
# Script collects:
# - Security event logs from CloudWatch
```

---

#### §164.308(a)(7) - Contingency Plan (Required)

**Evidence:**
- [ ] Disaster recovery plan
- [ ] Business continuity plan
- [ ] Data backup plan
- [ ] Disaster recovery test results (annual)
- [ ] Emergency mode operation plan
- [ ] Data backup and recovery procedures

**Automated Collection:**
```bash
# Script collects:
# - RDS backup snapshots
# - S3 versioning configuration
# - Backup test logs (if exist)
```

**How to Add:**
```bash
cp disaster-recovery-plan.pdf evidence-YYYYMMDD/HIPAA/Administrative_Safeguards/
cp DR-test-results-2025.pdf evidence-YYYYMMDD/HIPAA/Administrative_Safeguards/
```

---

#### §164.308(a)(8) - Evaluation (Required)

**Evidence:**
- [ ] Annual security evaluation report
- [ ] Internal audit results
- [ ] External audit results (if applicable)
- [ ] Penetration test results
- [ ] Vulnerability assessment results
- [ ] Compliance gap analysis

**How to Add:**
```bash
# Run HIPAA risk assessment
./scripts/compliance/hipaa-risk-assessment.sh

# Add results
cp hipaa-assessment-*.json evidence-YYYYMMDD/HIPAA/Administrative_Safeguards/
cp hipaa-assessment-*.md evidence-YYYYMMDD/HIPAA/Administrative_Safeguards/
```

---

### Physical Safeguards (§164.310)

#### §164.310(a) - Facility Access Controls (Addressable)

**For Cloud Infrastructure (AWS):**
- [ ] AWS SOC 2 Type II report
- [ ] AWS HIPAA BAA
- [ ] Data center compliance certifications

**For On-Premises (if applicable):**
- [ ] Physical access control policy
- [ ] Badge access logs
- [ ] Visitor logs
- [ ] Facility security plan

**How to Obtain AWS SOC 2 Report:**
```
1. Log into AWS Artifact: https://console.aws.amazon.com/artifact
2. Download: AWS SOC 2 Type II Report
3. Save to evidence package
```

---

#### §164.310(b) - Workstation Use (Required)

**Evidence:**
- [ ] Workstation security policy
- [ ] Screen lock policy
- [ ] Clean desk policy
- [ ] Workstation inventory

---

#### §164.310(c) - Workstation Security (Required)

**Evidence:**
- [ ] Endpoint security configuration
- [ ] Full-disk encryption verification
- [ ] Antivirus/EDR deployment
- [ ] Device inventory

---

#### §164.310(d) - Device and Media Controls (Required)

**Evidence:**
- [ ] Media disposal procedures
- [ ] Certificates of destruction
- [ ] Secure erase procedures
- [ ] Hardware inventory
- [ ] Media tracking logs

---

### Technical Safeguards (§164.312)

#### §164.312(a) - Access Control (Required)

**Unique User Identification (Required)**
- [ ] No shared accounts verification
- [ ] User account list

**Automated Collection:**
```bash
# Script collects IAM user list
# Verify no shared accounts
```

**Emergency Access Procedure (Required)**
- [ ] Break-glass procedure documentation
- [ ] Emergency access logs
- [ ] Emergency access review

**Automatic Logoff (Addressable)**
- [ ] Session timeout configuration (15 minutes for PHI access)
- [ ] Timeout verification

**Encryption and Decryption (Addressable)**
- [ ] Encryption configuration documentation
- [ ] Key management procedures
- [ ] AES-256-GCM configuration
- [ ] TLS 1.3 configuration

**Automated Collection:**
```bash
# Script collects:
# - RDS encryption status
# - S3 encryption configuration
# - KMS keys
# - SSL/TLS configuration (if tests run)
```

---

#### §164.312(b) - Audit Controls (Required)

**Evidence:**
- [ ] Audit logging configuration
- [ ] Log retention policy (6+ years)
- [ ] Sample audit logs
- [ ] Log review procedures

**Automated Collection:**
```bash
# Script collects:
# - CloudWatch audit logs
# - Access logs
# - Database audit logs
```

---

#### §164.312(c) - Integrity (Required)

**Evidence:**
- [ ] Data integrity procedures
- [ ] Checksum/hash verification
- [ ] GCM authentication tag verification

**Automated Collection:**
```bash
# Encryption with GCM mode provides integrity
# Script documents encryption configuration
```

---

#### §164.312(d) - Person or Entity Authentication (Required)

**Evidence:**
- [ ] Authentication mechanism documentation
- [ ] MFA configuration
- [ ] Password policy
- [ ] Authentication logs

**Automated Collection:**
```bash
# Script collects:
# - MFA status for all users
# - IAM password policy
```

---

#### §164.312(e) - Transmission Security (Required)

**Evidence:**
- [ ] TLS configuration
- [ ] Certificate management procedures
- [ ] VPN configuration (if applicable)
- [ ] SSL/TLS test results

**Automated Collection:**
```bash
# Run SSL tests first
./scripts/ssl/test-ssl-config.sh

# Then collect evidence
./scripts/compliance/collect-evidence.sh

# Script includes SSL test results
```

---

### Breach Notification (§164.400-414)

**Evidence:**
- [ ] Breach notification procedures
- [ ] Breach risk assessment template
- [ ] Sample breach notifications (if applicable)
- [ ] Breach log

**Only needed if breach occurred:**
- [ ] Breach risk assessment (for each incident)
- [ ] Notification to individuals (within 60 days)
- [ ] Notification to HHS (if 500+)
- [ ] Media notification (if 500+ in jurisdiction)
- [ ] Business Associate notification to Covered Entity

---

## SOC 2 Evidence Requirements

### Common Criteria (CC)

#### CC1 - Control Environment

**Evidence:**
- [ ] Organizational chart
- [ ] Code of conduct/ethics policy
- [ ] HR policies
- [ ] Background check policy and records
- [ ] Job descriptions (key roles)
- [ ] Board meeting minutes (security topics)

---

#### CC2 - Communication and Information

**Evidence:**
- [ ] Internal security communications
- [ ] Security training materials
- [ ] Security incident communications
- [ ] External communications (customer notifications)

---

#### CC3 - Risk Assessment

**Evidence:**
- [ ] Risk assessment methodology
- [ ] Risk register
- [ ] Risk treatment plans
- [ ] Risk acceptance documentation

**How to Add:**
```bash
# Run risk assessment
./scripts/compliance/hipaa-risk-assessment.sh

# Results apply to both HIPAA and SOC 2
cp hipaa-assessment-*.json evidence-YYYYMMDD/SOC2/Common_Criteria/
```

---

#### CC4 - Monitoring Activities

**Evidence:**
- [ ] Monitoring procedures
- [ ] Security dashboards (screenshots)
- [ ] Alert configurations
- [ ] Alert response records

**Automated Collection:**
```bash
# Script collects:
# - CloudWatch configuration
# - Alert definitions
```

---

#### CC5 - Control Activities

**Evidence:**
- [ ] Change management records
- [ ] Configuration management procedures
- [ ] Segregation of duties matrix
- [ ] Code review process
- [ ] Deployment approval records

---

#### CC6 - Logical and Physical Access Controls

**Evidence:**
- [ ] Access control policies
- [ ] Access review records
- [ ] MFA implementation
- [ ] Physical access controls

**Automated Collection:**
```bash
# Script collects:
# - IAM policies, roles, users
# - MFA status
```

---

#### CC7 - System Operations

**Evidence:**
- [ ] Incident management procedures
- [ ] Incident records
- [ ] Change management procedures
- [ ] Change tickets
- [ ] Capacity planning documentation
- [ ] Performance monitoring

**Automated Collection:**
```bash
# Script collects:
# - System performance logs
# - Resource utilization data
```

---

#### CC8 - Change Management

**Evidence:**
- [ ] Change management policy
- [ ] Change request template
- [ ] Change approval records (last 90 days)
- [ ] Rollback procedures
- [ ] Emergency change procedures

**How to Add:**
```bash
# Export from ticket system (Jira, GitHub, etc.)
# Add to SOC2/Common_Criteria/
```

---

#### CC9 - Risk Mitigation

**Evidence:**
- [ ] Vulnerability management policy
- [ ] Vulnerability scan results
- [ ] Patch management procedures
- [ ] Security update logs

---

### Availability Criteria

#### A1.1 - Availability Performance

**Evidence:**
- [ ] Uptime reports (target: 99.9%)
- [ ] SLA performance data
- [ ] Downtime incident reports
- [ ] Root cause analyses

**How to Generate:**
```bash
# CloudWatch uptime query
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=biomate-production \
    --start-time 2025-01-01T00:00:00Z \
    --end-time 2025-12-31T23:59:59Z \
    --period 3600 \
    --statistics Average
```

---

#### A1.2 - System Monitoring

**Evidence:**
- [ ] Monitoring procedures
- [ ] CloudWatch dashboards (screenshots)
- [ ] Alert configurations
- [ ] Alert response procedures
- [ ] Escalation procedures

---

#### A1.3 - Backup and Recovery

**Evidence:**
- [ ] Backup schedules
- [ ] Backup test results
- [ ] RTO documentation
- [ ] RPO documentation
- [ ] Disaster recovery test results

**Automated Collection:**
```bash
# Script collects:
# - RDS snapshots
# - S3 versioning configuration
```

---

### Confidentiality Criteria

#### C1.1 - Data Classification

**Evidence:**
- [ ] Data classification policy
- [ ] Data inventory
- [ ] Confidential data handling procedures

---

#### C1.2 - Encryption

**Evidence:**
- [ ] Encryption at rest configuration
- [ ] Encryption in transit configuration
- [ ] Key management procedures

**Automated Collection:**
```bash
# Script collects:
# - RDS encryption status
# - S3 encryption configuration
# - KMS keys
# - TLS configuration
```

---

## Evidence Organization

### Directory Structure

```
evidence-YYYYMMDD/
├── 00-README.md                    ← Start here
├── evidence-summary.md             ← Overview and checklist
├── HIPAA/
│   ├── Administrative_Safeguards/
│   │   ├── evidence-checklist.md
│   │   ├── risk-assessment-2025.pdf
│   │   ├── security-officer-designation.pdf
│   │   ├── sanction-policy.pdf
│   │   └── iam-events.json (auto)
│   ├── Physical_Safeguards/
│   │   ├── evidence-checklist.md
│   │   ├── aws-soc2-report.pdf
│   │   └── workstation-security-policy.pdf
│   ├── Technical_Safeguards/
│   │   ├── evidence-checklist.md
│   │   ├── ssl-test-results.log (auto)
│   │   ├── kms-keys.json (auto)
│   │   └── access-logs.json (auto)
│   └── Breach_Notification/
│       └── breach-notification-procedures.pdf
├── SOC2/
│   ├── Common_Criteria/
│   │   ├── evidence-checklist.md
│   │   ├── risk-assessment-2025.pdf
│   │   ├── change-tickets-Q4.csv
│   │   └── iam-policies.json (auto)
│   ├── Availability/
│   │   ├── evidence-checklist.md
│   │   ├── uptime-report-2025.pdf
│   │   ├── DR-test-results.pdf
│   │   └── rds-snapshots.json (auto)
│   └── Confidentiality/
│       ├── evidence-checklist.md
│       └── encryption-config.pdf
├── logs/ (all auto-collected)
├── security/ (all auto-collected)
├── backups/ (all auto-collected)
├── access-control/ (all auto-collected)
├── training/
│   ├── README.md
│   ├── training-records-2025.xlsx
│   └── certificates/
│       ├── john-doe-hipaa-2025.pdf
│       └── jane-smith-hipaa-2025.pdf
└── policies/
    ├── README.md
    ├── privacy-policy.pdf
    ├── security-policy.pdf
    ├── incident-response-policy.pdf
    └── backup-policy.pdf
```

### File Naming Conventions

**Policies:**
- `{policy-name}-policy-v{version}-{date}.pdf`
- Example: `incident-response-policy-v2.1-20251111.pdf`

**Training Records:**
- `training-records-{year}.xlsx`
- `{employee-name}-{training-type}-{year}.pdf`

**Test Results:**
- `{test-type}-test-results-{date}.pdf`
- Example: `DR-test-results-20251111.pdf`

**Assessments:**
- `{assessment-type}-assessment-{date}.pdf`
- Example: `risk-assessment-20251111.pdf`

---

## Audit Preparation

### 30 Days Before Audit

1. **Run Full Evidence Collection:**
   ```bash
   ./scripts/compliance/collect-evidence.sh --days 365 --output-dir /audit/2025-annual
   ```

2. **Review Evidence Summary:**
   ```bash
   cat /audit/2025-annual/evidence-summary.md
   ```

3. **Complete All Checklists:**
   ```bash
   # Find all checklist files
   find /audit/2025-annual -name "evidence-checklist.md"

   # Review each one
   ```

4. **Add Missing Evidence:**
   - Training records
   - Policy documents
   - Annual evaluations
   - Change management tickets
   - Penetration test results

5. **Verify All Items:**
   - [ ] All automated evidence collected
   - [ ] All manual evidence added
   - [ ] All checklists 100% complete
   - [ ] All documents current (not outdated)
   - [ ] All signatures present
   - [ ] All required training completed

### 1 Week Before Audit

6. **Organize by Auditor Requirements:**
   - Create auditor-specific view if needed
   - Index all evidence
   - Create table of contents

7. **Prepare Explanations:**
   - Document any gaps with justification
   - Prepare compensating controls explanation
   - Document any exceptions

8. **Practice Responses:**
   - Review common audit questions
   - Prepare walkthrough of controls
   - Identify subject matter experts

### Day of Audit

9. **Provide Evidence Package:**
   - Share evidence directory or archive
   - Provide evidence summary
   - Assign SME for each area

10. **During Audit:**
    - Answer questions truthfully
    - Provide additional evidence as requested
    - Document all audit requests
    - Track findings in real-time

### After Audit

11. **Address Findings:**
    - Create remediation plan
    - Assign owners and deadlines
    - Track to completion

12. **Update Evidence:**
    - Add remediation evidence
    - Update policies/procedures
    - Re-run assessments if needed

---

## Evidence Retention

### Retention Periods

| Evidence Type | HIPAA | SOC 2 | Recommended |
|---------------|-------|-------|-------------|
| Audit logs | 6 years | 7 years | **7 years** |
| Policies | 6 years | 7 years | **7 years** |
| Training records | 6 years | 7 years | **7 years** |
| Risk assessments | 6 years | 7 years | **7 years** |
| Incident reports | 6 years | 7 years | **7 years** |
| Change records | Not specified | 7 years | **7 years** |
| Backup records | 6 years | 7 years | **7 years** |
| Contracts/BAAs | 6 years | 7 years | **7 years** |
| Penetration tests | Not specified | 7 years | **7 years** |

### Storage Requirements

**Security:**
- Encrypted at rest (AES-256)
- Access-controlled (least privilege)
- Integrity protected (checksums)
- Audit logging enabled

**Location:**
- Primary: AWS S3 with versioning
- Backup: Separate region/account
- Archive: Glacier for long-term (7+ years)

**Organization:**
```
s3://biomate-compliance-evidence/
├── 2025/
│   ├── Q1/
│   │   └── compliance-evidence-20250115.tar.gz
│   ├── Q2/
│   ├── Q3/
│   └── Q4/
├── 2024/
└── 2023/
```

### Archive Script

```bash
#!/bin/bash
# Archive evidence to S3

EVIDENCE_DIR="$1"
DATE=$(date +%Y%m%d)
QUARTER="Q$(($(date +%-m)/3+1))"
YEAR=$(date +%Y)

# Create archive
tar -czf "compliance-evidence-${DATE}.tar.gz" "$EVIDENCE_DIR"

# Generate checksum
sha256sum "compliance-evidence-${DATE}.tar.gz" > "compliance-evidence-${DATE}.tar.gz.sha256"

# Upload to S3
aws s3 cp "compliance-evidence-${DATE}.tar.gz" \
    "s3://biomate-compliance-evidence/${YEAR}/${QUARTER}/" \
    --server-side-encryption AES256

aws s3 cp "compliance-evidence-${DATE}.tar.gz.sha256" \
    "s3://biomate-compliance-evidence/${YEAR}/${QUARTER}/" \
    --server-side-encryption AES256

echo "Archived to: s3://biomate-compliance-evidence/${YEAR}/${QUARTER}/compliance-evidence-${DATE}.tar.gz"
```

---

## Troubleshooting

### Error: "AWS CLI not configured"

**Problem:** Script can't access AWS resources

**Solution:**
```bash
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region (us-east-1)
# - Output format (json)
```

---

### Error: "Access Denied" on CloudWatch Logs

**Problem:** IAM permissions insufficient

**Solution:**
Add IAM policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

---

### Warning: "No logs found for log group"

**Problem:** Log group doesn't exist or has no logs in date range

**Solutions:**
1. Verify log group exists:
   ```bash
   aws logs describe-log-groups --region us-east-1
   ```

2. Check CloudWatch retention settings:
   ```bash
   aws logs describe-log-groups \
       --log-group-name-prefix /biomate \
       --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}'
   ```

3. Extend date range:
   ```bash
   ./scripts/compliance/collect-evidence.sh --days 180
   ```

---

### Error: "jq: command not found"

**Problem:** jq not installed

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# macOS
brew install jq

# CentOS/RHEL
sudo yum install -y jq
```

---

### Missing Manual Evidence

**Problem:** Checklists show many items not collected

**Solution:** This is expected. The script only collects automated evidence. You must add:
- Training records
- Policy documents
- Incident reports
- Change tickets
- Meeting minutes
- Sign-offs

Follow instructions in `training/README.md` and `policies/README.md`.

---

### Archive Too Large

**Problem:** Evidence archive is very large (>10 GB)

**Solutions:**
1. Reduce date range (90 days instead of 365):
   ```bash
   ./scripts/compliance/collect-evidence.sh --days 90
   ```

2. Collect only one framework:
   ```bash
   ./scripts/compliance/collect-evidence.sh --frameworks hipaa
   ```

3. Use S3 for storage instead of local files

---

## Best Practices

### 1. Automate Quarterly Collection

Add to cron:
```bash
# Run on 15th of Jan, Apr, Jul, Oct at 2 AM
0 2 15 1,4,7,10 * /home/biomate/biomate/scripts/compliance/collect-evidence.sh --days 90
```

### 2. Version Control Policies

Keep policies in git:
```bash
git tag policy-v2.1-20251111
git push --tags
```

### 3. Centralize Training Records

Use a Training Management System or spreadsheet:
```csv
Employee,Training,Date,Expires,Certificate
John Doe,HIPAA Privacy,2025-01-15,2026-01-15,CERT-001
John Doe,HIPAA Security,2025-01-15,2026-01-15,CERT-002
```

### 4. Document Exceptions

If a control doesn't apply or you have compensating controls, document it:
```
EXCEPTION: §164.310(a)(1) Facility Access Controls

Justification: We use AWS cloud infrastructure exclusively. Physical
security is provided by AWS data centers (SOC 2 Type II certified).

Compensating Control: AWS BAA in place, AWS SOC 2 report reviewed annually,
logical access controls enforced via IAM.

Approved by: [Security Officer]
Date: [DATE]
```

### 5. Keep Evidence Current

Don't wait for an audit. Update continuously:
- Train employees immediately upon hire
- Update policies when processes change
- Document incidents as they occur
- Run tests on schedule
- Review access quarterly

---

## Quick Reference

### Evidence Collection Commands

```bash
# Standard quarterly collection
./scripts/compliance/collect-evidence.sh

# Annual collection
./scripts/compliance/collect-evidence.sh --days 365

# Pre-audit comprehensive collection
./scripts/compliance/collect-evidence.sh --days 730 --output-dir /audit/2025

# HIPAA only
./scripts/compliance/collect-evidence.sh --frameworks hipaa

# SOC 2 only
./scripts/compliance/collect-evidence.sh --frameworks soc2

# Custom date range and output
./scripts/compliance/collect-evidence.sh --days 180 --output-dir /custom/path
```

### Adding Manual Evidence

```bash
# Training records
cp training-records.xlsx evidence-YYYYMMDD/training/
cp certificates/*.pdf evidence-YYYYMMDD/training/certificates/

# Policies
cp policies/*.pdf evidence-YYYYMMDD/policies/

# HIPAA-specific
cp risk-assessment.pdf evidence-YYYYMMDD/HIPAA/Administrative_Safeguards/
cp DR-test-results.pdf evidence-YYYYMMDD/HIPAA/Administrative_Safeguards/

# SOC 2-specific
cp change-tickets.csv evidence-YYYYMMDD/SOC2/Common_Criteria/
cp uptime-report.pdf evidence-YYYYMMDD/SOC2/Availability/
```

### Archiving

```bash
# Create archive
tar -czf compliance-evidence-$(date +%Y%m%d).tar.gz evidence-YYYYMMDD/

# Generate checksum
sha256sum compliance-evidence-$(date +%Y%m%d).tar.gz > compliance-evidence-$(date +%Y%m%d).tar.gz.sha256

# Upload to S3
aws s3 cp compliance-evidence-$(date +%Y%m%d).tar.gz \
    s3://biomate-compliance-evidence/$(date +%Y)/Q$(($(date +%-m)/3+1))/ \
    --server-side-encryption AES256
```

---

## Support

For questions about compliance evidence collection:

**Security Team:** security@biomate.ai
**Compliance Officer:** compliance@biomate.ai
**Privacy Officer:** privacy@biomate.ai

**Documentation:**
- HIPAA: `/home/biomate/biomate/20251111_1530_HIPAA_COMPLIANCE_GUIDE.md`
- SOC 2: (see this guide)
- Secrets: `/home/biomate/biomate/20251111_1525_SECRETS_MANAGEMENT_GUIDE.md`

---

**Document Version:** 1.0
**Last Updated:** 2025-11-11
**Next Review:** 2026-11-11
