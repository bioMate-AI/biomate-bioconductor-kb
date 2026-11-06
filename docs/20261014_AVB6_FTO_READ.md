# αvβ6 monomer — technical FTO read vs the Trivehexin/avebehexin genus

**Date:** 2026-10-14 · **INFORMATIONAL / TECHNICAL ONLY — NOT LEGAL ADVICE.** A real freedom-to-operate opinion
requires a patent attorney, the granted claims in each jurisdiction of interest, and a doctrine-of-equivalents
(DoE) analysis. This maps our candidates against the published genus to tell counsel where to look.

## The blocking patent
- **CA2998968A1 / CA2998968C** — "Ligands for integrin αvβ6, synthesis and uses thereof," inventors Quigley &
  Notni (TU Munich; licensed to **TRIMT GmbH**). Priority 2016-09-19; **granted; legal status active**; nominal
  term to ~2036-09-19. A broader family (WO/EP/US members) exists and must be pulled for the target jurisdiction.
- Source for the claim scope below: Google Patents text for CA2998968A1 (machine-read; **confirm X-definitions
  against the certified granted claim before relying on any "outside" call**).

## The claimed genus
`Cyclo-(Arg-X1-Asp-X2-X3-X4-X5-X6-X7)` (cyclic nonapeptide), with:
| pos | allowed residues (per fetched claim text) |
|---|---|
| Arg / Asp | fixed (the R..D of RGD) |
| X1 | Ser, Gly, Thr |
| X2 | Leu, Ile, Nle, Val, Phe |
| X3 | **Gly, Ala** |
| X4 | Leu, Ile, Nle, Val, Phe, Lys, Tyr, Trp, Arg |
| X5 | **D-Pro**, N-Me-D-lipophilic |
| X6 | Pro, **N-Me-amino acids, N-Me-Lys**, N-Me-Lys(Ac) |
| X7 | Ala, Leu, Ile, Nle, Val, Phe, Tyr, Trp |

Our scaffold `cyclo(P1-R-G-D-L-P6-P7-[dP]-[NMeK])`, read from Arg, maps as: R=Arg, G=X1, D=Asp, **L=X2**,
**P6=X3**, **P7=X4**, **[dP]=X5**, **[NMeK]=X6**, **P1=X7**. The lock (X5=D-Pro, X6=N-Me-Lys) and the flanks
(X4/X7 ∈ Phe/Tyr/Trp) are all squarely inside. **Multimers (formula II, n=3–5) and chelator conjugates (DOTA/
NODAGA/TRAP, ⁶⁸Ga/¹⁷⁷Lu…) are explicitly claimed too** — so the Trivehexin-style trimer-on-TRAP construct does
**not** escape the patent either.

## Candidate-by-candidate
Both controls are the patentee's own leads (inside by definition): Trivehexin monomer `c[YRGDLAYp(NMe)K]`,
avebehexin `c[FRGDLAFp(NMe)K]`.
| candidate | P1=X7 | P6=X3 | P7=X4 | literal status | notes |
|---|---|---|---|---|---|
| AVB6-R3-01 W/A/F | W✓ | A✓ | F✓ | **INSIDE** (infringes) | |
| R3-02 F/A/W | F✓ | A✓ | W✓ | **INSIDE** | |
| R3-03 W/A/W | W✓ | A✓ | W✓ | **INSIDE** | |
| R3-04 Y/A/W | Y✓ | A✓ | W✓ | **INSIDE** | |
| R3-05 W/A/Y | W✓ | A✓ | Y✓ | **INSIDE** | |
| R3-07 F/G/W | F✓ | G✓ | W✓ | **INSIDE** | |
| **R3-06 Y/S/F** | Y✓ | **S** | F✓ | **literally OUTSIDE X3** (Ser ∉ {Gly,Ala}) | **high DoE risk** (Ser≈Ala+OH) |
| **R3-08 W/S/F** | W✓ | **S** | F✓ | **literally OUTSIDE X3** | **high DoE risk** |

## Escape routes and how weak each is
1. **Non-Gly/Ala at X3 (P6=Ser, our R3-06/08).** Only a one-atom change from Ala → a court would very likely
   find it equivalent (DoE). Weak standalone basis.
2. **Non-canonical residues at the flanks (X4/X7) outside the enumerated lists** — e.g. 2-naphthylalanine,
   4-F/4-Cl-Phe, homophenylalanine (our ncAA "G1"-style ideas). These are literally outside the listed residues,
   the **strongest literal escape** — but each is a close homolog of Phe/Trp, so DoE still looms; needs counsel.
3. **Scaffold-hop out of the nonapeptide genus entirely** — different ring size/linkage, bicycle, non-RGDL
   presentation that keeps the pharmacophore+geometry but is not `Cyclo-(Arg-X1-Asp-X2-X3-X4-X5-X6-X7)`. This is
   the only route that leaves the claim by construction rather than by argument. (Matches the earlier rule-vs-
   novelty conclusion: real novelty is scaffold-hop, not monomer tweaks.)
4. **License from TRIMT.** The commercial-reality option for any genus monomer.

## Bottom line
Every mechanism-valid monomer we generate on the `…-RGDL-…-[dP]-[NMeK]` scaffold is **inside this granted,
active genus** — including the multivalent/chelator construct, which is separately claimed. The two Ser-at-X3
candidates are the only ones literally outside a listed position, and that gap is DoE-vulnerable. So:
- No αvβ6 **monomer** from this scaffold is FTO-clear without counsel, and most are plainly inside.
- The construct route (trimer/chelator) is also claimed — it does not provide freedom.
- The only structural path to freedom is a **scaffold-hop that exits the nonapeptide genus**, or a **license**.
This is why affinity ranking was moot: the gating constraint is IP, and it points the design effort at
scaffold-hopping (or licensing), not at optimizing another genus monomer.

## For counsel (next steps, not doable here)
Pull the granted claims of the US/EP/WO family members for the jurisdiction of interest; confirm the exact X3
and X4/X7 residue enumerations and any "comprising/consisting" and synthetic-amino-acid language; run the DoE
analysis on (a) Ser@X3 and (b) each proposed ncAA flank; and assess the multimer/chelator claims against the
intended construct.
