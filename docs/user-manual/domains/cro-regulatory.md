# CRO & regulatory (cross-domain)

> One-line promise: after this page you know how BioMate turns finished analyses into a signable,
> audit-ready regulatory dossier — and exactly where the honest edges are. For drug-discovery &
> regulatory scientists.

<!-- Cross-domain chapter; the IND assembly + 21 CFR 11 claims are code-verified in the flagship
     chapter's ledger (docs/user-manual/domains/drug-discovery-ind.md). This chapter reuses those
     verified rows and does not re-assert anything beyond them. -->

## What this is for
Regulatory work is cross-domain: it *consumes* the outputs of other analyses (ADMET, PBPK, dose-finding)
and assembles them into a submission section with a defensible audit trail. In BioMate that is the
**IND §2.6** assembly path, covered end-to-end in the flagship chapter —
[Drug discovery → IND](drug-discovery-ind.md). This page is the regulatory-lens summary.

## Use cases
| Goal | How | Inputs | Output (artifact) | Lane |
|---|---|---|---|---|
| Assemble the IND §2.6 nonclinical summary | IND workspace (`/ind-report`) → Document step | completed ADMET + PBPK (+ dose-finding) runs in the project | §2.6.1/§2.6.2/§2.6.4… as a DOCX + Markdown | Cloud (assembler) |
| Sign & version a section with an audit trail | e-signature + immutable superseded versions | the assembled document | signed DOCX + audit-trail PDF (SHA-256 hash chain) | Instant |
| Attach measured (wet-lab) data over predictions | attachment upload on the IND workspace | measured values | updated section with measured overriding predicted | Instant |

## How to ask
Reach it from the ADMET chat result ("Generate IND") or open `/ind-report` directly. See the flagship
chapter for the full 5-step workspace (Setup · ADMET · PBPK · Leads · Document).

## Tools & workflows behind this
- **IND section assembler** — generates §2.6.1.1–§2.6.1.6, §2.6.2, §2.6.4 (tabulated), §2.6.5–§2.6.7 as
  Markdown → DOCX via pandoc. *(verified: `ind_assembly.py` — see the [IND chapter ledger](drug-discovery-ind.md).)*
- **21 CFR 11 audit trail** — SHA-256 hash chain with `prev_hash` links; records user/action/timestamp;
  immutable superseded versions; e-signature.
- **Export** — DOCX / Markdown / audit-trail PDF endpoints.

## QC gates & how to read them
Regulatory assembly inherits the upstream domains' gates — the ADMET hERG/DILI/Ames/Ro5 gates and the
PBPK R² gate (see [Appendix C](../appendix/C-qc-gate-reference.md)). The §2.6 narrative uses only
extracted values from those runs — no invented numbers.

## A worked example
See the flagship [Drug discovery → IND](drug-discovery-ind.md) worked example: ADMET screen → auto-loop
remediation → PBPK human-dose projection → assemble §2.6 → sign. That chapter is the canonical, fully
code-verified walk-through; this page is its regulatory summary.

## Outputs & visualization
The assembled DOCX/Markdown open as a report; the audit trail exports as a PDF. Underlying run outputs
open in the in-app viewers ([I.8](../modules/I08-outputs-viewers-interactive.md)); the whole record is
downloadable ([I.9](../modules/I09-reports-and-reproducibility.md)).

## Pitfalls & tips
> **Pitfall — dev e-signature is not production MFA.** On dev the TOTP e-signature accepts any 6 digits;
> real enrolled MFA is roadmap. Don't treat a dev signature as a controlled one.

> **Pitfall — GLP sections need GLP data.** Toxicology §2.6.3 (single/repeat-dose, genotox in-vivo)
> renders "Awaiting GLP data" placeholders until you attach wet-lab results — it does not fabricate tox.

## What's not covered (→ [Appendix E](../appendix/E-coverage-and-roadmap.md))
- **No "Submit to FDA"** — no submission endpoint (the button is disabled).
- **Non-FDA regions** — section rendering returns `not_implemented`.
- **NDA-fetch** (NDA → PK params) is disabled ("coming soon").
- **No manuscript "Stage 6"** — the flow ends at the DOCX + versioned edits; there is no downstream
  manuscript assembler.
- The PBPK reference set is 30 marketed drugs (smaller than full-regulatory sets).

---
_Verification: all regulatory claims here are the code-verified rows of the flagship
`domains/drug-discovery-ind.md` (IND assembler, 21 CFR 11 audit trail, DOCX/PDF export, the roadmap
gaps). This chapter adds no unverified claims._
