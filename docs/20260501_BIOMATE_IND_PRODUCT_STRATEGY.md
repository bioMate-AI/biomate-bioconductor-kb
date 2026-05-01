# BioMate IND Module 2.6 — Product Strategy

**Date:** 2026-05-01  
**Status:** Internal strategic document  
**Scope:** Go-to-market, regulatory positioning, reviewer model, publication strategy

---

## 1. Is This the Product?

**Yes. This is the core product, not a feature.**

BioMate has built something that does not exist in the market: automated generation of
ICH M4 CTD §2.6.1–§2.6.5 from computational pipeline outputs. Every other tool in
this space either (a) requires completed wet-lab study reports to summarise, or (b)
does not produce CTD-formatted regulatory output at all.

The IND writing market is large, underserved by technology, and has a clear pain point:
regulatory affairs scientists spend 40–80 hours per compound reformatting and narrating
computational predictions that already exist in databases and workflow outputs. BioMate
collapses this to minutes of generation + hours of human review.

### Market Size

| Segment | Size (2025) | CAGR | BioMate Relevance |
|---------|------------|------|--------------------|
| Global regulatory writing services | ~$4.2B | 12% | Direct replacement for nonclinical writing |
| IND applications filed (FDA/year) | 5,000–7,000 | stable | Each needs a §2.6 package |
| Computational CRO services | ~$3.5B | 15% | Differentiator for CRO customers |
| ADMET/PBPK software (Certara, Schrödinger) | ~$800M | 10% | We sit above them in the stack |

**Realistic near-term ARR scenarios:**

| Model | Customers | Price | ARR |
|-------|-----------|-------|-----|
| Per-campaign SaaS | 200 campaigns/yr | $20–40K | $4–8M |
| Platform license | 20 pharma/biotech | $100–200K/yr | $2–4M |
| CRO white-label | 5 CROs | $200K/yr | $1M |
| Combined (year 2–3) | — | — | **$10–20M** |

These are conservative numbers with a 5–10 person team. The Certara model —
platform license + consulting bundle — typically generates $50–200K per client per year
with high renewal rates (regulatory tools are sticky once workflows are built around them).

### Why Now

Three external forces converge in 2026:

1. **ICH S7B(R1) Step 4 (November 2024)** formally validates in silico hERG as acceptable
   for screening. This is the first time a major ICH guideline explicitly endorses
   computational safety pharmacology for regulatory use. BioMate can cite this directly.

2. **FDA/EMA Joint AI Guidance (January 2026)** legitimises AI-generated regulatory
   content with disclosure + human review. The eSig + audit trail we built is precisely
   what this guidance calls for.

3. **AutoIND preprint (arXiv:2509.09738, September 2025)** demonstrates that the
   research community is converging on this problem — but AutoIND requires completed
   wet-lab study reports and does not cover §2.6.1 computational pharmacology.
   We have a 6–12 month window to publish first from the computational-data-first angle.

---

## 2. Can a Computational Package Be Submitted to FDA?

**Yes — at the pre-IND stage. No — as a standalone full Phase I IND.**

### Clarification on 21 CFR §312.23(a)(8)

The regulation says nonclinical data "may consist of published literature or unpublished
studies." This phrase was drafted in the 1970s–80s. **"Unpublished studies" means
proprietary in-house wet-lab studies not yet published — not computational models.**
FDA has never formally interpreted this phrase to include in silico predictions as a
substitute for required in vitro studies.

The operative standard — "sufficient to reasonably conclude it is safe to proceed" —
has been operationalised by FDA through ICH M3(R2) to require specific in vitro studies
before first-in-human (FIH) dosing:

- In vitro genotoxicity (Ames + chromosomal aberration) per ICH S2(R1) §4:
  *"should ordinarily be completed before initiation of human clinical trials"*
- In vitro hERG per ICH S7B(R1): *"In vitro assays for hERG channel current inhibition
  should be conducted before first-in-human studies"* — even though S7B(R1) Step 4
  (November 2024) formally validates in silico screening, it explicitly does NOT
  allow in silico to replace the GLP in vitro assay for FIH decisions

**BioMate's computational data is appropriate for §2.6.1** (which ICH M4S(R2) defines as
the computational pharmacology section) and the **pre-IND meeting context**. It cannot
stand alone as the §2.6.3 toxicology evidentiary basis for a Phase I IND.

The correct framing: BioMate generates the computational scaffold that (a) is submitted
in the pre-IND meeting, (b) informs the GLP study design, and (c) is progressively
enriched with wet-lab data as studies complete.

### Pathway 1: Pre-IND Meeting Package (Primary Target)

**Regulatory basis:** 21 CFR §312.82 — "Pre-IND meetings"

FDA routinely holds pre-IND meetings where sponsors present their development plan
and request written guidance. The package submitted for this meeting typically contains:
- Literature review of the compound class
- In silico/in vitro pharmacology and safety screening results
- Proposed nonclinical study plan
- Proposed Phase I clinical protocol design

**Computational ADMET + PBPK + in silico Ames/hERG is standard here.**
FDA's written response gives sponsors a formal record of what studies they will accept
for the full IND — before they spend $2–5M on GLP studies. This is the primary
use case for BioMate output today.

### Pathway 2: Exploratory/Phase 0 IND

**Regulatory basis:** FDA Guidance "Exploratory IND Studies" (January 2006)

Phase 0 studies use sub-therapeutic microdoses and require minimal nonclinical
support — primarily computational/in vitro characterisation with no in vivo GLP tox.
BioMate's output directly supports this pathway.

### Pathway 3: Full Phase I IND (BioMate as Draft Only)

**Regulatory basis:** 21 CFR §312.23(a)(8) + ICH M3(R2)

A full Phase I IND requires:
- GLP in vitro genotoxicity (Ames + chromosomal aberration) per ICH S2(R1)
- GLP in vitro hERG patch clamp per ICH S7B(R1)
- In vivo single-dose toxicity (2 species) per ICH M3(R2)
- Safety pharmacology core battery in vivo per ICH S7A

BioMate generates the written §2.6 narrative and tabulated summaries for these sections,
but with "studies planned" placeholders until wet-lab data is uploaded via the
`wetlab_data` parameter. The wet-lab ingester then replaces placeholders with measured
values. The full §2.6 package evolves: **computational draft → wet-lab enriched →
GLP-complete filing.**

### Summary

| Submission Type | Computational-only acceptable? | BioMate role |
|----------------|-------------------------------|--------------|
| Pre-IND meeting | ✅ Yes, standard practice | Primary output |
| Phase 0 / exploratory IND | ✅ Yes, FDA 2006 guidance | Full support |
| Full Phase I IND | ⚠️ Draft only; wet-lab sections required | Draft + ingest pipeline |
| NDA/BLA Module 2.6 | ❌ Complete wet-lab data required | Document formatting layer |

---

## 3. Human Review Model

**Who signs off on the BioMate-generated document before it goes to FDA?**

This is a non-negotiable legal requirement. The FDA AI Guidance (Jan 2026) and
21 CFR Part 11 §11.50 both require that someone with relevant credentials is named
as the responsible reviewer. BioMate provides the document; a human must approve it.

### Model A — Startup Internal Reviewer (Standard Case)

The startup's computational chemist, DMPK scientist, or regulatory affairs officer
reviews the BioMate-generated draft and clicks "Approve & Sign" in the eSig workflow.

**Requirements for this person:**
- PhD or MSc in pharmacology, medicinal chemistry, pharmaceutical sciences, or equivalent
- Familiarity with ICH M4, S7B, S2(R1) structure (a one-day training suffices)
- Responsibility for the scientific content they sign

This is the same model as GitHub Copilot — the tool generates, the professional reviews
and accepts. The startup employee is the named author; BioMate is the drafting tool.

**This is viable for:** Biotech/pharma with at least one computational scientist on staff.
Typical early-stage biotech (Series A+) has this person.

### Model B — Contract Regulatory Affairs Reviewer (Add-On Service)

For very early-stage companies (seed-stage, 3–5 people, no regulatory staff):

BioMate contracts with a network of regulatory affairs consultants (CRAs) who provide:
- Document review (2–4 hours per package at $200–400/hour = $400–1,600 per review)
- Named sign-off on the eSig record
- Consultation notes on gaps and recommended next steps

This is a services revenue stream on top of the SaaS fee and is how Certara structures
its business — software licenses + consulting services (consulting is ~40% of their revenue).

**Pricing:** $2,000–5,000 add-on per IND package for professional review service.

### What We Need to Implement

The current eSig record captures `user_id`, `action`, `meaning`, and `totp_token`.
For regulatory defensibility, add optional fields:
- `reviewer_title` — e.g. "Director, Computational Pharmacology"  
- `reviewer_credentials` — e.g. "PhD Pharmacology, 10 years IND experience"
- `review_scope` — e.g. "§2.6.1–§2.6.5 computational pharmacology and PK"

These appear in the audit trail and are cited in the document footer alongside the
existing "AI-assisted draft — human reviewed and approved" disclosure.

---

## 4. Publication, Blog, and Marketing

### Sequence

The correct order is: **paper → preprint → blog → conference → press → sales**

Each step builds credibility for the next. Without the paper, marketing claims are
unverifiable and regulatory-minded customers will not trust them.

---

### Paper

**Status:** Manuscript ~80% complete at `research/20260429_BIOMATE_IND_MANUSCRIPT.md`

**Remaining work (~1 week):**
- Add §2.6.4/§2.6.5 tabulated summary results to Methods and Results sections
- Add document freeze/hash section to the 21 CFR Part 11 compliance discussion
- Update abstract to reflect full §2.6.1–§2.6.5 scope
- Add OSP benchmark comparison (GMFE, within-2-fold vs approved range)
- Add wet-lab ingestion pipeline to Methods

**Target journals (in priority order):**

| Journal | Impact | Why |
|---------|--------|-----|
| *Journal of Cheminformatics* (SpringerNature) | 8.6 | Gold standard for computational drug discovery methods; open access |
| *Drug Discovery Today* (Elsevier) | 7.5 | Wide pharma industry readership; review/research letters |
| *CPT: Pharmacometrics & Systems Pharmacology* (Wiley/ASCPT) | 4.8 | PBPK and regulatory pharmacology focus; ASCPT audience is FDA reviewers |
| *Molecular Informatics* (Wiley) | 4.1 | Cheminformatics; broader computational chemistry audience |

**Key claims to support:**
- First system to generate ICH M4 CTD §2.6.1–§2.6.5 from computational pipelines
  without pre-existing wet-lab study reports
- hERG AUROC 0.9635 on internal holdout (vs Chemprop baseline 0.870)
- PBPK within-2-fold 73.3% (meets EMA ≥67% criterion; within OSP approved range 50–100%)
- 37/37 gold standard assertions across 9 reference compounds (Redfern 2003 / DILIrank /
  Hansen 2009 / TDC)
- Hybrid regulatory auditor (regex + LLM judge) eliminates false-negative keyword matching

**Closest prior art acknowledged:**  
AutoIND (Eser et al., arXiv:2509.09738): covers §2.6.2/4/6 from wet-lab reports.
Distinguishing factors: (1) computational-first data pipeline; (2) §2.6.1 coverage;
(3) multi-region compliance (FDA/EMA/NMPA/PMDA); (4) peer-reviewed gold standard.

---

### Preprint

Post to **bioRxiv** simultaneously with journal submission.
- bioRxiv has ~80,000 daily readers; pharma/biotech community reads it actively
- Allows citation before peer review (important for early BD conversations)
- URL to include in all marketing materials from day one of submission

---

### Blog Post

**Post after paper accepted or bioRxiv preprint goes live.**

**Target platforms:**
- LinkedIn (primary — pharma/biotech audience)
- Towards Data Science (technical credibility with data science/ML community)
- Company blog (SEO + permanent reference)

**Narrative hook:** "We ran ICH S7B — the guideline that formally validated in silico
hERG for the first time (November 2024) — and benchmarked our model against the
TDC leaderboard. Here's what it means for IND writing."

**Contents:**
1. The problem: 40–80 hours to format computational predictions into regulatory documents
2. What we built: computational-first CTD §2.6 generation (2-minute demo gif)
3. The numbers: benchmarks (hERG 0.9635, PBPK 73.3%, 37/37 gold standard)
4. ICH S7B(R1) timing: why this matters now
5. Call to action: "Try it with your compound — link to BioMate"

**Demo video:** 2-minute screen recording showing:
- Enter SMILES list
- Submit to AWS Batch (predict_admet_properties)
- Review outputs in campaign workspace
- Click "Generate IND Package"
- Show generated §2.6.1–§2.6.5 document with ADMET-AI values, PBPK table, reactive
  metabolite screen, tabulated PK/safety summary
- Show eSig workflow and frozen document download
- Total time shown: under 5 minutes from SMILES to signed DOCX

---

### Conference

**Target events (2026):**

| Event | Date | Audience | Format |
|-------|------|---------|--------|
| ACS National Meeting (Fall 2026) | August 2026 | Medicinal chemists, ADMET scientists | Poster or talk |
| SLAS Europe 2026 | June 2026 | Drug discovery, automation | Demo booth |
| DDT 2026 symposium | TBD | Regulatory pharmacology | Oral presentation |
| DIA Annual Meeting 2026 | June 2026 | Regulatory affairs professionals | Poster |

DIA (Drug Information Association) annual meeting is particularly valuable — the
audience is FDA reviewers, regulatory affairs directors, and IND specialists.
A poster at DIA showing real FDA-guideline-aligned output would generate more
qualified leads than any digital marketing campaign.

---

### Sales and BD

**Target customer profiles:**

1. **Seed/Series A biotech (5–20 employees)** — No regulatory staff; spending $50–150K on
   contract CROs for computational DMPK packages. BioMate replaces most of this spend.
   Pitch: "Your contract CRO charges you $80K for what BioMate does in 4 hours."

2. **Mid-size pharma computational group (20–200 employees)** — Has internal scientists
   but process is manual. BioMate becomes their IND writing tool.
   Pitch: "Your computational chemist spends 3 days formatting reports. BioMate makes it
   1 day — and the document is audit-ready on day one."

3. **Computational CRO (BioAscent, WuXi AppTec computational, Evotec computational)**  
   White-label BioMate as their regulatory output layer.
   Pitch: "Your scientists produce the data. BioMate produces the regulatory-formatted
   deliverable. You differentiate from CROs that only deliver raw numbers."

**Outreach approach:**
- LinkedIn DM to CSOs/VP Discovery at seed-stage biotechs (find via Crunchbase)
- Cold email to head of computational pharmacology at 50 mid-size pharma
- Partner conversation with WuXi AppTec (already in our CRO workspace)
- Conference lead capture at SLAS/DIA

---

## 5. Immediate Action Items

In priority order for the next 4 weeks:

| # | Task | Owner | Effort | Impact |
|---|------|-------|--------|--------|
| 1 | Finish manuscript (add §2.6.4/§2.6.5 results, freeze/hash section) | BioMate | 1 week | HIGH |
| 2 | Submit to bioRxiv and Journal of Cheminformatics | BioMate | 1 day | HIGH |
| 3 | Add reviewer credentials to eSig record | Engineering | 2 days | HIGH (legal) |
| 4 | §2.6.6 toxicology tabulated summary | Engineering | 2 weeks | HIGH |
| 5 | PK-Sim integration (mechanistic PBPK) | Engineering | 4 weeks | MEDIUM |
| 6 | Record 2-minute demo video | BioMate | 1 day | HIGH (marketing) |
| 7 | Identify 3 seed-stage biotech pilot candidates | BD | 1 week | HIGH |
| 8 | Blog post draft (after bioRxiv submission) | BioMate | 2 days | MEDIUM |
| 9 | DIA Annual Meeting abstract submission | BioMate | 1 day | MEDIUM |
| 10 | eCTD XML conversion pipeline | Engineering | 3 weeks | MEDIUM (NDA stage) |

---

## 6. Key Decisions Required

1. **Pricing model:** Per-campaign SaaS vs platform license? Recommend platform license
   for enterprise; per-campaign for early-stage with try-before-buy pilot offer.

2. **Reviewer model:** Do we offer the contract RA review service add-on, or require
   customers to have their own reviewer? Recommend: require own reviewer at launch;
   add service tier in 6 months after demand signal.

3. **Open-source vs proprietary:** Should the regulatory KB + auditor be open-sourced
   (builds community credibility) while the IND assembly pipeline stays proprietary?
   Recommend: open-source regulatory_knowledge.yaml and auditor checks (benefits
   the whole industry; impossible to keep secret); keep ADMET-AI integration + batch
   orchestration + campaign DB proprietary.

4. **Patent:** The §2.6.1–§2.6.5 assembly pipeline from computational data is likely
   patentable as a novel method. File provisional before publishing if commercially
   important. Consult IP counsel.

---

## 7. Why BioMate — Not Competitors?

The honest answer: **no existing product connects computational pipeline outputs to
CTD-formatted regulatory documents with an audit trail.** BioMate fills a gap, not
a contested space.

### Current customer workflow (what we replace)

```
Computational scientist runs Schrödinger/MOE/Pipeline Pilot
    → exports ADMET numbers to Excel
    → sends Excel + PBPK simulation report to regulatory writer
    → regulatory writer spends 3–6 weeks writing §2.6 in Word
    → multiple rounds of internal review + formatting
    → final document emailed to sponsor → manual version control
    
Total: $30–150K, 4–8 weeks, no audit trail
```

```
With BioMate:
SMILES list → AWS Batch (ADMET-AI) → Campaign workspace
    → "Generate IND Package" (minutes)
    → Review draft → Approve & Sign (eSig)
    → Download frozen DOCX with SHA-256 hash + version metadata
    
Total: <$5K, <1 week, 21 CFR Part 11 audit trail
```

### Specific competitive comparison

**vs. Certara CoAuthor:**  
CoAuthor formats structured tables (that you must already have) into narrative text.
You still have to run Simcyp yourself, export the tables, and hand them to CoAuthor.
No ADMET integration, no audit trail, no eSig. It's a Word plugin with NLG — not
an end-to-end pipeline. BioMate includes the ADMET-AI + PBPK step that CoAuthor requires
as a prerequisite.

**vs. Schrödinger / ADMET-AI:**  
These tools produce predictions but stop there. You get a spreadsheet or visualization.
They have no regulatory document generation, no ICH M4 CTD formatting, no audit trail.
BioMate sits *above* them in the stack — we could theoretically accept their outputs
as inputs (via the wet-lab ingester or pk_summary upload).

**vs. AutoIND (arXiv:2509.09738):**  
AutoIND uses LLMs to summarize *completed* preclinical study reports into §2.6.2/4/6.
If you have finished GLP studies, AutoIND can draft the narratives. But it does not:
(a) run any ADMET predictions; (b) cover §2.6.1 computational pharmacology; (c) work
from a computational pipeline without wet-lab reports; (d) have a regulatory auditor;
(e) have multi-region compliance; (f) have 21 CFR Part 11 audit trail. And it is a
preprint — no peer review, no production deployment disclosed.

**vs. Yseop / Narrativa / Assyro:**  
These target clinical regulatory documents (Module 2.7 clinical overview, CSR narratives).
They work from clinical trial data (CDISC datasets). They do not address nonclinical
computational data (§2.6.1–§2.6.5) at all. Different section, different data type,
different customer workflow.

**vs. In-house regulatory team:**  
The most common "competitor" is doing it manually. The regulatory writer is either
an FTE ($150–250K fully loaded annual cost) or a contractor ($100–200/hour).
A typical IND nonclinical package takes 40–80 hours = $4,000–16,000 in labour for
one §2.6 iteration. Multiply by 5–10 iterations per compound during development.
BioMate's iteration cycle is minutes, not weeks.

### The sustainable moat

1. **Data moat:** The ADMET training database (13,719 compounds, 18,602 measurements,
   guideline-tagged) and OSP skills DB (6 EMA-accepted qualification reports, 194 skills)
   improve the system's accuracy in ways competitors cannot easily replicate.

2. **Regulatory KB moat:** The versioned, multi-region regulatory knowledge base
   (FDA/EMA/NMPA/PMDA) with watch items and auto-updating thresholds requires ongoing
   regulatory expertise to maintain. This is not a one-time build.

3. **Gold standard moat:** 37/37 assertions against published reference compounds with
   quantitative benchmarks (TDC, OSP) provides auditable evidence of accuracy that
   competitors don't have and can't easily produce.

4. **Audit trail moat:** 21 CFR Part 11 SHA-256 hash chain + TOTP eSig + document
   freeze is a genuine compliance capability, not a checkbox. Once a customer builds
   their IND filing workflow around BioMate's audit trail, switching costs are very high.
