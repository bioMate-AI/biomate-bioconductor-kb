# Security & Compliance Discussion Preparation

**Meeting Purpose:** SOC 2 and HIPAA compliance architecture review
**Date:** 2025-10-28
**Attendees:** BioMate team + Security consultant

---

## Key Documents for Discussion

### 1. **Authentication & Security Architecture** (PRIMARY)
**File:** `/home/yzhang/biomate/reference/AUTHENTICATION_SECURITY_ARCHITECTURE_20251028.md`

**Why Important:**
- OAuth 2.0 / JWT implementation
- Role-Based Access Control (RBAC)
- Session management
- API security (rate limiting, CORS)
- Audit logging

**Key Sections for SOC 2/HIPAA:**
- Section 5: Audit & Logging (SOC 2 CC7.2, CC7.3)
- Section 6: Compliance (HIPAA Technical Safeguards)
- Section 7: Security Controls (Access controls, encryption)

---

### 2. **Data Management Architecture**
**File:** `/home/yzhang/biomate/reference/DATA_MANAGEMENT_ARCHITECTURE_20251028.md`

**Why Important:**
- PHI (Protected Health Information) storage
- Encryption at rest (S3 SSE-S3/KMS)
- Encryption in transit (TLS 1.2+)
- Access logging (S3 access logs)
- Data lifecycle (retention, deletion)

**Key Sections for HIPAA:**
- Section 5: Security & Compliance (HIPAA § 164.312(a)(2)(iv), § 164.312(e)(1))
- Section 6: Cost Optimization (data retention policies)

---

### 3. **Payment & Billing System Design**
**File:** `/home/yzhang/biomate/reference/PAYMENT_BILLING_SYSTEM_DESIGN_20251028.md`

**Why Important:**
- PCI DSS compliance (Stripe handles card data)
- Financial data security
- Invoice audit trail

**Key Sections:**
- Section 5: Payment Processing (PCI DSS via Stripe)
- Section 9: Database Schema (audit trail)

---

### 4. **90-Day Clinical Deployment Strategy** (if available)
**File:** Referenced in roadmap as `../research_repos/Deploying Instrument-Agnostic Bioinformatics Platforms to Clinical Labs: A 90-Day Implementation Strategy.md`

**Why Important:**
- CAP/CLIA validation requirements
- Clinical compliance roadmap (12-18 months)
- Regulatory framework

---

## SOC 2 Compliance Checklist

### Common Criteria (CC)

| Control | Requirement | BioMate Implementation | Document Reference |
|---------|-------------|------------------------|-------------------|
| **CC1** | Control Environment | RBAC, separation of duties | Auth Architecture §4 |
| **CC2** | Communication | Security policies documented | All architecture docs |
| **CC3** | Risk Assessment | Threat modeling, pen testing | Auth Architecture §9 |
| **CC4** | Monitoring | CloudWatch, DataDog APM | Performance Plan §7 |
| **CC5** | Control Activities | Input validation, rate limiting | Auth Architecture §3 |
| **CC6** | Logical Access | MFA, SSO, session management | Auth Architecture §2, §3 |
| **CC7** | System Operations | Audit logging, change management | Auth Architecture §5 |
| **CC8** | Change Management | CI/CD, version control | (Need to document) |
| **CC9** | Risk Mitigation | Incident response plan | Auth Architecture §10 |

---

## HIPAA Compliance Checklist

### Technical Safeguards (§ 164.312)

| Requirement | Implementation | Document Reference |
|-------------|----------------|-------------------|
| **§ 164.312(a)(1)** Access Control | RBAC, JWT tokens, MFA | Auth Architecture §2, §4 |
| **§ 164.312(a)(2)(i)** Unique User ID | User ID in JWT claims | Auth Architecture §3 |
| **§ 164.312(a)(2)(ii)** Emergency Access | Break-glass accounts | Auth Architecture §4.5 |
| **§ 164.312(a)(2)(iii)** Auto Logoff | Session timeout (30 min) | Auth Architecture §3 |
| **§ 164.312(a)(2)(iv)** Encryption | TLS 1.2+, S3 SSE-S3 | Data Mgmt §5, Auth §6 |
| **§ 164.312(b)** Audit Controls | CloudTrail, app logs | Auth Architecture §5 |
| **§ 164.312(c)(1)** Integrity Controls | Data validation, checksums | Data Mgmt §2 |
| **§ 164.312(d)** Person/Entity Auth | Password policies, MFA | Auth Architecture §2 |
| **§ 164.312(e)(1)** Transmission Security | TLS 1.2+, VPN | Auth Architecture §6 |

### Administrative Safeguards (§ 164.308)

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| **§ 164.308(a)(1)(ii)(A)** Risk Analysis | Threat modeling | ⚠️ TODO |
| **§ 164.308(a)(1)(ii)(B)** Risk Management | Security controls | ✅ In Progress |
| **§ 164.308(a)(2)** Workforce Security | Background checks | ⚠️ TODO |
| **§ 164.308(a)(3)** Workforce Training | Security awareness | ⚠️ TODO |
| **§ 164.308(a)(4)** Contingency Plan | Backup/DR | ⚠️ TODO |
| **§ 164.308(a)(5)(ii)(C)** Log Review | Daily log monitoring | ⚠️ TODO |
| **§ 164.308(a)(6)(ii)** Response/Reporting | Incident response | ⚠️ TODO |

### Physical Safeguards (§ 164.310)

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| **§ 164.310(a)(1)** Facility Access | AWS data centers (SOC 2) | ✅ AWS handles |
| **§ 164.310(b)** Workstation Use | Policy required | ⚠️ TODO |
| **§ 164.310(c)** Workstation Security | Device encryption | ⚠️ TODO |
| **§ 164.310(d)(1)** Device/Media Controls | Data disposal policy | ⚠️ TODO |

---

## Key Discussion Points

### 1. **Business Associate Agreement (BAA)**

**Questions for Consultant:**
- When should we sign BAAs with vendors (AWS, Stripe, etc.)?
- What provisions must be in our BAAs?
- Do pilot customers (research use only) require BAAs?

**Current Status:**
- AWS BAA: ⚠️ Not signed yet (required before handling PHI)
- Stripe BAA: ⚠️ Check if available (financial data)
- GitHub: ❌ Not HIPAA compliant (no PHI in repos)

---

### 2. **Data Classification**

**Questions:**
- How do we classify clinical vs research data?
- Can we use the same infrastructure for both?
- What are the retention requirements?

**Proposed Classification:**

| Data Type | PHI? | Retention | Encryption | Access Control |
|-----------|------|-----------|------------|----------------|
| Patient genomic data | ✅ YES | 7 years (clinical) | KMS | Strict RBAC |
| Research data | ❌ NO | User-defined | SSE-S3 | Project-based |
| Workflow metadata | ❌ NO | 1 year | SSE-S3 | User-only |
| Audit logs | ✅ YES (if contains PHI) | 6 years | KMS | Admin-only |
| Financial data | ❌ NO (PCI scope) | 7 years | Stripe | Billing admin |

---

### 3. **Audit Logging**

**Questions:**
- What events must we log for SOC 2?
- How long must we retain logs?
- Who can access audit logs?

**Proposed Logging:**

```typescript
// Audit event schema
interface AuditEvent {
  timestamp: Date;
  eventType: 'auth' | 'data_access' | 'data_modify' | 'admin_action';
  userId: string;
  ipAddress: string;
  userAgent: string;
  resource: string;  // e.g., "workflow:wf_123"
  action: string;    // e.g., "read", "write", "delete"
  result: 'success' | 'failure';
  reason?: string;   // If failed
  metadata: any;
}

// Example: Log PHI access
{
  timestamp: "2025-10-28T10:30:00Z",
  eventType: "data_access",
  userId: "user_123",
  ipAddress: "203.0.113.42",
  resource: "patient:PT_456",
  action: "read",
  result: "success",
  metadata: {
    dataType: "genomic_vcf",
    fileSize: 1048576,
  }
}
```

**Retention:** 6 years (HIPAA requirement)

---

### 4. **Encryption Strategy**

**Questions:**
- SSE-S3 vs SSE-KMS: When to use each?
- Do we need customer-managed keys (BYOK)?
- TLS 1.2 vs 1.3?

**Proposed:**

| Data | Encryption at Rest | Encryption in Transit |
|------|-------------------|----------------------|
| PHI (clinical) | SSE-KMS (customer keys) | TLS 1.3 |
| Research data | SSE-S3 (AWS managed) | TLS 1.2+ |
| Application data | RDS encryption | TLS 1.2+ |
| Backups | S3 Glacier (SSE-S3) | TLS 1.2+ |

---

### 5. **Access Control**

**Questions:**
- Is RBAC sufficient or do we need ABAC?
- How granular should permissions be?
- Emergency access procedures?

**Proposed RBAC:**

| Role | Permissions | PHI Access |
|------|-------------|------------|
| Patient | Own data only | ✅ YES (own) |
| Clinician | Assigned patients | ✅ YES (assigned) |
| Researcher | Research projects | ❌ NO (de-identified) |
| Lab Tech | QC/analysis | ❌ NO (workflow only) |
| Admin | System config | ❌ NO (unless clinical admin) |
| Security Admin | Audit logs | ✅ YES (read-only) |

---

### 6. **Incident Response**

**Questions:**
- What constitutes a breach?
- Notification timeline (HIPAA: 60 days)?
- Who is responsible for notifications?

**Proposed Breach Response:**

```
Detection (0-4 hours)
  ↓
Assessment (4-8 hours)
  ↓
Containment (8-24 hours)
  ↓
Notification (if breach confirmed)
  - Affected individuals: Within 60 days (HIPAA)
  - HHS: Within 60 days (if >500 individuals)
  - Media: Immediately (if >500 individuals in state)
  ↓
Remediation
  ↓
Post-Incident Review
```

---

### 7. **Third-Party Risk Management**

**Questions:**
- How do we vet vendors for security?
- What security questionnaires should we use?
- Ongoing monitoring requirements?

**Current Vendors:**

| Vendor | Service | BAA Required? | SOC 2 Report? | Status |
|--------|---------|---------------|---------------|--------|
| AWS | Infrastructure | ✅ YES | ✅ YES | ⚠️ BAA needed |
| Stripe | Payments | ❌ NO (PCI only) | ✅ YES | ✅ OK |
| Anthropic | AI API | ⚠️ If PHI in prompts | ❓ Unknown | ⚠️ Check |
| DataDog | Monitoring | ⚠️ If logs contain PHI | ✅ YES | ⚠️ Review |
| GitHub | Code hosting | ❌ NO | ✅ YES | ✅ OK (no PHI) |

---

### 8. **Penetration Testing**

**Questions:**
- How often should we pen test?
- Internal vs external vendors?
- Scope of testing?

**Proposed Schedule:**
- Internal vulnerability scanning: Weekly (automated)
- External pen test: Annually (before SOC 2 audit)
- Application security review: Quarterly
- Social engineering test: Bi-annually

---

### 9. **Disaster Recovery**

**Questions:**
- RTO/RPO targets for SOC 2?
- Multi-region deployment required?
- Backup testing frequency?

**Proposed:**

| System | RTO | RPO | Backup Strategy |
|--------|-----|-----|-----------------|
| Application | 4 hours | 1 hour | Multi-AZ, daily snapshots |
| Database | 1 hour | 5 minutes | Continuous replication |
| S3 Data | N/A | N/A | 11 nines durability |
| Audit Logs | 24 hours | 1 hour | CloudWatch → S3 |

---

### 10. **Workforce Training**

**Questions:**
- What training is required for SOC 2/HIPAA?
- Frequency of training?
- How to document training completion?

**Proposed:**
- HIPAA training: All employees, annually
- Security awareness: All employees, quarterly
- Developer security training: Engineering, bi-annually
- Incident response drill: Security team, bi-annually

---

## Open Questions for Consultant

1. **Compliance Timeline:**
   - When should we start formal SOC 2 audit process?
   - Can we get SOC 2 Type I before Type II?
   - Is HIPAA self-attestation sufficient for pilot phase?

2. **Scope:**
   - Should research-use-only (RUO) be out of HIPAA scope?
   - Can we have separate clinical vs research environments?
   - Does AI-generated content (Claude responses) need special handling?

3. **Cost Estimates:**
   - SOC 2 audit costs?
   - Security tools (SIEM, vulnerability scanner)?
   - Consultant/auditor fees?

4. **Quick Wins:**
   - What are the highest-priority gaps to address now?
   - Any low-hanging fruit for compliance?

---

## Next Steps

### Immediate (This Week):
1. [ ] Sign AWS BAA
2. [ ] Enable S3 encryption enforcement
3. [ ] Configure CloudTrail logging
4. [ ] Implement session timeout (30 min)
5. [ ] Document security policies

### Short-term (Month 1):
1. [ ] Complete threat modeling
2. [ ] Implement comprehensive audit logging
3. [ ] Security training for team
4. [ ] Vulnerability scanning setup
5. [ ] Incident response plan

### Medium-term (Month 2-3):
1. [ ] SOC 2 Type I audit
2. [ ] Penetration testing
3. [ ] HIPAA compliance documentation
4. [ ] Disaster recovery testing
5. [ ] Policy and procedure documentation

### Long-term (Month 4-6):
1. [ ] SOC 2 Type II audit (requires 6+ months observation)
2. [ ] HIPAA validation for clinical use
3. [ ] CAP/CLIA compliance (if clinical lab)
4. [ ] Continuous compliance monitoring

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Owner:** BioMate Security Team
