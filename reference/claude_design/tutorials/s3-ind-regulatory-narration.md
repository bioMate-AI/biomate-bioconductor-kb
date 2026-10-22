# S3 — IND nonclinical overview (CTD §2.6.1) walkthrough narration (EN)

Track: Regulatory document assembly. One block per timeline beat (10 scenes).
For edge-tts: acronyms are spelled where that reads more clearly aloud
(I-N-D, C-T-D, I-C-H, F-D-A, E-M-A, N-M-P-A, P-M-D-A, D-O-C-X, P-B-P-K are
spelled; ADMET is spoken as the word "ad-met"; 21 C-F-R Part 11 and
S-H-A-256 are spelled). Every claim traces to a live-verified fact — no
invented numbers.

---

## Step 1 — Title · from finished runs to CTD §2.6.1

The science is done. You have screened the molecule for ad-met properties, run a P-B-P-K simulation, and made a lead-selection call. Now that evidence has to become a regulatory document — the I-C-H Common Technical Document, Module 2.6, whose flagship is the C-T-D section 2.6.1, the Nonclinical Overview. BioMate's I-N-D Report assembles that document section by section, grounding each narrative in the campaign's real run outputs, and then runs a regulatory audit over the result. In this walkthrough we build the idea from the ground up, then show the feature producing actual C-T-D 2.6.1 text. And we will be exact about what it is — a draft for human review, never an approval.

---

## Step 2 — The problem · slow, multi-region, error-prone

Here is the problem this solves. The science is finished; the bottleneck is the document. A nonclinical overview must summarise every study faithfully, in a rigid structure, for several regulators at once — and every number in the prose must match the study it came from. Done by hand, it is weeks of careful transcription, repeated for each amendment as the data changes. It is multi-region: F-D-A, E-M-A, N-M-P-A and P-M-D-A each expect their own acceptance criteria and framing. And it is error-prone — when prose is typed separately from the runs, a single value can go stale, and an overview whose figures no longer match the data is a finding waiting to happen.

---

## Step 3 — The ideas you need first

Four ideas, and the rest of the document follows. First, the C-T-D: the I-C-H M4 Common Technical Document organises a submission into modules, and Module 2.6 holds the nonclinical written summaries. Second, the flagship — section 2.6.1, the Nonclinical Overview for pharmacology, with subsections 2.6.1.1 brief summary, 2.6.1.2 primary pharmacodynamics, 2.6.1.3 safety pharmacology, and 2.6.1.4 through 2.6.1.6; alongside it, 2.6.2 the written summary and 2.6.3 the tabulated summary. Third, the four regions — F-D-A, E-M-A, N-M-P-A, P-M-D-A — each with its own acceptance criteria. Fourth, and most important: the narrative is not free-written. It integrates the campaign's ad-met, P-B-P-K and lead-selection run outputs, so every statement traces back to a real result.

---

## Step 4 — In BioMate · from runs to section 2.6

Here is how that happens in the product. The I-N-D Report lives at the route slash-ind-report. You open it, pick a campaign assembled from ad-met, P-B-P-K and lead-selection runs, and ask BioMate to generate the Common Technical Document section 2.6. Behind the button, that fires a single call — post to the drug-discovery campaign's ind-assembly endpoint — which returns the ordered section list: 2.4, then 2.6.1.1 through 2.6.1.6, then 2.6.2 and 2.6.3.1. You set the target region, so the acceptance criteria and bridging notes match the dossier. And every section is written against the campaign's real run outputs, not composed from scratch. What you see on screen is the live product assembling section 2.6 from your runs.

---

## Step 5 — Inputs · what feeds it

What feeds the assembly? Because it is grounded, the inputs are the real run outputs together with the dossier facts a regulator expects, gathered into one assembly request. The run evidence comes first: the P-K summary is read from a predict-ad-met or P-B-P-K run, and the lead-selection decision supplies the primary-pharmacodynamics story — this is the grounding the prose is written against. Then the submission facts: molecule name, sponsor, indication and target name identify the program, and the region selects the agency framing. Finally the compliance context: the G-L-P facility and its recognition, an ethnic-bridging note for N-M-P-A and P-M-D-A, and any wet-lab data. One request object carries all of it into the narrative.

---

## Step 6 — The method · section by section, grounded, regenerable

Now the method, and it is deliberately not one block of text. BioMate walks the C-T-D section 2.6 structure — 2.4, then 2.6.1.1 through 2.6.1.6, then 2.6.2 and 2.6.3.1 — and writes each subsection as its own narrative. For each one, the prose is grounded in the integrated ad-met, P-B-P-K and lead-selection outputs, so the pharmacodynamics, safety-pharmacology and P-K statements all trace to real results. And because each section stands on its own, any one of them can be regenerated independently — you can refine the safety-pharmacology subsection without disturbing the primary-pharmacodynamics one. The output is generated as Markdown, ready to export to D-O-C-X, and the document is versioned: version one signed, then version two.

---

## Step 7 — The output · real CTD 2.6.1 text

This is what the assembly produces: readable Common Technical Document section 2.6.1 prose, subsection by subsection — the brief summary, the primary pharmacodynamics, the safety pharmacology — each appearing as finished regulatory text. You export it as a Word file: a get call to the ind-assembly download endpoint with format D-O-C-X renders the document through pandoc, named by campaign and C-T-D section. Each version is versioned and electronically signed, and the file carries a S-H-A-256 document hash so its integrity can be checked. There is a freeze guard: once a document is signed, re-generation returns H-T-T-P 409 — a supersede call makes a new version rather than overwriting the signed one. A signed document is a fixed record.

---

## Step 8 — The regulatory audit gate

Before the draft moves on, a built-in regulatory auditor runs over it and grades every finding by severity: CRITICAL, MAJOR, MINOR, INFO. CRITICAL and MAJOR demand action; MINOR and INFO are advisory. And this gate has teeth — a CRITICAL or failed-qualification finding blocks the downstream actions, C-R-O export and I-N-D assembly, until it is resolved. Take a worked example: if a P-B-P-K model fails the E-M-A C-max within-two-fold criterion — the expectation per C-H-M-P guidance — the auditor inserts a section 2.6.2 model-limitation statement and halts. The limitation is stated in the document, not hidden. The gate is a hard stop, not a silent rewrite; it never quietly passes a failed check.

---

## Step 9 — Honest limits

Now the honest limits, reproduced faithfully from the product's own disclaimer. Every section this feature produces is a BioMate-generated draft that must not be submitted without human regulatory-affairs review and a 21 C-F-R Part 11 electronic signature. The tool assembles; a qualified person decides. The automated audit is a machine consistency check — it is not a regulatory approval or guarantee. Clearing the gate means the document is internally consistent, not that an agency will accept it. And where a criterion is not met — a P-B-P-K model outside within-two-fold, a missing qualification — the document states the limitation rather than hiding it, and the downstream action halts until it is addressed. This is an assembly aid behind a human signature, not a self-certifying submission.

---

## Step 10 — Closing · at a glance

So, the I-N-D nonclinical overview at a glance: finished runs in, a grounded Common Technical Document section 2.6.1 draft out, with a regulatory audit in between. From the ind-report route, BioMate assembles Module 2.6 section by section, grounding each narrative in your ad-met, P-B-P-K and lead-selection runs; it exports a versioned, electronically signed, S-H-A-256-hashed D-O-C-X; and it runs a severity-graded audit that halts on a CRITICAL finding. It is built to the I-C-H M4 standard and frames the dossier for F-D-A, E-M-A, N-M-P-A or P-M-D-A. The value is turning weeks of transcription into minutes of grounded assembly — every section traced to its source, every limitation stated in the open. And the draft always waits on human regulatory review and a 21 C-F-R Part 11 signature before anything is filed.

---
