#!/bin/bash
# HIPAA Security Risk Assessment Tool
# HIPAA §164.308(a)(1)(ii)(A) - Risk Analysis
# Version: 1.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ASSESSMENT_DIR="./hipaa-assessments"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ASSESSMENT_FILE="$ASSESSMENT_DIR/hipaa-risk-assessment-$TIMESTAMP.json"
REPORT_FILE="$ASSESSMENT_DIR/hipaa-risk-assessment-$TIMESTAMP.md"

mkdir -p "$ASSESSMENT_DIR"

echo "========================================="
echo "HIPAA Security Risk Assessment"
echo "========================================="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Assessor: $(whoami)@$(hostname)"
echo ""

# Initialize assessment data
cat > "$ASSESSMENT_FILE" <<EOF
{
  "metadata": {
    "assessment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "assessor": "$(whoami)@$(hostname)",
    "version": "1.0",
    "organization": "BioMate AI",
    "scope": "Production Environment"
  },
  "administrative_safeguards": {},
  "physical_safeguards": {},
  "technical_safeguards": {},
  "organizational_requirements": {},
  "policies_procedures": {},
  "risk_scores": {},
  "findings": [],
  "recommendations": []
}
EOF

# Risk scoring function
calculate_risk() {
    local likelihood=$1  # 1-5
    local impact=$2      # 1-5
    echo $((likelihood * impact))
}

# Assessment questions
total_questions=0
passed_questions=0
high_risks=0
medium_risks=0
low_risks=0

# Function to ask yes/no question
ask_question() {
    local category=$1
    local standard=$2
    local question=$3
    local evidence=$4

    total_questions=$((total_questions + 1))

    echo ""
    echo -e "${BLUE}[$total_questions] $category - $standard${NC}"
    echo "Question: $question"
    echo "Evidence required: $evidence"
    echo ""

    read -p "Is this control implemented? (y/n/p for partial): " answer

    local status=""
    local score=0

    case $answer in
        y|Y)
            status="COMPLIANT"
            score=0
            passed_questions=$((passed_questions + 1))
            echo -e "${GREEN}✓ Compliant${NC}"
            ;;
        p|P)
            status="PARTIAL"
            score=2
            medium_risks=$((medium_risks + 1))
            echo -e "${YELLOW}⚠ Partially Compliant${NC}"
            read -p "Describe gaps: " gaps
            ;;
        *)
            status="NON-COMPLIANT"
            score=4
            high_risks=$((high_risks + 1))
            echo -e "${RED}✗ Non-Compliant${NC}"
            read -p "Describe risk: " risk_desc
            ;;
    esac

    # Store finding
    local finding=$(jq -n \
        --arg cat "$category" \
        --arg std "$standard" \
        --arg q "$question" \
        --arg stat "$status" \
        --arg sc "$score" \
        --arg ev "$evidence" \
        --arg gaps "${gaps:-N/A}" \
        --arg risk "${risk_desc:-N/A}" \
        '{
            category: $cat,
            standard: $std,
            question: $q,
            status: $stat,
            risk_score: ($sc | tonumber),
            evidence: $ev,
            gaps: $gaps,
            risk_description: $risk
        }')

    # Append to findings
    jq ".findings += [$finding]" "$ASSESSMENT_FILE" > "$ASSESSMENT_FILE.tmp"
    mv "$ASSESSMENT_FILE.tmp" "$ASSESSMENT_FILE"
}

echo "This assessment covers all HIPAA Security Rule requirements."
echo "Answer honestly - this is for internal improvement, not punishment."
echo ""
read -p "Press Enter to begin assessment..."

# ============================================
# ADMINISTRATIVE SAFEGUARDS (§164.308)
# ============================================

echo ""
echo "========================================="
echo "ADMINISTRATIVE SAFEGUARDS (§164.308)"
echo "========================================="

# Security Management Process §164.308(a)(1)
ask_question "Administrative" "§164.308(a)(1)(ii)(A)" \
    "Has a comprehensive risk analysis been conducted to identify threats to ePHI?" \
    "Risk assessment document, threat modeling results"

ask_question "Administrative" "§164.308(a)(1)(ii)(B)" \
    "Are risk management policies in place to reduce risks to ePHI to reasonable levels?" \
    "Risk management plan, mitigation strategies document"

ask_question "Administrative" "§164.308(a)(1)(ii)(C)" \
    "Is there a sanction policy for workforce members who violate security policies?" \
    "HR policy document, disciplinary procedures"

ask_question "Administrative" "§164.308(a)(1)(ii)(D)" \
    "Are information system activities regularly reviewed (audit logs, access reports, security incidents)?" \
    "Audit log review schedule, security monitoring reports"

# Assigned Security Responsibility §164.308(a)(2)
ask_question "Administrative" "§164.308(a)(2)" \
    "Has a Security Official been designated responsible for HIPAA security?" \
    "Job description, organizational chart showing security officer"

# Workforce Security §164.308(a)(3)
ask_question "Administrative" "§164.308(a)(3)(i)(A)" \
    "Are there procedures to verify persons seeking ePHI access have appropriate authorization?" \
    "Access request forms, authorization procedures"

ask_question "Administrative" "§164.308(a)(3)(i)(B)" \
    "Are procedures in place for determining ePHI access based on job role?" \
    "Role-based access control matrix, job descriptions"

ask_question "Administrative" "§164.308(a)(3)(i)(C)" \
    "Are workforce clearance procedures implemented (background checks for PHI access)?" \
    "HR screening procedures, background check records"

ask_question "Administrative" "§164.308(a)(3)(ii)(B)" \
    "Are termination procedures in place to disable access immediately upon employment termination?" \
    "Termination checklist, access revocation logs"

# Information Access Management §164.308(a)(4)
ask_question "Administrative" "§164.308(a)(4)(ii)(B)" \
    "Are there procedures for granting access to ePHI based on access authorization policies?" \
    "Access control policy, approval workflows"

ask_question "Administrative" "§164.308(a)(4)(ii)(C)" \
    "Are there procedures for modifying access when job responsibilities change?" \
    "Access modification procedures, role change documentation"

# Security Awareness and Training §164.308(a)(5)
ask_question "Administrative" "§164.308(a)(5)(i)" \
    "Do all workforce members receive security awareness training?" \
    "Training records, attendance logs, training materials"

ask_question "Administrative" "§164.308(a)(5)(ii)(A)" \
    "Is there periodic training on security reminders (password management, phishing, etc.)?" \
    "Training schedule, security bulletin archives"

ask_question "Administrative" "§164.308(a)(5)(ii)(B)" \
    "Is there training on malware protection and detection?" \
    "Security training curriculum, malware awareness materials"

ask_question "Administrative" "§164.308(a)(5)(ii)(C)" \
    "Is there training on log-in monitoring procedures?" \
    "Access monitoring training, incident response training"

ask_question "Administrative" "§164.308(a)(5)(ii)(D)" \
    "Is there training on password management (creation, change, safeguarding)?" \
    "Password policy, security awareness training records"

# Security Incident Procedures §164.308(a)(6)
ask_question "Administrative" "§164.308(a)(6)(ii)" \
    "Are there procedures to identify, respond to, report, and mitigate security incidents?" \
    "Incident response plan, incident log"

# Contingency Plan §164.308(a)(7)
ask_question "Administrative" "§164.308(a)(7)(ii)(A)" \
    "Is there a data backup plan with procedures to create retrievable exact copies of ePHI?" \
    "Backup policy, backup logs, restore test results"

ask_question "Administrative" "§164.308(a)(7)(ii)(B)" \
    "Is there a disaster recovery plan to restore lost ePHI?" \
    "DR plan, DR test results, RTO/RPO documentation"

ask_question "Administrative" "§164.308(a)(7)(ii)(C)" \
    "Is there an emergency mode operation plan to continue critical business processes during emergencies?" \
    "Business continuity plan, emergency procedures"

ask_question "Administrative" "§164.308(a)(7)(ii)(D)" \
    "Are testing and revision procedures in place to test contingency plans?" \
    "DR test schedule, DR test reports, plan revision history"

ask_question "Administrative" "§164.308(a)(7)(ii)(E)" \
    "Are there procedures for obtaining ePHI during emergencies?" \
    "Emergency access procedures, emergency contact list"

# Evaluation §164.308(a)(8)
ask_question "Administrative" "§164.308(a)(8)" \
    "Is there a process to perform periodic technical and non-technical evaluations?" \
    "Evaluation schedule, audit reports, assessment results"

# Business Associate Contracts §164.308(b)(1)
ask_question "Administrative" "§164.308(b)(1)" \
    "Are Business Associate Agreements (BAAs) in place with all third parties handling ePHI?" \
    "Signed BAAs with AWS, Anthropic, OpenAI, etc."

# ============================================
# PHYSICAL SAFEGUARDS (§164.310)
# ============================================

echo ""
echo "========================================="
echo "PHYSICAL SAFEGUARDS (§164.310)"
echo "========================================="

# Facility Access Controls §164.310(a)(1)
ask_question "Physical" "§164.310(a)(1)" \
    "Are there policies limiting physical access to facilities with ePHI systems?" \
    "Facility access policy, datacenter security (AWS shared responsibility)"

ask_question "Physical" "§164.310(a)(2)(ii)" \
    "Are there procedures to restore access to ePHI after emergencies?" \
    "Facility restoration procedures, emergency access plans"

ask_question "Physical" "§164.310(a)(2)(iii)" \
    "Are there procedures to safeguard facilities during repair/maintenance?" \
    "Maintenance procedures, vendor access controls"

ask_question "Physical" "§164.310(a)(2)(iv)" \
    "Are there controls to validate physical access based on job role?" \
    "Access badge system, visitor logs, AWS datacenter compliance"

# Workstation Use §164.310(b)
ask_question "Physical" "§164.310(b)" \
    "Are there policies specifying proper workstation use for ePHI access?" \
    "Workstation use policy, clean desk policy"

# Workstation Security §164.310(c)
ask_question "Physical" "§164.310(c)" \
    "Are there physical safeguards for workstations accessing ePHI?" \
    "Screen privacy filters, automatic screen lock, cable locks"

# Device and Media Controls §164.310(d)(1)
ask_question "Physical" "§164.310(d)(2)(i)" \
    "Are there procedures for final disposal of ePHI media?" \
    "Media destruction policy, shredding/wiping procedures"

ask_question "Physical" "§164.310(d)(2)(ii)" \
    "Are there procedures for reuse of ePHI-containing media?" \
    "Media sanitization procedures, data wiping tools"

ask_question "Physical" "§164.310(d)(2)(iii)" \
    "Is there accountability for hardware/media movement (tracking, authorization)?" \
    "Asset management system, transfer logs"

ask_question "Physical" "§164.310(d)(2)(iv)" \
    "Are backups created before equipment movement?" \
    "Pre-move backup procedures, data transfer verification"

# ============================================
# TECHNICAL SAFEGUARDS (§164.312)
# ============================================

echo ""
echo "========================================="
echo "TECHNICAL SAFEGUARDS (§164.312)"
echo "========================================="

# Access Control §164.312(a)(1)
ask_question "Technical" "§164.312(a)(2)(i)" \
    "Does each user have a unique identifier for accessing ePHI?" \
    "User account listing, authentication logs"

ask_question "Technical" "§164.312(a)(2)(ii)" \
    "Are emergency access procedures in place for ePHI access during emergencies?" \
    "Emergency access procedures, break-glass account documentation"

ask_question "Technical" "§164.312(a)(2)(iii)" \
    "Are automatic logoff mechanisms implemented (session timeout)?" \
    "Session timeout configuration (15 minutes HIPAA), timeout logs"

ask_question "Technical" "§164.312(a)(2)(iv)" \
    "Is ePHI encrypted when at rest?" \
    "Encryption configuration, database encryption status, file encryption"

# Audit Controls §164.312(b)
ask_question "Technical" "§164.312(b)" \
    "Are hardware, software, and/or procedural mechanisms in place to record/examine ePHI access?" \
    "Audit log configuration, log retention policy (6+ years), SIEM"

# Integrity §164.312(c)(1)
ask_question "Technical" "§164.312(c)(2)" \
    "Are there mechanisms to authenticate ePHI integrity (checksums, hashes)?" \
    "Integrity verification procedures, checksum validation logs"

# Person or Entity Authentication §164.312(d)
ask_question "Technical" "§164.312(d)" \
    "Are procedures in place to verify persons/entities seeking ePHI access are who they claim?" \
    "MFA implementation, authentication mechanisms, identity verification"

# Transmission Security §164.312(e)(1)
ask_question "Technical" "§164.312(e)(2)(i)" \
    "Are integrity controls in place to ensure ePHI is not improperly modified during transmission?" \
    "TLS configuration, message authentication codes, checksums"

ask_question "Technical" "§164.312(e)(2)(ii)" \
    "Is ePHI encrypted during transmission over networks?" \
    "TLS 1.3 configuration, VPN usage, encrypted API calls"

# ============================================
# Generate Report
# ============================================

echo ""
echo "========================================="
echo "Calculating Risk Scores..."
echo "========================================="

compliance_percentage=$((passed_questions * 100 / total_questions))
total_risk_score=$((high_risks * 4 + medium_risks * 2 + low_risks * 1))

# Update risk scores in JSON
jq ".risk_scores = {
    total_questions: $total_questions,
    passed_questions: $passed_questions,
    compliance_percentage: $compliance_percentage,
    high_risks: $high_risks,
    medium_risks: $medium_risks,
    low_risks: $low_risks,
    total_risk_score: $total_risk_score
}" "$ASSESSMENT_FILE" > "$ASSESSMENT_FILE.tmp"
mv "$ASSESSMENT_FILE.tmp" "$ASSESSMENT_FILE"

# Generate recommendations based on findings
echo "Generating recommendations..."

jq -r '.findings[] | select(.status != "COMPLIANT") | .standard' "$ASSESSMENT_FILE" | while read -r standard; do
    recommendation=""

    case $standard in
        "§164.308(a)(1)"*)
            recommendation="Conduct comprehensive risk analysis and implement risk management program"
            ;;
        "§164.308(a)(5)"*)
            recommendation="Implement security awareness training program for all workforce members"
            ;;
        "§164.308(a)(6)"*)
            recommendation="Develop and test incident response procedures"
            ;;
        "§164.308(a)(7)"*)
            recommendation="Implement and test backup and disaster recovery procedures"
            ;;
        "§164.308(b)(1)")
            recommendation="Execute Business Associate Agreements with all third-party vendors"
            ;;
        "§164.312(a)(2)(iv)")
            recommendation="Implement encryption for all ePHI at rest (AES-256)"
            ;;
        "§164.312(b)")
            recommendation="Implement comprehensive audit logging with 6+ year retention"
            ;;
        "§164.312(d)")
            recommendation="Implement multi-factor authentication for all ePHI access"
            ;;
        "§164.312(e)(2)(ii)")
            recommendation="Implement TLS 1.3 for all ePHI transmissions"
            ;;
    esac

    if [[ -n "$recommendation" ]]; then
        rec_json=$(jq -n --arg s "$standard" --arg r "$recommendation" '{standard: $s, recommendation: $r}')
        jq ".recommendations += [$rec_json]" "$ASSESSMENT_FILE" > "$ASSESSMENT_FILE.tmp"
        mv "$ASSESSMENT_FILE.tmp" "$ASSESSMENT_FILE"
    fi
done

# ============================================
# Generate Markdown Report
# ============================================

cat > "$REPORT_FILE" <<EOF
# HIPAA Security Risk Assessment Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Assessor:** $(whoami)@$(hostname)
**Organization:** BioMate AI
**Scope:** Production Environment

---

## Executive Summary

**Overall Compliance:** $compliance_percentage%

**Risk Distribution:**
- 🔴 High Risk (Non-Compliant): $high_risks
- 🟡 Medium Risk (Partial): $medium_risks
- 🟢 Low Risk (Compliant): $passed_questions

**Total Risk Score:** $total_risk_score (Lower is better)

**Compliance Status:**
EOF

if [[ $compliance_percentage -ge 95 ]]; then
    echo "✅ **EXCELLENT** - Ready for HIPAA compliance certification" >> "$REPORT_FILE"
elif [[ $compliance_percentage -ge 80 ]]; then
    echo "⚠️  **GOOD** - Minor gaps remain, implement recommendations" >> "$REPORT_FILE"
elif [[ $compliance_percentage -ge 60 ]]; then
    echo "⚠️  **FAIR** - Significant gaps exist, prioritize high-risk items" >> "$REPORT_FILE"
else
    echo "🔴 **POOR** - Major compliance gaps, immediate action required" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

---

## Findings by Category

### Administrative Safeguards (§164.308)

EOF

jq -r '.findings[] | select(.category == "Administrative") |
    "**\(.standard)** - \(.question)\n- Status: \(.status)\n- Risk Score: \(.risk_score)\n- Gaps: \(.gaps)\n"' \
    "$ASSESSMENT_FILE" >> "$REPORT_FILE"

cat >> "$REPORT_FILE" <<EOF

### Physical Safeguards (§164.310)

EOF

jq -r '.findings[] | select(.category == "Physical") |
    "**\(.standard)** - \(.question)\n- Status: \(.status)\n- Risk Score: \(.risk_score)\n- Gaps: \(.gaps)\n"' \
    "$ASSESSMENT_FILE" >> "$REPORT_FILE"

cat >> "$REPORT_FILE" <<EOF

### Technical Safeguards (§164.312)

EOF

jq -r '.findings[] | select(.category == "Technical") |
    "**\(.standard)** - \(.question)\n- Status: \(.status)\n- Risk Score: \(.risk_score)\n- Gaps: \(.gaps)\n"' \
    "$ASSESSMENT_FILE" >> "$REPORT_FILE"

cat >> "$REPORT_FILE" <<EOF

---

## Priority Recommendations

EOF

# Add top 10 recommendations
jq -r '.recommendations | unique_by(.standard) | .[] |
    "- **\(.standard):** \(.recommendation)"' \
    "$ASSESSMENT_FILE" | head -10 >> "$REPORT_FILE"

cat >> "$REPORT_FILE" <<EOF

---

## Next Steps

1. **Immediate (< 1 week):**
   - Address all high-risk (non-compliant) findings
   - Implement critical security controls

2. **Short-term (1-4 weeks):**
   - Remediate medium-risk (partial) findings
   - Complete security awareness training

3. **Long-term (1-3 months):**
   - Implement remaining recommendations
   - Conduct follow-up assessment
   - Prepare for external audit

---

## Compliance Tracking

| Standard | Status | Target Date | Owner |
|----------|--------|-------------|-------|
EOF

jq -r '.findings[] | select(.status != "COMPLIANT") |
    "| \(.standard) | \(.status) | TBD | TBD |"' \
    "$ASSESSMENT_FILE" >> "$REPORT_FILE"

cat >> "$REPORT_FILE" <<EOF

---

## Assessment Methodology

This assessment follows the HIPAA Security Rule requirements outlined in 45 CFR Part 164, Subpart C.

**Assessment Criteria:**
- **Compliant (0 points):** Control fully implemented with documented evidence
- **Partial (2 points):** Control partially implemented with gaps
- **Non-Compliant (4 points):** Control not implemented or no evidence

**Risk Scoring:**
- Risk Score = Likelihood × Impact
- Total Risk Score = Sum of all non-compliant findings

---

## Supporting Documentation

**Evidence Files:**
- Assessment Data: \`$(basename "$ASSESSMENT_FILE")\`
- This Report: \`$(basename "$REPORT_FILE")\`

**Review Schedule:**
- Next Assessment: $(date -d '+90 days' '+%Y-%m-%d')
- Annual Re-assessment: $(date -d '+1 year' '+%Y-%m-%d')

---

**Assessment Complete**
**Report Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

---

## Appendix: HIPAA Security Rule Standards

### Administrative Safeguards (§164.308)
- (a)(1) Security Management Process
- (a)(2) Assigned Security Responsibility
- (a)(3) Workforce Security
- (a)(4) Information Access Management
- (a)(5) Security Awareness and Training
- (a)(6) Security Incident Procedures
- (a)(7) Contingency Plan
- (a)(8) Evaluation
- (b)(1) Business Associate Contracts

### Physical Safeguards (§164.310)
- (a)(1) Facility Access Controls
- (b) Workstation Use
- (c) Workstation Security
- (d)(1) Device and Media Controls

### Technical Safeguards (§164.312)
- (a)(1) Access Control
- (b) Audit Controls
- (c)(1) Integrity
- (d) Person or Entity Authentication
- (e)(1) Transmission Security
EOF

# Display summary
echo ""
echo "========================================="
echo "Assessment Complete!"
echo "========================================="
echo ""
echo -e "Compliance: ${GREEN}$compliance_percentage%${NC}"
echo -e "High Risks: ${RED}$high_risks${NC}"
echo -e "Medium Risks: ${YELLOW}$medium_risks${NC}"
echo -e "Low Risks: ${GREEN}$passed_questions${NC}"
echo ""
echo "Files created:"
echo "  - Data: $ASSESSMENT_FILE"
echo "  - Report: $REPORT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review report: cat $REPORT_FILE"
echo "  2. Prioritize high-risk findings"
echo "  3. Assign owners for remediation"
echo "  4. Set target completion dates"
echo "  5. Schedule follow-up assessment in 90 days"
echo ""
