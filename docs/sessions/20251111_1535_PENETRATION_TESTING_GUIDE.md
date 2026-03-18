# BioMate AI Penetration Testing Guide
**Date:** 2025-11-11
**Version:** 1.0
**Compliance:** SOC 2 CC7.1, HIPAA §164.308(a)(8)

---

## Table of Contents

1. [Overview](#overview)
2. [Penetration Testing Scope](#penetration-testing-scope)
3. [Pre-Testing Requirements](#pre-testing-requirements)
4. [Testing Methodology](#testing-methodology)
5. [Testing Checklist](#testing-checklist)
6. [Tools and Techniques](#tools-and-techniques)
7. [Reporting Requirements](#reporting-requirements)
8. [Remediation Process](#remediation-process)
9. [Vendor Selection Guide](#vendor-selection-guide)

---

## Overview

### Purpose

Penetration testing simulates real-world attacks to identify security vulnerabilities before malicious actors can exploit them. This is a **critical requirement** for:

- **SOC 2 Type II:** Demonstrates ongoing security monitoring and testing
- **HIPAA Security Rule:** §164.308(a)(8) requires periodic technical evaluations
- **Production Readiness:** Validates security controls before launch
- **Cyber Insurance:** Often required for coverage

### Testing Frequency

| Test Type | Frequency | Trigger Events |
|-----------|-----------|----------------|
| Automated Scanning | Weekly | Continuous |
| Internal Pentest | Quarterly | After major changes |
| External Pentest | Annually | Before production launch, after significant architecture changes |
| Red Team Exercise | Annually (optional) | Mature security program |

### Testing Types

**1. Black Box Testing**
- Tester has no prior knowledge of the system
- Simulates external attacker
- Tests perimeter defenses

**2. Gray Box Testing**
- Tester has partial knowledge (e.g., API documentation, user credentials)
- Simulates insider threat or compromised account
- Most common for web applications

**3. White Box Testing**
- Tester has full knowledge (source code, architecture diagrams, credentials)
- Most comprehensive coverage
- Finds deeper issues

**Recommendation for BioMate:** Start with **Gray Box** testing to balance cost and effectiveness.

---

## Penetration Testing Scope

### In-Scope Systems

**Production Environment:**
- ✅ Web application (https://biomate.ai)
- ✅ API endpoints (/api/*)
- ✅ Authentication/authorization mechanisms
- ✅ File upload/download functionality
- ✅ Workflow generation features
- ✅ Galaxy integration endpoints
- ✅ Database queries (SQL injection testing)
- ✅ Session management
- ✅ Third-party integrations (Claude API, OpenAI API)

**Infrastructure:**
- ✅ AWS security groups
- ✅ Network segmentation
- ✅ TLS/SSL configuration
- ✅ DNS configuration
- ✅ Email security (SPF, DKIM, DMARC)

### Out-of-Scope

**Excluded from Testing:**
- ❌ Physical security (AWS data centers)
- ❌ Social engineering (phishing, vishing)
- ❌ Denial of Service (DoS) attacks
- ❌ Third-party services (AWS, Anthropic, OpenAI internals)
- ❌ Production data deletion or modification
- ❌ Testing during peak hours (unless approved)

### Testing Boundaries

**Allowed:**
- ✅ Read-only database queries
- ✅ Creating test accounts
- ✅ Attempting authentication bypasses
- ✅ Testing for XSS, CSRF, injection flaws
- ✅ Attempting privilege escalation
- ✅ Testing rate limiting and input validation

**Not Allowed:**
- ❌ Deleting or modifying production data
- ❌ Attacking third-party services
- ❌ DoS or resource exhaustion attacks
- ❌ Physical intrusion attempts
- ❌ Social engineering without approval

---

## Pre-Testing Requirements

### 1. Authorization

**Required Documents:**
- [ ] Written authorization from CEO/CTO
- [ ] Signed Rules of Engagement (ROE)
- [ ] Emergency contact information
- [ ] Testing schedule approval

**Sample Authorization Letter:**

```
To: [Pentesting Vendor]
From: [Your Name, Title]
Date: [Date]

This letter authorizes [Vendor Name] to conduct penetration testing
on the following systems owned by BioMate AI:

Scope: https://biomate.ai and associated API endpoints
Duration: [Start Date] to [End Date]
Testing Hours: [Hours allowed]
Restrictions: No DoS attacks, no physical intrusion

Emergency Contacts:
- Security Lead: [Name] <[email]> [phone]
- DevOps Lead: [Name] <[email]> [phone]

Signed: ____________________
[Your Name, Title]
```

### 2. Environment Preparation

**Staging Environment (Recommended for Initial Tests):**
```bash
# Create staging environment that mirrors production
# Use separate AWS account or isolated VPC
# Populate with realistic (but synthetic) test data
# Enable enhanced logging
```

**Production Environment (Final Validation):**
```bash
# Backup all data before testing
./scripts/backup/backup-database.sh

# Enable detailed audit logging
# Notify team of testing schedule
# Prepare incident response team for potential false alarms
```

### 3. Baseline Security Scan

**Run before penetration test to establish baseline:**

```bash
# Run automated security scan
./scripts/security/test-security.sh > pentest-baseline-$(date +%Y%m%d).txt

# Check security score
./scripts/monitoring/check-security-status.sh

# Document current vulnerabilities (if any)
# Share baseline with pentesting team
```

### 4. Test Data Preparation

**Create test accounts:**
```sql
-- Low-privilege user
INSERT INTO users (username, email, role) VALUES
    ('pentest_user', 'pentest+user@biomate.ai', 'user');

-- Admin user (for privilege escalation testing)
INSERT INTO users (username, email, role) VALUES
    ('pentest_admin', 'pentest+admin@biomate.ai', 'admin');

-- Provide credentials to testing team
```

**Synthetic PHI data:**
```
# Create realistic but fake patient data for testing
# Use tools like Synthea or Mockaroo
# Ensure data is clearly marked as TEST
# Do not use real patient information
```

### 5. Monitoring Setup

**Enhanced monitoring during pentest:**

```bash
# Increase logging verbosity
sed -i 's/LOG_LEVEL=info/LOG_LEVEL=debug/' .env.production

# Monitor in real-time
aws logs tail /biomate/production/security --follow &
aws logs tail /biomate/production/audit --follow &

# Set up alerts for security team
# Create dedicated Slack channel for pentest alerts
```

---

## Testing Methodology

### Phase 1: Reconnaissance (2-4 hours)

**Objectives:**
- Gather information about the target
- Identify attack surface
- Map application functionality

**Activities:**
1. **Passive Reconnaissance:**
   - DNS enumeration (dig, nslookup, dnsdumpster.com)
   - WHOIS lookups
   - Google dorking
   - GitHub repository review (public information only)
   - SSL certificate transparency logs

2. **Active Reconnaissance:**
   - Port scanning (nmap)
   - Service enumeration
   - Technology fingerprinting (Wappalyzer)
   - Directory brute-forcing (dirbuster, gobuster)
   - Subdomain enumeration

**Example Commands:**
```bash
# DNS enumeration
dig biomate.ai ANY
dig biomate.ai NS
dig biomate.ai MX

# Subdomain enumeration
subfinder -d biomate.ai
amass enum -d biomate.ai

# Port scanning (with permission!)
nmap -sV -sC -p- biomate.ai

# Technology detection
whatweb https://biomate.ai
```

### Phase 2: Vulnerability Scanning (4-8 hours)

**Objectives:**
- Identify known vulnerabilities
- Find common misconfigurations
- Assess patch levels

**Activities:**
1. **Web Application Scanning:**
   - OWASP ZAP automated scan
   - Nikto web server scan
   - Burp Suite automated crawler
   - SSL/TLS testing (testssl.sh, SSL Labs)

2. **Dependency Scanning:**
   - npm audit (frontend)
   - pip-audit (backend)
   - Snyk or Dependabot analysis

3. **Configuration Review:**
   - Security headers check
   - CORS policy review
   - Cookie security attributes
   - CSP policy effectiveness

**Example Commands:**
```bash
# OWASP ZAP (using Docker)
docker run -t owasp/zap2docker-stable zap-baseline.py \
    -t https://biomate.ai

# Nikto scan
nikto -h https://biomate.ai

# SSL/TLS test
testssl.sh https://biomate.ai

# Dependency audit
cd frontend && npm audit
cd backend && pip-audit
```

### Phase 3: Manual Testing (16-32 hours)

**Objectives:**
- Find logic flaws and business logic vulnerabilities
- Test complex attack scenarios
- Validate automated findings

**Critical Test Areas:**

#### 3.1 Authentication & Session Management

**Tests:**
- [ ] Brute force protection (rate limiting)
- [ ] Password complexity enforcement
- [ ] Password reset flow security
- [ ] Account enumeration prevention
- [ ] Session token randomness and entropy
- [ ] Session fixation vulnerabilities
- [ ] Session timeout enforcement (15 minutes)
- [ ] Concurrent session handling
- [ ] Logout functionality
- [ ] "Remember me" security
- [ ] MFA bypass attempts
- [ ] OAuth/SSO implementation (if applicable)

**Example Tests:**
```bash
# Test brute force protection
for i in {1..100}; do
    curl -X POST https://biomate.ai/api/auth/login \
        -d '{"username":"admin","password":"wrong'$i'"}'
done
# Should trigger rate limiting after N attempts

# Test session fixation
# 1. Get session token before auth
# 2. Login
# 3. Check if session token changed

# Test session timeout
# 1. Login and get token
# 2. Wait 16 minutes
# 3. Try to use token (should fail)
```

#### 3.2 Authorization & Access Control

**Tests:**
- [ ] Horizontal privilege escalation (access other users' data)
- [ ] Vertical privilege escalation (user → admin)
- [ ] Insecure Direct Object References (IDOR)
- [ ] Missing function-level access control
- [ ] Parameter tampering
- [ ] Path traversal in API endpoints
- [ ] Forced browsing to admin pages
- [ ] API authorization bypass

**Example Tests:**
```bash
# Test IDOR (Insecure Direct Object Reference)
# As user A, try to access user B's data
curl -H "Authorization: Bearer <user_a_token>" \
    https://biomate.ai/api/users/user_b_id/profile
# Should return 403 Forbidden

# Test privilege escalation
# As regular user, try admin endpoint
curl -H "Authorization: Bearer <user_token>" \
    https://biomate.ai/api/admin/users
# Should return 403 Forbidden

# Parameter tampering
curl -H "Authorization: Bearer <token>" \
    "https://biomate.ai/api/workflows?user_id=another_user"
# Should not return another user's workflows
```

#### 3.3 Input Validation

**Tests:**
- [ ] SQL Injection (all input fields)
- [ ] NoSQL Injection (if using NoSQL)
- [ ] XSS (Reflected, Stored, DOM-based)
- [ ] XXE (XML External Entity)
- [ ] SSRF (Server-Side Request Forgery)
- [ ] Command Injection
- [ ] LDAP Injection
- [ ] Template Injection
- [ ] File upload vulnerabilities
- [ ] Path traversal

**Example Tests:**
```bash
# SQL Injection
curl "https://biomate.ai/api/search?q=' OR '1'='1"
curl "https://biomate.ai/api/search?q='; DROP TABLE users--"

# XSS
curl "https://biomate.ai/api/search?q=<script>alert('XSS')</script>"
curl -X POST https://biomate.ai/api/comments \
    -d '{"text":"<img src=x onerror=alert(1)>"}'

# Command Injection
curl "https://biomate.ai/api/tools/run?cmd=ls;cat%20/etc/passwd"
curl "https://biomate.ai/api/tools/run?cmd=$(whoami)"

# Path Traversal
curl "https://biomate.ai/api/files/download?file=../../../etc/passwd"
curl "https://biomate.ai/api/files/download?file=%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd"

# File Upload
# Upload executable file (.php, .sh, .exe)
# Upload file with malicious MIME type
# Upload oversized file (test size limits)
```

#### 3.4 Business Logic Vulnerabilities

**Tests:**
- [ ] Workflow manipulation
- [ ] Price/quantity manipulation (if applicable)
- [ ] Workflow approval bypass
- [ ] Race conditions
- [ ] Integer overflow/underflow
- [ ] Negative numbers in numeric fields
- [ ] Workflow state manipulation
- [ ] API rate limiting bypass
- [ ] Coupon/credit manipulation (if applicable)

**Example Tests:**
```bash
# Race condition (concurrent requests)
for i in {1..10}; do
    curl -X POST https://biomate.ai/api/workflows/create \
        -H "Authorization: Bearer <token>" \
        -d '{"name":"workflow"}' &
done
wait
# Check if more than allowed workflows created

# Negative quantity
curl -X POST https://biomate.ai/api/cart/add \
    -d '{"item_id":"123","quantity":-1}'

# Workflow state manipulation
curl -X PATCH https://biomate.ai/api/workflows/123 \
    -d '{"status":"approved"}' # Should require admin
```

#### 3.5 Cryptography

**Tests:**
- [ ] Weak encryption algorithms
- [ ] Hardcoded encryption keys
- [ ] Insufficient key length
- [ ] Missing encryption for sensitive data
- [ ] Predictable random number generation
- [ ] Insecure password storage (plaintext, MD5, SHA1)
- [ ] ECB mode encryption (should use GCM/CBC)
- [ ] TLS/SSL misconfigurations

**Example Tests:**
```bash
# Check password hashing
# (Requires code review or database access)
# Look for bcrypt/scrypt/Argon2, NOT MD5/SHA1

# Check encryption in transit
curl -v https://biomate.ai 2>&1 | grep "TLSv1.3"

# Check for hardcoded secrets in client-side code
curl https://biomate.ai | grep -i "api_key\|secret\|password"
```

#### 3.6 API Security

**Tests:**
- [ ] GraphQL introspection enabled (if using GraphQL)
- [ ] GraphQL DoS (deeply nested queries)
- [ ] REST API enumeration
- [ ] Missing authentication on API endpoints
- [ ] Excessive data exposure
- [ ] Mass assignment
- [ ] API versioning issues
- [ ] CORS misconfiguration
- [ ] Missing rate limiting

**Example Tests:**
```bash
# Test unauthenticated API access
curl https://biomate.ai/api/users
curl https://biomate.ai/api/admin/stats

# Mass assignment
curl -X POST https://biomate.ai/api/users/update \
    -d '{"username":"test","role":"admin"}' # Should not allow role change

# Excessive data exposure
curl https://biomate.ai/api/users/me
# Should not return sensitive fields (password_hash, etc.)

# CORS misconfiguration
curl -H "Origin: https://evil.com" https://biomate.ai/api/sensitive
# Check Access-Control-Allow-Origin header
```

### Phase 4: Exploitation (8-16 hours)

**Objectives:**
- Prove vulnerabilities are exploitable
- Assess real-world impact
- Chain vulnerabilities for maximum impact

**Activities:**
- Develop proof-of-concept exploits
- Attempt to access sensitive data (PHI in test environment)
- Chain vulnerabilities (e.g., XSS → session hijacking → admin access)
- Document exploitation steps with screenshots/videos

**Examples:**
```
1. XSS → Cookie Theft → Session Hijacking
   - Find stored XSS vulnerability
   - Inject payload to steal cookies
   - Use stolen cookie to hijack admin session
   - Access admin panel

2. IDOR → Data Breach
   - Find IDOR in /api/patients/:id endpoint
   - Enumerate all patient IDs
   - Download all patient records
   - Demonstrate PHI breach

3. SQL Injection → Database Compromise
   - Find SQL injection point
   - Extract database schema
   - Dump user credentials
   - Demonstrate full database access
```

### Phase 5: Post-Exploitation (4-8 hours)

**Objectives:**
- Assess persistence mechanisms
- Test lateral movement
- Evaluate detection capabilities

**Activities:**
- Create backdoor accounts (if permitted)
- Test incident detection (Are security team alerted?)
- Attempt to access other systems
- Evaluate logging and monitoring effectiveness

### Phase 6: Reporting (8-16 hours)

**Objectives:**
- Document all findings
- Provide remediation guidance
- Present executive summary

**Report Structure:**
1. Executive Summary
2. Testing Methodology
3. Findings (by severity)
4. Detailed Vulnerability Descriptions
5. Proof-of-Concept Exploits
6. Remediation Recommendations
7. Appendices (test evidence)

---

## Testing Checklist

### Pre-Test Checklist

- [ ] Written authorization obtained
- [ ] Rules of Engagement signed
- [ ] Testing schedule approved
- [ ] Emergency contacts documented
- [ ] Staging environment prepared
- [ ] Test accounts created
- [ ] Baseline security scan completed
- [ ] Team notified of testing dates
- [ ] Enhanced logging enabled
- [ ] Incident response team on standby

### OWASP Top 10 (2021) Testing Checklist

- [ ] **A01 - Broken Access Control**
  - [ ] IDOR testing
  - [ ] Privilege escalation
  - [ ] Forced browsing
  - [ ] Missing function-level access control

- [ ] **A02 - Cryptographic Failures**
  - [ ] TLS/SSL configuration
  - [ ] Sensitive data encryption (at rest and in transit)
  - [ ] Weak algorithms
  - [ ] Password storage

- [ ] **A03 - Injection**
  - [ ] SQL Injection
  - [ ] NoSQL Injection
  - [ ] OS Command Injection
  - [ ] LDAP Injection
  - [ ] XPath Injection

- [ ] **A04 - Insecure Design**
  - [ ] Business logic flaws
  - [ ] Missing security controls
  - [ ] Insufficient rate limiting
  - [ ] Workflow vulnerabilities

- [ ] **A05 - Security Misconfiguration**
  - [ ] Default credentials
  - [ ] Unnecessary features enabled
  - [ ] Missing security headers
  - [ ] Verbose error messages
  - [ ] Directory listing

- [ ] **A06 - Vulnerable and Outdated Components**
  - [ ] Dependency scanning (npm, pip)
  - [ ] Framework version checks
  - [ ] Library vulnerability checks

- [ ] **A07 - Identification and Authentication Failures**
  - [ ] Brute force protection
  - [ ] Session management
  - [ ] Password policies
  - [ ] MFA effectiveness

- [ ] **A08 - Software and Data Integrity Failures**
  - [ ] CI/CD pipeline security
  - [ ] Unsigned updates
  - [ ] Insecure deserialization

- [ ] **A09 - Security Logging and Monitoring Failures**
  - [ ] Audit logging effectiveness
  - [ ] Log tampering prevention
  - [ ] Incident detection capabilities

- [ ] **A10 - Server-Side Request Forgery (SSRF)**
  - [ ] SSRF in URL parameters
  - [ ] SSRF in file uploads
  - [ ] SSRF in webhooks

### HIPAA-Specific Testing

- [ ] PHI encryption at rest (AES-256)
- [ ] PHI encryption in transit (TLS 1.3)
- [ ] Access controls for PHI
- [ ] Audit logging for PHI access
- [ ] Session timeout (15 minutes or less)
- [ ] Unique user identification
- [ ] Emergency access procedures
- [ ] Integrity controls (checksums, MACs)
- [ ] Person/entity authentication (MFA)

### API Security Testing

- [ ] Authentication required on all endpoints
- [ ] Authorization enforced properly
- [ ] Rate limiting per endpoint
- [ ] Input validation
- [ ] Output encoding
- [ ] CORS configuration
- [ ] API versioning
- [ ] Error handling (no sensitive info leaked)

---

## Tools and Techniques

### Recommended Tools

**Web Application Testing:**
- [Burp Suite Professional](https://portswigger.net/burp) - Comprehensive web testing ($$)
- [OWASP ZAP](https://www.zaproxy.org/) - Free alternative to Burp
- [Nikto](https://github.com/sullo/nikto) - Web server scanner
- [SQLMap](https://sqlmap.org/) - SQL injection automation
- [XSSer](https://github.com/epsylon/xsser) - XSS detection and exploitation

**Network Scanning:**
- [Nmap](https://nmap.org/) - Port scanning and service enumeration
- [Masscan](https://github.com/robertdavidgraham/masscan) - Fast port scanner
- [testssl.sh](https://testssl.sh/) - TLS/SSL testing

**Vulnerability Scanning:**
- [Nessus](https://www.tenable.com/products/nessus) - Commercial vulnerability scanner ($$)
- [OpenVAS](https://www.openvas.org/) - Open-source vulnerability scanner
- [Nuclei](https://github.com/projectdiscovery/nuclei) - Fast vulnerability scanner

**Exploitation Frameworks:**
- [Metasploit](https://www.metasploit.com/) - Penetration testing framework
- [Empire](https://github.com/BC-SECURITY/Empire) - Post-exploitation framework
- [BeEF](https://beefproject.com/) - Browser exploitation framework

**Reconnaissance:**
- [Amass](https://github.com/OWASP/Amass) - Subdomain enumeration
- [Subfinder](https://github.com/projectdiscovery/subfinder) - Subdomain discovery
- [theHarvester](https://github.com/laramies/theHarvester) - OSINT gathering
- [Shodan](https://www.shodan.io/) - Internet-connected device search

**Cloud Security:**
- [ScoutSuite](https://github.com/nccgroup/ScoutSuite) - AWS security audit
- [Prowler](https://github.com/prowler-cloud/prowler) - AWS security assessment
- [CloudSploit](https://github.com/aquasecurity/cloudsploit) - Cloud configuration scanner

### Setting Up Testing Environment

```bash
# Install Kali Linux (recommended for pentesting)
# Download from: https://www.kali.org/get-kali/

# Or install tools on Ubuntu
sudo apt update
sudo apt install -y \
    nmap nikto sqlmap dirb gobuster \
    wfuzz john hashcat hydra \
    metasploit-framework zaproxy

# Install Burp Suite Community Edition
wget https://portswigger.net/burp/releases/download -O burpsuite.sh
chmod +x burpsuite.sh
./burpsuite.sh

# Install testssl.sh
git clone https://github.com/drwetter/testssl.sh.git
cd testssl.sh
./testssl.sh https://biomate.ai
```

---

## Reporting Requirements

### Findings Severity Classification

**Critical (P0):**
- Direct access to PHI without authentication
- SQL injection leading to database compromise
- Remote code execution
- Authentication bypass

**High (P1):**
- Privilege escalation (user → admin)
- Stored XSS on sensitive pages
- IDOR allowing access to other users' PHI
- Weak encryption of PHI

**Medium (P2):**
- Reflected XSS
- CSRF on non-critical functions
- Information disclosure (non-PHI)
- Weak password policy

**Low (P3):**
- Missing security headers (non-critical)
- Verbose error messages
- Directory listing
- Outdated libraries (no known exploits)

**Informational:**
- Best practice recommendations
- Defense-in-depth suggestions

### Report Template

```markdown
# Penetration Test Report: BioMate AI

## Executive Summary

**Test Date:** [Date]
**Tested By:** [Company/Individual]
**Test Type:** Gray Box Web Application Penetration Test
**Scope:** https://biomate.ai

**Summary of Findings:**
- Critical: X
- High: X
- Medium: X
- Low: X
- Informational: X

**Overall Risk Rating:** [Low/Medium/High/Critical]

**Recommendation:** [Pass/Conditional Pass/Fail]

## Findings

### Finding 1: SQL Injection in Search Function

**Severity:** Critical
**CVSS Score:** 9.8
**Affected Component:** /api/search endpoint
**Risk:** Complete database compromise, PHI exposure

**Description:**
The search endpoint is vulnerable to SQL injection through the `q` parameter...

**Proof of Concept:**
```bash
curl "https://biomate.ai/api/search?q=' UNION SELECT password FROM users--"
```

**Impact:**
- Attacker can dump entire database
- All PHI exposed
- User credentials compromised
- HIPAA breach notification required

**Remediation:**
1. Use parameterized queries (prepared statements)
2. Implement input validation
3. Apply principle of least privilege to database user

**Code Example:**
```typescript
// Vulnerable code
const results = await db.query(`SELECT * FROM data WHERE name = '${req.query.q}'`);

// Fixed code
const results = await db.query('SELECT * FROM data WHERE name = $1', [req.query.q]);
```

**Retest Date:** [Date]
**Retest Result:** [Pass/Fail]

---

[Repeat for each finding...]
```

---

## Remediation Process

### Immediate Actions (< 24 hours) for Critical Findings

1. **Assess impact** - Is production affected?
2. **Contain** - Disable vulnerable feature if necessary
3. **Notify** - Alert security team and stakeholders
4. **Patch** - Develop and test fix
5. **Deploy** - Push fix to production (emergency change)
6. **Verify** - Request pentester to retest
7. **Document** - Log in incident register

### Short-term Actions (< 1 week) for High Findings

1. Develop fix
2. Test in staging
3. Schedule deployment
4. Deploy to production
5. Request retest

### Medium/Long-term Actions (< 30 days) for Medium/Low Findings

1. Prioritize in backlog
2. Schedule for upcoming sprint
3. Implement fix
4. Test and deploy
5. Update documentation

### Tracking Remediation

**Create remediation tracker:**

| Finding ID | Severity | Description | Owner | Target Date | Status | Retest Result |
|------------|----------|-------------|-------|-------------|--------|---------------|
| PENTEST-001 | Critical | SQL Injection in /api/search | DevOps Lead | 2025-11-12 | Fixed | PASS |
| PENTEST-002 | High | Stored XSS in comments | Frontend Dev | 2025-11-15 | In Progress | Pending |
| PENTEST-003 | Medium | Missing CSRF token | Security Eng | 2025-11-30 | Backlog | Pending |

---

## Vendor Selection Guide

### Choosing a Penetration Testing Vendor

**Key Criteria:**

1. **Certifications:**
   - OSCP (Offensive Security Certified Professional)
   - CEH (Certified Ethical Hacker)
   - GPEN (GIAC Penetration Tester)
   - CREST certified (UK/EU)

2. **Experience:**
   - Healthcare/HIPAA experience (preferred)
   - Web application testing (required)
   - Cloud security (AWS preferred)
   - SaaS application testing

3. **Methodology:**
   - Follows OWASP Testing Guide
   - Uses industry-standard tools
   - Manual testing (not just automated scans)
   - Clear reporting

4. **Compliance:**
   - Understands SOC 2 requirements
   - Understands HIPAA requirements
   - Can provide evidence for audits
   - Willing to sign NDA/BAA

5. **Cost:**
   - $5,000 - $15,000 for small web application
   - $15,000 - $50,000 for comprehensive test
   - $50,000+ for red team engagement

**Recommended Vendors:**
- [NCC Group](https://www.nccgroup.com/)
- [Bishop Fox](https://bishopfox.com/)
- [Cobalt](https://cobalt.io/)
- [Synack](https://www.synack.com/)
- [HackerOne Pentesting](https://www.hackerone.com/product/pentesting)
- [Bugcrowd](https://www.bugcrowd.com/)

**Request for Proposal (RFP) Template:**

```
Subject: Request for Penetration Testing Services

BioMate AI is seeking a qualified penetration testing vendor for our
healthcare SaaS platform.

Scope:
- Web application (Node.js/TypeScript)
- RESTful API
- AWS infrastructure
- ~20,000 lines of code

Requirements:
- Gray box testing preferred
- HIPAA compliance experience
- Detailed report with remediation guidance
- Retesting included in price

Timeline:
- Testing window: [Date range]
- Report delivery: Within 2 weeks of testing completion

Deliverables:
- Executive summary
- Detailed technical report
- Proof-of-concept exploits
- Remediation recommendations
- Retest after fixes

Budget: $10,000 - $20,000

Please provide:
- Company overview and certifications
- Relevant experience (healthcare/SaaS)
- Testing methodology
- Sample report (redacted)
- Pricing and timeline
- References

Submit proposals by: [Date]
Contact: security@biomate.ai
```

---

## Appendix: Quick Reference

### Pre-Test Commands

```bash
# Backup production data
./scripts/backup/backup-database.sh

# Run baseline security scan
./scripts/security/test-security.sh

# Check security status
./scripts/monitoring/check-security-status.sh

# Enable debug logging
sed -i 's/LOG_LEVEL=info/LOG_LEVEL=debug/' .env.production
systemctl restart biomate-frontend biomate-backend
```

### Post-Test Commands

```bash
# Restore normal logging
sed -i 's/LOG_LEVEL=debug/LOG_LEVEL=info/' .env.production
systemctl restart biomate-frontend biomate-backend

# Delete test accounts
psql -h $DB_HOST -U $DB_USER -d biomate \
  -c "DELETE FROM users WHERE email LIKE 'pentest%';"

# Review findings and create tickets
# Import findings to issue tracker (GitHub, Jira, etc.)

# Schedule retest after remediation
```

### Emergency Response (If Active Attack Detected During Testing)

```bash
# 1. STOP THE TEST
# Contact pentester immediately: [phone]

# 2. Assess if real attack or authorized test
# Check testing window and authorized IPs

# 3. If real attack:
# Follow Incident Response Plan
# See: 20251111_1435_INCIDENT_RESPONSE_PLAN.md

# 4. If authorized test:
# Let testing continue
# Document false positive
```

---

**Document Owner:** Security Lead
**Last Updated:** 2025-11-11
**Next Review:** Before production launch, then annually
**Classification:** CONFIDENTIAL

---

**Related Documentation:**
- [Security Compliance Audit Report](20251111_1430_SECURITY_COMPLIANCE_AUDIT_REPORT.md)
- [Incident Response Plan](20251111_1435_INCIDENT_RESPONSE_PLAN.md)
- [Security Setup Guide](20251111_1445_SECURITY_SETUP_GUIDE.md)
- [Production Readiness Checklist](20251111_1510_PRODUCTION_READINESS_CHECKLIST.md)
