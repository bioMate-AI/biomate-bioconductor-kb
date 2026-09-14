# SOW / PSA Review Memo — Sentry Assurance SOC 2 Type 2 Engagement

**Document reviewed:** `BioMate AI - SOC 2 - T2 - PSA - SOW - 08102026.docx`
**Parties:** Sentry Assurance, LLC (Delaware) ↔ BioMate AI LLC (Texas, 4625 Cedar Oaks Ln, Bellaire, TX)
**Effective date on document:** August 10, 2026
**Reviewer:** prepared for Yaoyun Zhang, 2026-09-01
**Bottom line:** ⚠️ **No red-line blockers, but do NOT sign until five commercial items are clarified in writing** (items #1–#5 below). The rest are standard professional-services terms noted for awareness.

> This is a business/commercial review to help you decide, not legal advice. For a signed attestation contract with indemnity, IP-assignment, and a non-standard third-party payment structure, a 30-minute review by counsel is worth it — I flag exactly what to point them at.

---

## A. Must clarify before signing (blocking)

### 1. The "$0 → billed to Workstreet" payment structure is the biggest open question
The SOW pricing section reads, in full: **"$0 – Audit fees will be billed directly to Workstreet."** That single line interacts with several other clauses in ways that need to be pinned down:

- **Who pays, and what is BioMate's residual exposure?** Workstreet (a Vanta-ecosystem MSP/vCISO partner) is evidently bundling/paying the audit fee. But **BioMate is the signing party on this PSA/SOW**, and multiple clauses make *the Client* liable for money:
  - §6.4(a) **Termination for convenience** — Client "shall invoice Client for all remaining amounts under such SOW that would have been due and payable as if Sentry Assurance had fully completed all Services." If the SOW value is $0 this is empty — but confirm there's no separate schedule where the real number lives.
  - §7.7 **late-payment interest / suspension**, §7.1 **deposit** — confirm no deposit is demanded of BioMate.
  - **Ask for and read the BioMate ↔ Workstreet agreement.** Confirm in writing that (a) BioMate owes Sentry nothing directly, and (b) if the Workstreet relationship lapses or Workstreet fails to pay, BioMate does **not** inherit the fee. Get this as a side letter or an email confirmation from both Sentry and Workstreet.

### 2. The rescheduling penalty is 120%, and our readiness gaps make it a live risk
SOW: *"Client … agrees to pay a rescheduling fee equal to twenty percent (20%) of the total contract value, **in addition to the total contract value**, should fieldwork need to be rescheduled within thirty (30) days of the scheduled start of fieldwork or if Client does not meet their responsibilities … within thirty (30) days of the start of fieldwork."*

- That is effectively **120% of contract value** if we slip inside the 30-day window or miss our responsibilities.
- Two problems: (a) **What is "total contract value" when the line item is $0?** If it references the Workstreet-paid amount, this penalty could be real money that lands on BioMate. (b) Given our current readiness (see `02_READINESS_SELF_ASSESSMENT.md`), slipping fieldwork is a realistic scenario. **Clarify the dollar basis and who bears it.** This clause is *the* financial reason to not schedule fieldwork until we are genuinely ready.

### 3. The observation/review period is blank ("to be mutually agreed")
The single most consequential scheduling term is undefined. Before this SOW means anything operationally you must decide:
- **Type 1 (as-of date) first, then Type 2**, or **straight Type 2** (a period, commonly 3 months for a first report)?
- The **start date of the observation period** — and because **SOC 2 has no remediation window** (confirmed in Sentry's own materials), that start date must be a day on which *all* in-scope controls are already live. Do not let this be set to a date before we're ready.

### 4. Scope is Security-only; HIPAA and other TSC are NOT in this SOW
- The examination is limited to **Common Criteria / Security** (2017 TSC). **No Availability, Confidentiality, Processing Integrity, or Privacy.**
- **HIPAA is not in scope of this SOW at all.** If you need a HIPAA report/attestation (likely, given BioMate handles biomedical and potentially clinical data), that is a **separate SOW** or a Vanta-framework track — confirm the path with Sentry/Workstreet.
- **Business call:** pharma/enterprise buyers of a health-data platform frequently ask for **Confidentiality** (and sometimes Availability) in a SOC 2. Adding them later is a re-scope with new fees. Decide now whether Security-only clears your sales pipeline. (Not a legal defect — a go-to-market decision.)

### 5. Confirm Sentry is a licensed CPA firm
A SOC 2 opinion under AT-C 105/205 must be issued by a **licensed CPA firm**. The SOW asserts the examination will be performed per those standards (§10.2(a) also reps compliance with law), but it does not name Sentry's CPA license/PCAOB/AICPA firm registration. **Ask for their firm license number / peer-review status** — cheap diligence that protects the value of the report you're paying (indirectly) for.

---

## B. Standard terms — noted for awareness (no action needed unless you disagree)

| # | Clause | What it says | Note |
|---|---|---|---|
| 6 | §6.1 **Auto-renewal** | 1-yr term, auto-renews yearly unless 90-day written non-renewal notice | Calendar the 90-day window (~May of each year). |
| 7 | SOW **Deposit forfeiture** | If Client terminates for convenience, any deposit is non-refundable | Only matters if a deposit is actually taken (see #1). |
| 8 | §12.2 **Liability cap** | Sentry's liability capped at fees paid/payable under the SOW | With a $0 SOW value, the cap is effectively ~$0 — Sentry carries little monetary liability to BioMate. Typical for attest firms; combine with #1. |
| 9 | §12.1 **No consequential damages** | Both parties waive indirect/consequential/lost-profit damages | Standard. |
| 10 | §11.1 vs §11.2 **Indemnity asymmetry** | Sentry indemnifies only for **willful, fraudulent, or grossly negligent** acts; Client indemnifies broadly (use of deliverables, bad data, negligence, breach, law violations) | Asymmetric but standard for attestation work. Sentry's ordinary negligence is not indemnified. |
| 11 | §16.12 **Governing law** | **Ohio (Cuyahoga County)** courts | Neither party is in Ohio (Sentry=DE, BioMate=TX). Inconvenient forum for us; usually non-negotiable for the firm. Minor. |
| 12 | §16.18 / §16.14 | Jury-trial waiver; prevailing-party attorney fees | Standard. |
| 13 | §13 **Non-solicitation** | No soliciting Sentry personnel for 12 months; penalty = 1 yr salary + recruitment costs | Standard; low risk for us. |
| 14 | §9.4 **Deliverable disclosure** | The SOC 2 report may be shared only **complete and unaltered, with legends intact** | Standard for a restricted-use report — you can share with customers under NDA but cannot excerpt/quote it in marketing. |
| 15 | §16.3 **Publicity** | Neither party may use the other's name/logo/announce the deal without prior written consent (not unreasonably withheld for client-list/logo use) | Means you can't publicly say "audited by Sentry" without their OK. Minor. |
| 16 | SOW ¶182 **Restricted-use report** | Report is for Client + specified knowledgeable parties only | Standard SOC 2. Fine for customer due-diligence sharing under NDA. |
| 17 | SOW ¶203 **Mgmt representation letter** | Must be signed or Sentry cannot issue the opinion (scope limitation) | Just be ready to sign it at the end. |
| 18 | §2.3 **Limited warranty** | 30-day non-conformity notice; sole remedy = cure or refund of prepaid fees | With $0 prepaid, the refund remedy is empty. Note. |
| 19 | §8.1 **IP / work-for-hire** | Client owns deliverables **upon full payment**; Sentry keeps pre-existing materials (grants us a license) | Standard. With third-party payment, confirm "full payment" is satisfied by Workstreet's payment so title vests in BioMate. |

---

## C. Drafting nits (cosmetic — not blocking)
- §2.3 begins "**In** the Services…" (should be "If") and switches to the undefined term "**Service Provider**" (elsewhere the firm is "Sentry Assurance"). Same defined-term slip appears in a couple of places.
- ¶156 "the receipt and **of** sufficiency of which."
- These don't change meaning but show the template wasn't fully cleaned — a reason to read the final signature version carefully.

---

## D. Recommendation

**Proceed to sign once items #1–#5 are answered in writing.** None is a deal-breaker; all are clarifications you're entitled to before committing:

1. Get the **Workstreet payment arrangement** in writing and confirm **zero residual payment exposure** for BioMate (fee, deposit, termination amounts, and the reschedule penalty).
2. Nail down the **"total contract value" basis** for the **120% reschedule penalty** and who bears it.
3. Decide **Type 1-then-2 vs. straight Type 2** and set an **observation-period start date only after we're ready** (protects against #2).
4. Confirm the **HIPAA path** and whether to add **Confidentiality/Availability** TSC now vs. later.
5. Confirm **Sentry's CPA firm licensure**.

Suggested one-line ask to Sentry + Workstreet (email):
> "Before we countersign, please confirm in writing: (a) BioMate owes no fees, deposit, termination, or rescheduling amounts directly — all audit fees are Workstreet's obligation; (b) the dollar basis and responsible party for the SOW's 20%+100% rescheduling fee; (c) whether HIPAA and any additional Trust Services Criteria are handled under this SOW or a separate one; and (d) Sentry's CPA firm license / peer-review status. We'll set the observation-period start date jointly once our Vanta control readiness clears your fieldwork threshold."
