# Citation Correction — Aronov 2008 J Med Chem (Fabricated) → Redfern 2003 + Bowes 2012 + Waring & Johnstone 2007 + Aronov 2008 Curr Opin

Date: 2026-05-28
Trigger: `research_repos/citation_reconciliation_20260527.md` (Agent R) — the cited
"Aronov AM 2008. *J Med Chem* 51:6632-6641, DOI 10.1021/jm800467u" does not exist
on PubMed.

## What was wrong

For ~6 months BioMate's QC evidence layer attributed the **10 µM hERG IC50
discovery-stage safety cutoff** and the **logP/IC50 regression** used in the
ADMET auto-loop to a fabricated paper:

> Aronov AM 2008. *J Med Chem* 51:6632-6641. DOI: 10.1021/jm800467u

This DOI/journal/page combination does not resolve. A related but distinct
DOI (`10.1021/jm0707476`) was also in use in `knowledge_base.py`.

## What's correct

The 10 µM hERG cutoff is the operational implication of two well-established
papers, and the property-tuning framework + quantitative logP/IC50 model
have their own real sources:

| Claim | Correct citation |
|---|---|
| 10 µM hERG cutoff (regulatory anchor) | **Redfern P et al.** *Cardiovasc Res* 2003;58(1):32-45. DOI: 10.1016/S0008-6363(02)00846-5. (30× safety margin over free Cmax; at typical 0.3 µM free Cmax this → 10 µM IC50.) |
| 10 µM cross-pharma consensus | **Bowes J et al.** *Nat Rev Drug Discov* 2012;11(12):909-922. DOI: 10.1038/nrd3845. |
| Property-tuning framework (logP/MW reduction) | **Aronov AM.** "Tuning out of hERG." *Curr Opin Drug Discov Devel* 2008;11(1):128-140. PMID: 18175275. (This is the real Aronov 2008 hERG paper.) |
| Quantitative logP↔IC50 regression | **Waring MJ & Johnstone C.** *Bioorg Med Chem Lett* 2007;17(6):1759-1764. DOI: 10.1016/j.bmcl.2006.12.061. |

## Files changed

1. **`backend/config/qc_evidence.yaml`** — `admet.admet_herg_ic50` entry: replaced
   `paper_ref` + `paper_doi`; rewrote `paper_supports` (now anchored on Redfern
   2003 30× margin); embedded Bowes 2012 in `rule_text` and Waring & Johnstone
   2007 + Aronov 2008 *Curr Opin* in `finding`.

2. **`backend/experiments/admet_autoloop/knowledge_base.py`** — PRIMARY SOURCES
   docstring header rewritten with all four real citations. The `herg_ic50`
   knowledge list expanded from 2 entries (old Aronov + ICH S7B) to 3 entries:
   - GOLD: Redfern 2003 (10 µM cutoff anchor)
   - GOLD: Waring & Johnstone 2007 (logP regression for the remediation math)
   - SILVER: Aronov 2008 *Curr Opin* (property-tuning framework — real paper,
     different journal than the fabricated cite)
   - The ICH S7B SILVER entry was preserved separately (unchanged) in the file.

3. **`frontend/client/src/data/qc-evidence.ts`** — patched once successfully,
   then reverted by parallel-session protection, then patched again, then
   reverted **a second time**. Per CLAUDE.md anti-collision protocol
   ("if reverted twice, stop and report") I did NOT re-apply a third time.
   **Manual step required:** regenerate this file from `qc_evidence.yaml`
   when no parallel session is touching it. Suggested command:
   ```bash
   python3 -c "
   import yaml, json
   data = yaml.safe_load(open('backend/config/qc_evidence.yaml'))
   # emit TS — match existing format in qc-evidence.ts
   "
   ```
   Or simply re-apply the targeted Edit to the `admet.admet_herg_ic50` block.

4. **`research_repos/flagship_paper/manuscript/MANUSCRIPT_DRAFT.md`** — three
   in-body changes:
   - §1 Intro: "Aronov 2008 for hERG inhibition" → "Redfern 2003 / Bowes 2012 for
     the 10 µM hERG safety margin"
   - §3 (Methods worked example): evidence-payload citation updated to Redfern
     2003 + DOI + Bowes 2012 cross-confirmation
   - §3 (Provenance grade discussion): GOLD example text rewritten to reflect
     Redfern 30× margin rule deriving the 10 µM threshold
   - Reference 4 fully rewritten to list all four correct citations
   (~+250 words net.)

5. **`research_repos/autoloop_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md`** —
   four in-body changes:
   - §Intro (line 51): hERG knowledge-base anchor replaced; added refs 10, 11, 12
   - §Architecture (line 65): worked example rewritten to attribute the
     remediation regression to Waring & Johnstone 2007 rather than fabricated
     Aronov; escalation framework attributed to real Aronov 2008 *Curr Opin*
   - §Provenance grades (line 73): SILVER example rewritten (Waring & Johnstone
     mechanism vs Redfern/Bowes regulatory cutoff)
   - §Per-domain wiring (line 83): citation list for `_fix_herg` rewritten
   - Reference 4 rewritten; added references 10 (Bowes), 11 (Waring & Johnstone),
     12 (Aronov *Curr Opin*).
   (~+180 words net.)

6. **`research_repos/cryo_em_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md`** —
   no occurrences of "Aronov"; no change required.

7. **`backend/tests/test_qc_evidence.py::test_evidence_for_admet_herg`** —
   assertion updated from `"Aronov" in paper_ref` → `"Redfern" in paper_ref`;
   docstring also updated.

## Test results

```
backend/tests/test_qc_evidence.py ........... [11 passed]
backend/tests/test_qc_gate_reader.py .......................................
                                     ......................................  [70 passed]
backend/experiments/admet_autoloop/tests/test_admet_loop.py ...........  [24 passed]
backend/experiments/admet_autoloop/tests/test_admet_ux_loop.py .........  [12 passed]
======================= 117 passed, 2 warnings in 5.36s ========================
```

All 117 tests green.

## Parallel-session collisions observed

| File | Reverts before stabilising |
|---|---|
| `backend/config/qc_evidence.yaml` | 1 (re-applied once; stable) |
| `backend/experiments/admet_autoloop/knowledge_base.py` | 1 (re-applied once; stable) |
| `frontend/client/src/data/qc-evidence.ts` | **2 (NOT re-applied — manual regen needed)** |

## Confirmation

BioMate now claims the 10 µM hERG IC50 discovery-stage safety cutoff via
**Redfern 2003 (*Cardiovasc Res*)** as the primary regulatory source for the
30× safety margin, cross-confirmed by **Bowes 2012 (*Nat Rev Drug Discov*)** as
the cross-pharma industry consensus. The logP-reduction remediation rationale
is attributed to **Waring & Johnstone 2007 (*Bioorg Med Chem Lett*)**, and the
secondary MW/pKa property-tuning escalation cites the real **Aronov 2008
(*Curr Opin Drug Discov Devel*)** "Tuning out of hERG." The fabricated "Aronov
2008 *J Med Chem* 51:6632-6641 DOI 10.1021/jm800467u" citation has been
removed from the YAML, Python knowledge base, two manuscripts, and one test.

## Process lesson — mandatory PubMed verification

Going forward, **every new `paper_ref` added to `qc_evidence.yaml`,
`knowledge_base.py`, or a manuscript reference list MUST be PubMed-verified
before commit.** Suggested workflow:

1. Look up the DOI on `https://doi.org/<DOI>`. It must resolve to the cited
   journal + volume + page.
2. Look up the title on PubMed. The result page must list the same
   authors / journal / year / volume / pages as in the citation.
3. If either lookup fails, do not commit — the citation is fabricated or
   garbled and must be replaced with a real one.

A short helper script could automate this (DOI HEAD → resolve, NCBI E-utilities
`esearch` for the title) — recommend adding it under `backend/scripts/`
as `verify_citations.py` in a follow-up.

## Remaining manual step

Re-apply this single Edit to `frontend/client/src/data/qc-evidence.ts` when
no parallel session is touching it:

```
"paper_ref": "Aronov AM 2008. J Med Chem 51:6632-6641",
"paper_doi": "10.1021/jm800467u",
"provenance": "GOLD",
"paper_supports": "Aronov 2008 establishes hERG IC50 ≤ 10 µM as the safety cutoff for cardiac liability in early-stage drug discovery.\n",
"rule_text": "BioMate halts if hERG IC50 ≤ 10 µM (admet_standard profile).\n",
"finding": "Remediation: tighten upstream logP and pKa filters; hERG liability correlates with basic amines and high lipophilicity.\n"
```
becomes
```
"paper_ref": "Redfern P et al. Cardiovasc Res 2003; 58(1):32-45",
"paper_doi": "10.1016/S0008-6363(02)00846-5",
"provenance": "GOLD",
"paper_supports": "Redfern 2003 establishes the 30× safety margin between hERG IC50 and free therapeutic Cmax as the industry-accepted cardiac liability cutoff; for a typical small-molecule free Cmax of ~0.3 µM this corresponds to an IC50 ≥ 10 µM.\n",
"rule_text": "BioMate halts if hERG IC50 ≤ 10 µM (admet_standard profile). The 10 µM operational threshold is confirmed in Bowes 2012 (Nat Rev Drug Discov 11:909-922, DOI 10.1038/nrd3845) as the cross-pharma industry consensus.\n",
"finding": "Remediation: tighten upstream logP filter per Waring & Johnstone 2007 (Bioorg Med Chem Lett 17:1759-1764, DOI 10.1016/j.bmcl.2006.12.061) logP/IC50 regression; or reduce MW per Aronov 2008 (Curr Opin Drug Discov Devel 11:128-140, PMID 18175275) \"Tuning out of hERG.\"\n"
```
