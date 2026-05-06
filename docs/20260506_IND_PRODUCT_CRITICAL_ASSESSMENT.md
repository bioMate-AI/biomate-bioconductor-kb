# IND Report — Critical Product Assessment

**Date:** 2026-05-06  
**Purpose:** Honest answer to: why aren't others doing this, and what does it take to be a real product?

---

## The Honest Answer: Why Others Aren't Doing It This Way

The existing strategy doc (20260501) argues this space is uncrowded and we have first-mover advantage. That's partially true but misses the core structural reason nobody has built this:

**The document is not the bottleneck. The data is.**

A regulatory writer spends 40–80 hours writing §2.6. But they spend that time because they are translating 2,000 pages of GLP study reports into 60 pages of prose. The bottleneck is not the writing — it is having the study data in the first place, which takes 2–4 years and $2M–$10M. Automating the writing step while the data collection step still takes years does not meaningfully change a drug developer's timeline or budget. This is why nobody built it: it solves the wrong problem.

BioMate's specific angle — generate §2.6 from in silico predictions rather than study reports — sidesteps this, but creates a different problem: the output is not what regulators need for an IND. In silico predictions are acceptable context for a pre-IND meeting; they are not acceptable evidence for a clinical hold-free Phase I IND. The document we generate today is a planning document, not a submission document. A regulatory writer would need to redo it from scratch once the GLP studies complete.

So in its current form: **not a product a pharma company would pay $100K for.** A tool they might pay $5K–$15K for as a planning aid.

---

## What Needs to Be True for This to Be a Real Product

### Condition 1: Accept real study data as input

The product cannot be limited to BioMate's own computational outputs. A regulatory writer's job is to summarize GLP study reports — PDFs from CROs. If BioMate can accept an uploaded PDF of a GLP in vitro genotoxicity study and extract the key results (test system, concentrations tested, positive/negative outcome, study director, date), then write the §2.6.3.3 genotoxicity subsection from that data, the product becomes useful for the actual Phase I IND preparation workflow.

This is a completely different technical problem from what we have built. It requires:
- PDF extraction from CRO-formatted study reports (not standardized — every CRO has a different template)
- Structured data extraction (NOAEL, species, dose groups, findings)
- Validation that extracted values are plausible and internally consistent
- Traceability: every sentence in §2.6 must be traceable to a specific page/table in Module 4

Without this, the output is a computational sandbox toy, not a regulatory writing tool.

### Condition 2: The full §2.6 scope, not a subset

We currently generate §2.6.1 (pharmacology), §2.6.2 (PK), and §2.6.3.3/3.7 (genotox/cardiac). A real IND nonclinical package requires:

| Section | Currently | Required |
|---------|-----------|----------|
| §2.4 Nonclinical Overview | ❌ Missing | Required in every IND |
| §2.6.1 Pharmacology Written Summary | ✅ | ✓ |
| §2.6.2 PK Written Summary | ✅ | ✓ |
| §2.6.3.1 Single-dose toxicity | ❌ Missing | Required if in vivo studies done |
| §2.6.3.2 Repeat-dose toxicity | ❌ Missing | Required for Phase I |
| §2.6.3.3 Genotoxicity | ✅ Partial | ✓ |
| §2.6.3.4 Carcinogenicity | ❌ Missing | Required for chronic use drugs |
| §2.6.3.5 Reproductive toxicity | ❌ Missing | Required for drugs used in WOCBP |
| §2.6.4 Written Summary of Repro Tox | ❌ Missing | Conditional |
| §2.6.5 Ecotoxicology | ❌ Missing | Required (EU mandatory, FDA recommended) |

The sections we're missing are the high-value ones. §2.6.3.2 (repeat-dose tox) and §2.4 (nonclinical overview) are what regulatory writers spend most time on. Without them, a sponsor still needs a regulatory writer.

### Condition 3: A regulatory writer workflow, not a download button

The current product produces a DOCX and a sign-button. Real regulatory writing is:

1. Generate draft
2. Regulatory writer annotates (this number is wrong / this section needs a study cross-reference / this interpretation is too strong)
3. Writer requests specific data (what was the NOAEL from the 28-day study?)
4. Revise draft
5. Medical monitor or CMO reviews
6. Legal/regulatory review for IND cover letter alignment
7. Sign and submit

BioMate has steps 1 and 5 (draft and sign). Steps 2–4 require a tracked-changes document editing interface and step 6 requires integration with what the sponsor's legal/regulatory team is doing. Without this workflow, a regulatory writer will generate the BioMate draft once and then work entirely in Word, which means BioMate gets none of the credit for the final document and no lock-in.

### Condition 4: A go-to-market that reaches regulatory writers, not data scientists

The people who buy and use regulatory writing tools are Regulatory Affairs (RA) directors and senior regulatory scientists. They are not the people using BioMate's AI chat interface. They:
- Use Microsoft Word every day
- Are risk-averse about their submissions
- Have existing relationships with CROs
- Are evaluated on whether their submissions get approved, not on how fast they were written

The current BioMate product — an AI chat that suggests workflows — will never reach them organically. To sell to them, you need:
- A standalone product at a distinct URL (not the BioMate chat)
- SOC 2 Type II compliance (they will ask)
- 21 CFR Part 11 validation documentation (not just the feature — a validation package they can show an FDA inspector)
- Case studies with actual IND submissions where BioMate draft was used
- Either a direct sales motion (in-person at DIA, RAPS conferences) or a CRO partnership

---

## The Actual Path to a Real Product

### Stage 1 — Make the computational tool genuinely useful (3–6 months)

Complete what we have:
- §2.4 Nonclinical Overview (high priority — requested in every pre-IND meeting)
- §2.6.3.1–§2.6.3.2 scaffolds (even as "awaiting GLP data" structured placeholders)
- Better output length (currently 250–300w per section; target 800–2,000w)
- Tables: ICH M4 requires tabulated summaries alongside written summaries. We have no tables.

Target: **pre-IND meeting package** at academic spinouts and seed-stage biotechs. Price $10K–$20K. This is a real purchase they make — consultants charge $25K–$50K for this service.

### Stage 2 — Accept real study data (6–18 months)

Build the PDF ingestion pipeline for GLP study reports. This is hard:
- 5–10 different CRO templates (Charles River, Covance, Eurofins, etc.)
- Extract: species, dose groups, NOAEL, findings, study director, dates, GLP statement
- Validation and cross-reference table generation
- Map extracted data → specific §2.6 subsections

With this, the product can generate a **draft Phase I IND §2.6 package** that a regulatory writer reviews and approves. The regulatory writer's job shifts from writing to reviewing. Time savings: 60–80% of writing time.

Price: $50K–$150K per IND package (still cheaper than the $150K–$500K CRO manual writing cost). Or $200K/year SaaS for companies with multiple compounds.

### Stage 3 — Regulatory writer co-pilot workflow (12–24 months)

Build the tracked-changes review interface:
- Inline comments and annotations in the generated document
- Cross-reference checker (sentence → Module 4 page number)
- Real-time audit trail of human edits
- Section completeness checker against ICH M4S(R2) checklist
- Multi-user review workflow (computational scientist → regulatory writer → CMO)

This is when BioMate becomes a platform that regulatory writers want to use every day. Lock-in is strong once the document history and audit trail are in the system.

---

## What the Competitors Are Actually Building

The reason nobody has built the full product yet:

1. **Certara** is too busy defending Simcyp ($300M+ PBPK market). They are building AI on top of their existing software but not trying to replace regulatory writers.

2. **AutoIND (arXiv 2025)** solves the document-from-wet-lab-data problem but requires completed study reports and doesn't do computational-first.

3. **AI regulatory writing startups** (Intelligencia, Trials.ai) focus on clinical documents (protocols, CSRs) where the data structure is more predictable (CDISC standards). Nonclinical has no equivalent standard for raw study data.

4. **The real blocker** for all of them: GLP study reports are proprietary documents not available for training. You can't build a training dataset from real CRO reports without partnerships. The training data problem is the moat, not the model.

BioMate's training data approach (EMA EPARs + openFDA) is directionally right — EPARs are the only public CTD-formatted nonclinical prose that exists. The limitation is that EPARs cover approved drugs with complete study packages, not early-stage computational IND candidates.

---

## The Real Product Thesis

**BioMate is not an IND generator. It is a regulatory writing infrastructure layer.**

The product is: a system that accepts structured nonclinical data in any form (computational predictions, CRO PDF reports, in-house assay CSVs), maps it to ICH M4 CTD structure, generates first-draft prose to ICH regulatory standards, and provides a tracked human-review workflow with 21 CFR Part 11 audit trail.

The LLM is one component. The data extraction, the ICH M4 schema enforcement, the review workflow, and the audit trail are the others. No single competitor has all four. Building all four is the 18-month plan.

**First revenue:** Pre-IND meeting packages at $10K–$20K.  
**Series A product:** GLP data ingestion + full §2.6 at $150K/year.  
**Defensible moat:** The fine-tuned regulatory LLM (v2 today, DPO-aligned v3) trained on EMA EPAR data — this is data nobody else has turned into a model specifically for this task.
