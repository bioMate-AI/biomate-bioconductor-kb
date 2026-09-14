# H4 KO-collapse gate — screen of the ~212 NEW sweep deposits

Date 2026-09-14. `training_eligible=false`. SEARCH/metadata only (3.1 GB free, df-checked; no bulk pulls).

## Question
Among the ~212 NEW human-immune immunopeptidome deposits in `BROADER_DATA_SWEEP.json`, does any provide a
**genetic HARD-ESSENTIAL machinery perturbation** (B2M / TAP1 / TAP2 / TAPBP KO/knockdown/disruption, or natural
B2M-mutant / HLA-loss) with a **WT/control contrast** on a **NON-A\*02 (allele-disjoint)** HLA background and a
**processed ligandome** — i.e. something that could feed the ORIGINAL H4 **KO-collapse** gate that IFN-γ
(opposite-sign) data cannot?

## Answer: NO — 0 new disjoint-allele hard-essential-KO backgrounds

| Combined disjoint hard-essential-KO backgrounds | 0 |
|---|---|
| From the NEW sweep | 0 |
| Held (HAP1, A375 — both HLA-A\*02:01 post-renormalization) | 0 disjoint |
| Reaches ≥3 disjoint to re-power collapse gate w/o CRO? | **NO** |

**The CRO for the hard-essential disjoint-allele collapse claim still stands.**

## Priority candidates — all REJECTED for the KO-collapse gate

| Acc | What it is | Perturbation | Hard-essential? | Non-A\*02? | Verdict |
|---|---|---|---|---|---|
| **PXD052175** | Targeting ERAP / NKG2A-HLA-E (Broad) | ERAP1/2 aminopeptidase disruption | **No — trimmer/editor** | A\*02 cluster | REJECT (editor class; prior rescans already rejected ERAP) |
| **PXD025501** | HLA-I downregulation in Merkel cell carcinoma (Broad) | MYCL / PRC1.1 / USP7 — HLA-I **repressors**; loss RESTORES HLA-I | **No — upstream epigenetic regulator, GAIN direction** | mixed MCC lines | REJECT (not hard-essential machinery; wrong sign) |
| **PXD059832** | Cancer-restricted cryptic antigens (Science 2025, PDAC) | none (antigen discovery) | No | — | REJECT (no machinery contrast) |
| **PXD057858** | HIF/hypoxia translated ERVs (ccRCC) | hypoxia/HIF | No | — | REJECT (no machinery KO) |
| **PXD045855** | Integrated immunopeptidome+proteome COVID-19 lung | infection | No | — | REJECT (same-sample P+L, no KO) |
| **PXD066040** | Transgenic-mouse HLA-C\*06:02 psoriasis (Monash) | none (transgenic model) | No | C\*06:02 model | REJECT (allele model, no KO) |
| **PXD024248** | HLA-I ligandome of **HCT15/b2m** (jPOST) | natural B2M-mutant line — but this is the B2M-**reconstituted** rescue arm | B2M is hard-essential, but deposit is the **rescue** (gain) | **A\*02:01/A\*24:02 → A\*02+** | REJECT (A\*02, rescue arm not a KO-collapse contrast) |

## Machinery-token federated scan (ProteomeCentral PROXI + PRIDE v2)
KO-token regex (knock\*/CRISPR/B2M/β2m/TAP1/TAP2/TAPBP/tapasin/deficient/null/disrupt/HLA-loss/deleted/KD/LOH)
over the reachable immunopeptidome+ligandome slices surfaced **0 new** hard-essential-KO deposits. The only
KO-token hits were **already-logged** items: PXD063813 (B2M, A\*02, proteome-only), PXD024331 (abacavir, off-axis),
PXD015489 (cis-splicing, not a KO). A federated `B2M` keyword returned only mouse synaptosome/brain B2M
interactomes (PXD039275/74 — off-axis).

**Blind spot (unchanged):** the China-federated iProX/jPOST **native** pool (IPX/JPST accessions that never
federate to ProteomeXchange) throttled/timed out after ~6 queries — the same seam `BROADER_DATA_SWEEP` flagged.
It is the only place an unseen disjoint-allele KO could still hide; requires a re-sweep from an unblocked host.

## Why the sweep doesn't help this specific gate
The sweep's "machinery-perturbed" cluster is entirely: **trimmer/editor** (ERAP), **upstream epigenetic
repressor with GAIN-of-HLA direction** (MYCL/PRC1.1/USP7), **infection**, **hypoxia/ERV**, **antigen discovery**,
or **allele model**. None is a **loss-of-hard-essential-machinery collapse** on a non-A\*02 allele. The only
public route to a cross-allele machinery test remains the IFN-γ reframe (PXD014017, 3 disjoint backgrounds —
`H4_MACHINERY_PERTURB_RESCAN.json`), which is **opposite sign (gain, not collapse)** and does **not** satisfy the
KO-collapse gate.

## Bottom line
No public deposit — old or newly swept — supplies a hard-essential B2M/TAP/TAPBP KO↔WT immunopeptidome on an
allele disjoint from A\*02. Combined with the held (all-A\*02) HAP1/A375, the corpus still has **0 of the required
≥3** disjoint-allele hard-essential-KO backgrounds. The collapse-gate CRO cannot be avoided by public data.
