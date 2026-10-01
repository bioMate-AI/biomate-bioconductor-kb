# GenScript Cyclic Peptide Synthesis — CRO Capability & Order Brief

**Date:** 2026-10-01
**Purpose:** Evaluate GenScript (and alternatives) for ordering a first round of ~12–15 de-novo **cyclic** peptide candidates. Round 1 = 10–16 residues, **head-to-tail / backbone (N-to-C) cyclized**, all-canonical amino acids. Later rounds may need **N-methylation + non-natural / D-amino acids**.
**Honesty contract:** Numbers tagged **[Reported]** are stated on a vendor/source page (URL given). Numbers tagged **[Estimated]** are inferred from comparable public price lists, not from GenScript directly. Where GenScript does not publish a value, it is marked **quote-based / not public**. No prices or lead times are fabricated.

---

## BOTTOM LINE (read first)

**Can GenScript make our Round-1 head-to-tail cyclic 10–16mers?** **YES, comfortably** — with no material caveat.
- Head-to-tail backbone amide cyclization ("Head to tail amide cyclic") is an explicitly listed standard GenScript modification. [Reported]
- 10–16 residues is well inside their cyclic range (cyclic service page states **up to 50 AA**). [Reported]
- All-canonical, single macrocyclic amide bond — this is routine SPPS + on-resin/solution macrolactamization. The only normal complication is sequence-dependent cyclization efficiency (head-to-tail of small rings can epimerize / dimerize), which GenScript QCs by MS + HPLC. Nothing here is specialty.

**Round-2 (N-methylation + non-natural / D-AAs)?** **YES, but as specialty work** — longer lead time, higher cost, and should be confirmed per-sequence at quote time. GenScript explicitly supports N-methylation, D-amino acids, and azide/alkyne (click) residues; coupling efficiency for heavily N-methylated / all-D sequences is lower, so timelines extend. [Reported]

**Order-spec essentials (what we must provide):** sequence (1-letter or 3-letter, **N→C**), cyclization type = *head-to-tail backbone amide* with the linked atoms (α-N of residue 1 to α-C of residue n), any terminal mods (for a pure backbone cycle there are **no** free N/C termini — state that explicitly), per-residue modifications in 3-letter bracket notation, **scale/quantity** (e.g. 5–10 mg), **purity** (≥95%), and **counterion/salt form** (default TFA; request acetate/HCl exchange if needed for assays). Submit via the online custom-peptide quote form or peptide@genscript.com.

**Rough cost/turnaround (Round 1):** GenScript does not publish cyclic prices. **[Estimated]** ~\$400–\$900 per peptide for a 10–16mer at 5–10 mg / ≥95% (base per-AA ~\$10–\$15/AA from comparable vendors + a cyclization surcharge ~\$200–\$500). **Lead time [Reported]:** GenScript advertises cyclic delivery "as fast as **7 business days**"; realistic for a batch of 12–15 is **~2–4 weeks**. Get a written quote — treat the estimate as a planning figure only.

---

## 1. GenScript Cyclic-Peptide Capability Table

Source: GenScript Cyclic Peptide Synthesis Service and Peptide Modifications pages. [Reported unless noted]

| Capability | GenScript offering | Standard vs Specialty | Notes |
|---|---|---|---|
| **Head-to-tail (backbone, N-to-C amide)** ← *our Round 1* | "Head to tail amide cyclic" — listed modification | **Standard** | The single backbone macrolactam we need |
| **Disulfide — single** | "Mono Disulfide bridge" | **Standard** | Most common cyclization |
| **Disulfide — multiple** | "Double" and "Triple Disulfide Bridge"; also "Random Disulfide Bridge" | Standard (1–2) / **Specialty (3)** | Up to **3 disulfide bonds**; 3-bond is "extremely difficult," random folding recommended |
| **Side-chain-to-side-chain lactam** | "Amide cyclic (Side chain)" | **Standard** | Glu/Asp ↔ Lys lactam bridge |
| **Head-to-side-chain lactam** | "Amide cyclic (Head to side chain)" | Standard | |
| **Side-chain-to-tail** | "Amide cyclic (Side chain to tail)"; lactone option | Standard | |
| **Stapled (hydrocarbon)** | Staple peptides, i,i+4 and i,i+7 (ring-closing metathesis) | **Specialty** | |
| **Bicyclic** | Bicyclic peptides with various central scaffolds | **Specialty** | |
| **Click (triazole)** | Conventional + copper-free; Lys(N3), propargylglycine available | Specialty | Supports azide/alkyne residues |
| **"20+ cyclization types"** | Page states >20 methods; "enquiries about other types welcome" | — | Flexible beyond the listed menu |
| **Max length (cyclic)** | **Up to 50 AA** | — | Our 10–16mers are well inside |
| **N-methylation** | Mono-/di-/tri-methylated Lys at >98% achievable; "other methylation combinations" | **Specialty** | Relevant to Round 2 |
| **D-amino acids** | Supported ("can handle such peptides"); lower coupling efficiency → longer timeline | **Specialty** | Round 2 |
| **Non-natural AAs** | Supported incl. azide/alkyne (Lys(N3), propargylglycine) | **Specialty** | Round 2 |
| **Purity grades** | Crude → ≥95% → ≥98% (higher on request) | — | |
| **Scale (cyclic)** | µg to mg (library tier 1–9 mg); linear service goes mg→kg | — | Research-scale fine |

> **Caveat to carry into the quote:** the **general** custom-peptide page cites length up to ~100–200 AA, but the **cyclic-specific** page caps cyclic synthesis at **50 AA**. For 10–16mers this is irrelevant, but do not assume 100+ AA cyclics.

---

## 2. Exact Order-Spec Checklist (what WE provide)

Provide each candidate as a row with these fields. For a **pure head-to-tail backbone cycle**, the termini are consumed by the ring — call this out so the vendor doesn't add a free acid/amide or an acetyl cap.

| Field | What to specify for Round 1 | Example |
|---|---|---|
| **Sequence** | 1-letter **or** 3-letter, written **N→C**. 3-letter is safer once non-natural residues appear. | `cyclo(-FKGPLAWRIV-)` or `Cyclo(Phe-Lys-Gly-Pro-Leu-Ala-Trp-Arg-Ile-Val)` |
| **Cyclization type** | State **"head-to-tail backbone amide (N-to-C)"** explicitly — distinguish from side-chain lactam | "Head to tail amide cyclic" |
| **Linkage atoms** | α-amino N of residue 1 ↔ α-carboxyl C of residue n (backbone amide). For side-chain cycles you'd name the two residues/positions. | N(res1)–C(res_n) |
| **N-terminus** | For a backbone cycle: **none / consumed by ring** (do NOT request acetylation). If a linear control is also ordered, specify free-NH2 or Ac-. | "cyclic — no free N-term" |
| **C-terminus** | For a backbone cycle: **none / consumed by ring** (not free acid, not amide). For linear controls specify -OH (acid) vs -NH2 (amide). | "cyclic — no free C-term" |
| **Per-residue modifications** | 3-letter bracket notation. Round 2: N-Me as `(NMe)Xaa` or `MeLeu`; D-AAs as `D-Ala`/`dAla`; azide as `Lys(N3)`. | `MeLeu`, `D-Pro`, `Lys(N3)` |
| **Scale / quantity** | Net mg of final purified peptide. 5–10 mg is typical for a first functional/screening round. | 5 mg (or 10 mg) |
| **Purity** | ≥95% (HPLC) for assay work; ≥98% only if needed (roughly doubles cost). | ≥95% |
| **Counterion / salt form** | Default is **TFA** salt. If peptide goes into cell assays / in-vivo, request **acetate** (or HCl) exchange — TFA is cytotoxic at residual levels. GenScript: standard <10% TFA, guaranteed <1% TFA; acetate exchange available. | "Acetate salt, TFA-free" |
| **Delivery format** | Lyophilized powder (standard). | Lyophilized |
| **QC deliverables required** | HPLC trace + MS + COA (standard); add solubility / endotoxin / AAA if needed. | HPLC+MS+COA |

**How to order / get a quote (GenScript):**
- Online custom-peptide quote/order form: `genscript.com` → Peptide → Custom Peptide (`/quick_order/peptide/custom_peptide_high_step1`). [Reported]
- Email: **peptide@genscript.com** · Phone: **1-877-436-7274**. [Reported]
- For 12–15 at once, submit as a **batch/table** and explicitly ask for a **multi-peptide / library quote** (see §4 on discounts).

---

## 3. QC, Turnaround & Pricing (with honesty flags)

### QC provided
| QC item | GenScript | Standard vs add-on |
|---|---|---|
| HPLC purity trace | Yes | **Standard** |
| Mass spec (ESI / MALDI) ID confirmation | Yes (MS for cyclization verification) | **Standard** |
| Certificate of Analysis (COA) | Yes | **Standard** |
| Qualitative solubility note | Yes (free) | Standard |
| Quantitative solubility test | Yes | **Add-on** |
| Amino acid analysis (AAA) / N analysis (true quantitation) | Yes | **Add-on** |
| Endotoxin testing | Yes | **Add-on** (needed for in-vivo) |
| Counterion / TFA→acetate(or HCl) exchange | Yes (std <10% TFA; guaranteed <1%) | **Add-on** (recommend for Round-1 assays) |
| NMR / residual solvent | Yes | Add-on (rarely needed at research scale) |

### Turnaround [Reported]
- Cyclic service advertised: **"as fast as 7 business days."**
- Linear express (TurboTIDE): 4–15 AA in **5 BD**, 16–25 AA in **7 BD** (guaranteed); standard ~10 BD / 2–3 weeks.
- **Planning figure for our batch of 12–15 cyclics: ~2–4 weeks.** The "7 BD" is a best-case single-peptide marketing number; a batch with cyclization + QC + (Round 2) specialty residues runs longer. Confirm in the quote.

### Pricing
- **GenScript publishes NO cyclic-peptide prices — quote-based / not public.** The quote process is the online form or peptide@genscript.com (§2).
- **[Estimated] planning range (Round 1, 10–16mer, 5–10 mg, ≥95%, TFA salt):**
  - Base linear synthesis at comparable vendors: **~\$10–\$15 per amino acid** at 5–10 mg / ≥95% (Bio Basic ~\$13.74/AA 5–9 mg >95%; ABI ~\$12/AA 5 mg >95%; Omizzur ~\$11/AA). → ~\$120–\$240 base for a 12–16mer.
  - **Cyclization surcharge:** a comparable published list (LifeTein) charges ~**\$500 for amide cyclization** (vs \$200 for one disulfide). Head-to-tail backbone amide is in the amide-cyclization class.
  - **All-in estimate: ~\$400–\$900 per peptide** Round 1. **[Estimated — not a GenScript quote.]**
  - Round 2 (N-methylation / D / non-natural) will be **materially higher** (lower coupling efficiency, specialty building blocks) — budget a premium and get a per-sequence quote.
- **Express:** GenScript offers express tiers (faster = higher cost); applies to eligible sequences.
- **Bulk/library discount for 12–15 at once:** GenScript runs a **peptide library / multi-peptide** service — ordering the set together typically earns a per-peptide discount vs singletons. **Discount magnitude is quote-based / not public** — explicitly request a batch quote.

---

## 4. Alternatives Comparison (cyclic-peptide CROs)

| CRO | Cyclization range | Head-to-tail macrocycle? | Where it's strongest | GMP / scale |
|---|---|---|---|---|
| **GenScript** | 20+ types: head-to-tail, lactam, disulfide (≤3), staple, bicyclic, click | **Yes — listed standard mod** | Fast, cheap, broad menu, online quoting, good for **discovery-scale batches** (our use case) | Has cGMP service; strongest at research → mid scale |
| **Bachem** | Head-to-tail + side-chain (lactam, thioether), + cyclization strategies | **Yes** | **GMP API manufacturing**, 50+ yrs; best for scale-up / clinical; broad salt exchange (HCl/acetate/Na/ammonium) | Premium GMP; overkill/costly for a 15-peptide discovery round |
| **CPC Scientific** | "Any peptide modification"; cyclic incl. head-to-tail | **Yes** | 2–200 AA, 80–99% purity; **US + China footprint**, research → clinical CMC; competitive discovery pricing | Research + clinical-grade CMC |
| **WuXi TIDES (AppTec)** | Linear, cyclic, highly modified, UAA, conjugates; on-resin cyclization | **Yes** (demoed on-resin cyclization of 30+ AA macrocycle) | **Huge experience base** (100k+ cyclics), unnatural-AA synthesis, integrated discovery→CDMO; strong for **N-methylated / non-natural (Round 2)** | Full CDMO incl. GMP API (>100,000 L SPPS) |
| **AnaSpec** | Lactam, disulfide, stapled, constrained scaffolds | Yes (constrained focus) | Research → GMP; good constrained/stapled catalog | Research → GMP |
| **CPC / Peptide 2.0 (discovery shops)** | Standard cyclics incl. head-to-tail | Yes | Low-cost fast discovery peptides; good for cheap first-round singletons | Research-grade |

**Recommendation for us:**
- **Round 1 (plain head-to-tail 10–16mers, batch of 12–15):** **GenScript** or **CPC Scientific** — both do head-to-tail backbone amides as standard, offer batch/library quoting, and sit at discovery price/speed. GenScript's online batch quote form is the lowest-friction path.
- **Round 2 (N-methylation + non-natural/D):** keep GenScript in the running, but also quote **WuXi TIDES** — their unnatural-AA + heavily-modified macrocycle depth is a differentiator; and **Bachem** if any candidate graduates toward GMP/scale-up.

---

## 5. "How Far Can GenScript Go?" — Verdict by Round

**Round 1 — plain head-to-tail 10–16mers, all-canonical, 5–10 mg, ≥95%:**
- **Fully within GenScript's standard capability.** Head-to-tail amide cyclization is a listed standard mod; 10–16 AA is far under the 50-AA cyclic ceiling; ≥95% + HPLC/MS/COA is standard QC. **No blocking caveat.**
- Order the whole set as a **batch** for a library discount; request **acetate (TFA-free) salt** if peptides enter cell/in-vivo assays; ask for endotoxin if in-vivo.
- Only real technical risk is **sequence-dependent cyclization yield** on small rings (possible epimerization/dimerization) — GenScript catches this at MS/HPLC QC; a few sequences may need re-synthesis or a turn-inducer (e.g. a D-Pro/Gly) in the design.

**Round 2 — N-methylation + non-natural / D-amino acids:**
- **Achievable but specialty.** GenScript explicitly supports N-methylation, D-AAs, and click/azide residues. Expect **longer lead times and higher per-peptide cost**, and **confirm each sequence at quote time** (heavy N-methylation or all-D backbones lower coupling efficiency and can hit practical synthesis limits).
- For the most aggressively modified / longest Round-2 candidates, **dual-source** against WuXi TIDES (unnatural-AA depth) and keep **Bachem** as the GMP/scale-up path.

---

## Sources

- GenScript — Cyclic Peptide Synthesis Service: https://www.genscript.com/cyclic-peptide-service.html
- GenScript — Peptide Modifications (cyclization types, N-methylation, D/non-natural AAs, termini): https://www.genscript.com/peptide_modification.html
- GenScript — Custom Peptide Synthesis (purity, scale, turnaround, TFA exchange, ordering): https://www.genscript.com/peptide.html
- GenScript — Large Scale Peptide Synthesis: https://www.genscript.com/peptide_large_scale.html
- GenScript — cGMP Peptide Synthesis: https://www.genscript.com/gmp_peptide.html
- Bachem — Custom Peptide Synthesis (cyclization, salt exchange): https://www.bachem.com/products/research-and-specialties/custom-peptide-synthesis/
- CPC Scientific: https://cpcscientific.com/
- WuXi TIDES — Custom Peptide Synthesis / Unnatural AA: https://tides.wuxiapptec.com/services-solutions/peptide/discovery/custom-peptide-synthesis/ · https://tides.wuxiapptec.com/services-solutions/peptide/discovery/unnatural-amino-acid/
- AnaSpec — Cyclic & Constrained Peptides: https://www.anaspec.com/en/cyclic-peptides
- LifeTein — cyclization fees (amide ~$500, disulfide $200/$400) [comparable-vendor price point]: https://www.lifetein.com/peptide-synthesis-services.html
- Bio Basic — peptide pricing (per-AA, 5–9 mg >95%) [comparable]: https://www.biobasic.com/peptides-pricing/
- ABI Scientific — standard peptide price list [comparable]: https://www.abiscientific.com/peptide_synthesis_price.html
- Omizzur — peptide synthesis price [comparable]: https://www.omizzur.com/peptide-synthesis-price/

## Verified — synthesis location (2026-10-01, web-checked)
GenScript's **peptide synthesis is done in Zhenjiang, Jiangsu, CHINA** (cGMP facility, ~30,000 peptides/month).
Its **Piscataway, NJ** site handles gene synthesis / oligos / sequencing — **not peptides**. So US peptide
orders are made in China and shipped internationally → **customs + shipping add days beyond the quoted
synthesis time** (material for a ~7-business-day target). Ask for door-to-door lead time incl. customs; if
7 days is hard, a US-footprint synthesizer (e.g. CPC Scientific) avoids the customs leg.
Sources: genscript.com peptide-production-facility (Zhenjiang) + genscript.com gene-synthesis-USA (NJ = genes).
