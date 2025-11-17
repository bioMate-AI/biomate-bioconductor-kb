# Legal Document Templates for BioMate AI

**⚠️ IMPORTANT DISCLAIMER ⚠️**

**These templates are provided for informational purposes only and DO NOT constitute legal advice.**

**YOU MUST:**
- Have these documents reviewed by qualified legal counsel
- Customize all [BRACKETED] sections
- Ensure compliance with your specific jurisdiction
- Update regularly as laws change

**DO NOT use these templates without legal review!**

---

## Available Templates

### 1. Terms of Service
**File:** `TERMS_OF_SERVICE_TEMPLATE.md`

**Purpose:** Governs the use of your platform and protects your business.

**Key Sections:**
- Account registration and responsibilities
- Acceptable use policy
- Intellectual property rights
- Limitation of liability
- Dispute resolution
- HIPAA provisions for BAA customers

**Customization Required:**
- [ ] Legal entity name and address
- [ ] Pricing and payment terms
- [ ] Liability caps (consult insurance provider)
- [ ] Arbitration clause (optional)
- [ ] State/jurisdiction for governing law
- [ ] Contact information

**Legal Review Needed:**
- Corporate attorney
- Intellectual property attorney (if applicable)
- HIPAA attorney (for healthcare provisions)

---

### 2. Privacy Policy
**File:** `PRIVACY_POLICY_TEMPLATE.md`

**Purpose:** Explains how you collect, use, and protect user data.

**Key Sections:**
- Data collection practices
- Data usage and sharing
- Security safeguards
- User rights (GDPR, CCPA)
- Cookies and tracking
- International data transfers
- HIPAA privacy provisions

**Customization Required:**
- [ ] Legal entity name and address
- [ ] Data inventory (what you collect)
- [ ] Third-party subprocessors list
- [ ] Data retention periods
- [ ] Contact information (Privacy Officer, DPO)
- [ ] Cookie policy details

**Legal Review Needed:**
- Privacy attorney
- GDPR specialist (if serving EU)
- CCPA specialist (if serving California)
- HIPAA attorney (for PHI provisions)

**Compliance Considerations:**
- **GDPR** (EU General Data Protection Regulation)
- **CCPA** (California Consumer Privacy Act)
- **HIPAA** (Health Insurance Portability and Accountability Act)

---

### 3. HIPAA Notice of Privacy Practices
**File:** `HIPAA_NOTICE_OF_PRIVACY_PRACTICES_TEMPLATE.md`

**Purpose:** Required for organizations handling PHI under HIPAA.

**Key Sections:**
- How PHI may be used and disclosed
- Individual rights regarding PHI
- Your responsibilities as a Business Associate
- Breach notification procedures
- How to file complaints

**Customization Required:**
- [ ] Legal entity name and address
- [ ] Privacy Officer designation
- [ ] Security Officer designation
- [ ] Specific uses and disclosures you make
- [ ] Safeguards you implement
- [ ] Contact information

**Legal Review Needed:**
- HIPAA attorney (mandatory)
- Healthcare compliance specialist

**When Required:**
- You handle PHI for Covered Entities
- You have signed Business Associate Agreements
- You're a Covered Entity yourself

**When NOT Required:**
- You only handle de-identified data
- You have no Business Associate Agreements
- You don't handle health data

---

## Implementation Checklist

### Phase 1: Legal Review (1-2 weeks)

- [ ] Engage qualified legal counsel
- [ ] Provide business context and data practices
- [ ] Review and customize all three templates
- [ ] Address jurisdiction-specific requirements
- [ ] Finalize documents with attorney signatures

**Estimated Cost:** $2,000 - $10,000 depending on complexity

### Phase 2: Customization (1 week)

- [ ] Fill in all [BRACKETED] sections
- [ ] Remove inapplicable sections
- [ ] Add company-specific provisions
- [ ] Ensure consistency across documents
- [ ] Set effective dates

### Phase 3: Internal Review (1 week)

- [ ] Review with executive team
- [ ] Review with engineering/product team
- [ ] Ensure technical accuracy
- [ ] Verify all contact information
- [ ] Get final approvals

### Phase 4: Publication (1-2 days)

- [ ] Convert to final format (Markdown, HTML, PDF)
- [ ] Post on website (biomate.ai/terms, biomate.ai/privacy, biomate.ai/hipaa-notice)
- [ ] Archive previous versions
- [ ] Update footer links across website
- [ ] Implement "I agree" checkboxes in app
- [ ] Send notification of changes (if required)

### Phase 5: Ongoing Maintenance

- [ ] Annual legal review (minimum)
- [ ] Review after significant product changes
- [ ] Review after regulatory changes
- [ ] Monitor enforcement actions in your industry
- [ ] Keep subprocessor list updated

---

## Jurisdiction-Specific Considerations

### United States

**Federal Laws:**
- HIPAA (if handling PHI)
- FTC Act (prohibits deceptive practices)
- CAN-SPAM Act (email marketing)
- COPPA (if directed to children under 13)

**State Laws:**
- California: CCPA, CPRA
- Virginia: VCDPA
- Colorado: CPA
- [Add other state laws as applicable]

**Requirements:**
- Clear, conspicuous terms
- Reasonable limitation of liability
- Arbitration clauses (optional but common)

### European Union (GDPR)

**Additional Requirements:**
- Legal basis for processing
- Data Protection Officer (if required)
- Data Processing Agreements (DPAs)
- Explicit consent for certain processing
- Right to be forgotten
- Data portability

**Resources:**
- [GDPR official text](https://gdpr-info.eu/)
- [EU Data Protection Board guidelines](https://edpb.europa.eu/)

### California (CCPA/CPRA)

**Additional Requirements:**
- "Do Not Sell My Personal Information" link
- Detailed category listings
- Annual disclosure of data practices
- Opt-out mechanisms

**Resources:**
- [California Attorney General CCPA](https://oag.ca.gov/privacy/ccpa)

---

## Common Mistakes to Avoid

### ❌ Don't:

1. **Copy-paste without review** - Every business is unique
2. **Ignore jurisdictional differences** - Laws vary by location
3. **Use without legal counsel** - Templates are starting points, not final documents
4. **Forget to update** - Review annually at minimum
5. **Make promises you can't keep** - Ensure technical implementation matches promises
6. **Use overly broad language** - Be specific about your practices
7. **Forget about mobile apps** - Different rules may apply
8. **Neglect accessibility** - Provide in plain language, multiple formats
9. **Skip version control** - Archive all versions with effective dates
10. **Assume one-size-fits-all** - Customize for your specific situation

### ✅ Do:

1. **Engage qualified legal counsel** - Worth the investment
2. **Be transparent** - Clear, honest language builds trust
3. **Stay current** - Laws and best practices evolve
4. **Match implementation** - Ensure your technical practices align
5. **Test user flows** - Verify consent mechanisms work
6. **Keep records** - Document when users agreed to terms
7. **Train your team** - Everyone should understand privacy obligations
8. **Respond to requests promptly** - Have processes for access, deletion, etc.
9. **Monitor compliance** - Regular audits and assessments
10. **Plan for breaches** - Have incident response procedures ready

---

## Required Consents and Displays

### In Your Application

**Terms of Service:**
- Display during account registration
- Require checkbox: "I have read and agree to the Terms of Service"
- Link to full terms
- Archive user acceptance with timestamp

**Privacy Policy:**
- Display during account registration
- Link in footer of every page
- Separate consent for marketing (optional)
- Cookie consent banner (for EU users)

**HIPAA Notice:**
- Provide to Covered Entity clients
- Post on website
- Obtain acknowledgment of receipt
- Make available for download

### Example Consent Flow

```html
<form>
  <input type="checkbox" id="terms" required>
  <label for="terms">
    I have read and agree to the
    <a href="/terms" target="_blank">Terms of Service</a>
  </label>

  <input type="checkbox" id="privacy" required>
  <label for="privacy">
    I have read and understand the
    <a href="/privacy" target="_blank">Privacy Policy</a>
  </label>

  <!-- For BAA customers only -->
  <input type="checkbox" id="hipaa">
  <label for="hipaa">
    I acknowledge receipt of the
    <a href="/hipaa-notice" target="_blank">HIPAA Notice of Privacy Practices</a>
  </label>

  <button type="submit">Create Account</button>
</form>
```

---

## Coordinating with Business Associate Agreements

If you're a Business Associate under HIPAA, your legal documents must align with your BAAs:

**Terms of Service must:**
- Prohibit PHI upload without a BAA
- Reference HIPAA obligations for BAA customers
- Define allowed uses of PHI

**Privacy Policy must:**
- Describe HIPAA safeguards
- Explain PHI handling practices
- Reference HIPAA Notice

**HIPAA Notice must:**
- Describe your Business Associate role
- Explain limited uses of PHI
- Provide breach notification procedures

**BAA (separate document) must specify:**
- Permitted uses and disclosures
- Safeguard requirements
- Breach reporting obligations
- Termination provisions

---

## Resources

### Legal Guidance

**HIPAA:**
- HHS Office for Civil Rights: https://www.hhs.gov/hipaa
- HIPAA Privacy Rule: https://www.hhs.gov/hipaa/for-professionals/privacy
- HIPAA Security Rule: https://www.hhs.gov/hipaa/for-professionals/security

**GDPR:**
- Official text: https://gdpr-info.eu/
- EDPB guidelines: https://edpb.europa.eu/

**CCPA:**
- California AG: https://oag.ca.gov/privacy/ccpa
- IAPP resources: https://iapp.org/

### Attorney Directories

- American Bar Association: https://www.americanbar.org/
- Martindale-Hubbell: https://www.martindale.com/
- Avvo: https://www.avvo.com/

### Privacy Certifications

- CIPP (Certified Information Privacy Professional)
- CIPM (Certified Information Privacy Manager)
- CIPT (Certified Information Privacy Technician)

---

## Document Version Control

### File Naming Convention

When publishing final versions:
- `terms-of-service-v1.0-20251111.md`
- `privacy-policy-v1.0-20251111.md`
- `hipaa-notice-v1.0-20251111.md`

### Change Log Format

```markdown
## Version History

### Version 1.1 (2025-12-01)
- Updated data retention periods
- Added new subprocessor (Service XYZ)
- Clarified cookie usage
- **Material Change:** Updated dispute resolution clause

### Version 1.0 (2025-11-11)
- Initial publication
```

### Notification Requirements

**Material Changes:**
- Email all users 30 days before effective date
- Prominent banner on website
- Require re-acceptance for Terms of Service

**Non-Material Changes:**
- Update "Last Updated" date
- Post on website
- Optional notification

---

## Contact for Legal Questions

**DO NOT contact BioMate for legal advice on these templates.**

These templates are provided as-is without warranty. You must engage your own legal counsel.

**For template questions (not legal advice):**
Email: legal-templates@biomate.ai

**For qualified legal counsel:**
Consult:
- Technology attorney
- Privacy attorney
- HIPAA attorney (for healthcare)
- Your state bar association for referrals

---

## License

These templates are provided under [LICENSE TYPE].

**Permitted:**
- Use for your business (after legal review)
- Customize for your specific needs
- Share with your legal counsel

**Not Permitted:**
- Redistribution as templates
- Commercial sale
- Use without legal review
- Claiming as your own work

---

**Last Updated:** 2025-11-11
**Template Version:** 1.0

**REMEMBER: These are templates, not final legal documents. Always consult qualified legal counsel before use.**
