# Hard-Essential-KO Immunopeptidome RESCAN — did we miss public data that re-powers the failed leave-HLA-out H4 gate?

**Date:** 2026-09-13 · **Companion:** `HARD_ESSENTIAL_KO_RESCAN.json` · training_eligible = FALSE

## TL;DR

**Verdict: "CRO not shrinkable" is CONFIRMED. No qualifying public data was missed.**

- **NEW hard-essential-KO immunopeptidome deposits with a DISTINCT (disjoint) HLA background + fetchable processed ligandome: `0`.**
- One genuinely new B2M-KO deposit was found (**PXD063813**, C1R + K562), not previously in the inventory — but it **cannot re-power the gate** because (a) both lines are **HLA-A\*02**, the exact allele the gate already flagged as saturated/collapsed, and (b) its only processed file is a **tryptic whole-proteome DIA matrix**, not the HLA eluate.
- Reaching **≥3 disjoint-allele hard-essential-KO backgrounds** — the PASS condition — is **still not achievable from public data.** The CRO experiment is still required.

## What the gate needs vs. what public data offers (after rescan)

| Gate PASS criterion | Before rescan | After rescan |
|---|---|---|
| Hard-essential KO↔WT immunopeptidome backgrounds (usable processed ligandome) | 1 (HAP1) | **still 1** (HAP1) |
| Disjoint HLA alleles across those backgrounds | No (A\*02 collapse) | **still No** |
| Backgrounds carrying a positive severity→loss ordering | 1 (need ≥3) | **still 1** |

## The one new find: PXD063813 (log it, but it's not a gate re-power)

- **Title:** *The covalent bonding of beta-2-microglobulin with HLA class I influences the antigenic landscape of cells* (Liepe lab, deposited 2026-06, **OPEN**, timsTOF DIA).
- **Arms (24 raw `.d`):** `C1R-A02` (WT) vs `C1R-A02-NoB2M` (B2M-KO); `K562-A02` (WT) vs `K562-A02-NoB2M` (B2M-KO) — 6 runs each. **Clean WT↔B2M-KO contrast in two NEW cell lines.**
- **Why it does NOT qualify:**
  1. **No disjoint allele.** Both lines are HLA-A\*02 single-allele transfectants. A\*02 is already the collapsed allele shared by A375/THP-1/HeLa. This adds a 3rd/4th A\*02 B2M-KO replicate, not new allele coverage.
  2. **Processed file is proteome, not ligandome.** The held `report.pr_matrix.tsv` (44 MB, pulled to verify) is a **tryptic whole-proteome** DIA-NN search — confirmed from `report.log.txt`: `--cut K*,R* --missed-cleavages 1`, avg peptide length 14.3, ~7,800 proteins/run, 99% of 8–12mers end in K/R. The KO/WT ratios I computed (C1R 0.96, K562 0.99) are the **proteome** (unchanged by B2M-KO, as expected) — **not a presentation-collapse readout.** The eluted-ligand repertoire is only in the raw `.d` files and would need a fresh no-enzyme reprocessing (disk-prohibitive here).
- **Residual value (a cheap diagnostic, not a gate fix):** C1R and K562 are HLA-null parents carrying a single defined A\*02. If reprocessed no-enzyme, a clean B2M-KO **collapse** there would localize the unresolved **A375 B2M-KO non-collapse (88% retention)** — the *primary* CRO blocker per `LEAVE_HLA_OUT_RESULT.md` — to A375 itself (leaky KO / MHC1-TIP sensitivity) rather than to A\*02 biology. Worth flagging as the cheap A375-adjudication lead.

## Everything else examined and rejected (no clean hard-essential KO × distinct-HLA ligandome)

- **PXD060523** NLRC5-/- — **mouse** fibrosarcoma tissue (no human HLA).
- **PXD054743 / PXD046825** tapasin B\*44:02/44:05/W147A — **editor-dependence** system (721.220), same paradigm as held PXD063219; not a hard-essential collapse.
- **PXD048728** RNF185/tapasin — TMT **proteomics** screen (tapasin as substrate), not eluate.
- **PXD060641 / PXD061196** SUMO program — indirect immunoproteasome effect, no KO; MaxQuant proteome tables.
- **PXD024417** HeLa-CIITA — CIITA is the fixed background; perturbation is T6BP silencing (class-II).
- **PXD015957** PSMB8/9 — **overexpression**, not KO (and OE doesn't collapse presentation).
- **PXD027408** viral/TAP — PLC **proteomics**, viral not genetic.
- **PXD005544** TNBC — correlative APM downregulation, no KO. **PXD033485** — β2m dissociation biophysics, not a KO contrast.
- **PXD027006 / PXD046891 / PXD053256** — ERAP1 in-vitro / p14 / TYW2 — not APM hard-essential.

## Misclassification recheck (question a)

**No** held "WT-only" background hides a hidden hard-essential KO arm. Re-read PXD022020, PXD000394, PXD071022, PXD072525, PXD076608, PXD077352, PXD028364/PXD037365 — all baseline panels, disease-genotype comparisons, or drug/covalent perturbations. None carries a B2M/TAP/TAPBP/NLRC5/PSMB/CIITA genetic KO arm.

## MSV000091285 re-attempt (question b)

- **Non-FTP route WORKS.** MassIVE **https** `DownloadResultFile` returns HTTP 200; the GNPS datasette (`datasetcache.gnps2.org`) enumerates the `.mzML` tree (e.g. `...OTE_Aur2hr...` = ONX-0914/Aurora arm). The prior FTP block was **transport-only**; https is fully open and fetchable.
- **But it does NOT qualify for this gate.** MSV000091285 is a **pharmacologic UPS/proteasome-inhibition** study (its own summary: perturbing the ubiquitin-proteasome system; ~30% of the MHC-I repertoire is UPS-independent). It is **not** a genetic hard-essential KO and has no distinct-HLA KO↔WT structure. Fetchability was the only open question — resolved YES — but it adds no hard-essential KO background and should not be counted toward the ≥3 disjoint-allele requirement.

## Honest bottom line

The leave-HLA-out gate stays **FAIL / UNPROVEN across HLA** on public data. No public deposit supplies a hard-essential machinery-KO↔WT immunopeptidome on an allele **disjoint** from the A\*02 / HAP1 set. The single new B2M-KO deposit (PXD063813) is A\*02 and proteome-processed — a useful A375-discordance diagnostic, not a gate re-power. **The CRO experiment is still required to reach ≥3 disjoint-allele hard-essential-KO backgrounds.**
