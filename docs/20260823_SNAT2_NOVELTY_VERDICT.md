# SNAT2 novelty verdict — prior-art review (2026-08-23)

Source: deep-research workflow (98 agents, 3-vote adversarial verification; run `wf_8407fe8d-50e`). Answers
"is modeling SNAT2's transport cycle novel and sensible?" *before* committing effort. Updates the 08-02
`SNAT2_RELATED_WORK.md` with current-literature verification.

## Verdict: YES — novel and sensible, but the strongest novel asset is time-sensitive.

### Findings (all HIGH confidence, unanimous or 2-1 votes; sources cited in the run)
1. **No experimental 3D structure of human SNAT2/SLC38A2 (Q96QD8) has ever been published or deposited** (no
   PDB/EMDB, any year through 2026). SNAT2's transport cycle is **not** structurally resolved. Verbatim from a 2024
   SAR paper: *"SNAT2 still lacks a solved 3D protein structure."* Sources: Amino Acids 2024 (10.1007/s00726-024-03424-3),
   Mol Biol Rep 2024 (10.1007/s11033-023-08976-3), Mol Pharm 2023 (10.1021/acs.molpharmaceut.2c00948), MDPI Pharmaceutics 2024.
2. **All prior SNAT2 computational work is single-state.** AlphaFold `AF-Q96QD8-F1` (inward-open) + LeuT/Mhp1
   homology models; the 2023 Mol Pharm study ran only 200–500 ns MD/PCA *within* the inward-open state. **No
   outward-open/occluded model, no transition path, no enhanced-sampling/kinetics of the inter-state transition
   exists for SNAT2.**
3. **Multi-state structures exist only for the paralog SLC38A9**, not SNAT2: crystal 6C08 (cytosol/inward-open,
   3.17 Å) + 7KGV (N-plugged, 3.40 Å); the 2020 cryo-EM 6WJ2/6WJ3 resolve only SLC38A9's cytoplasmic tail with
   Rag GTPases/Ragulator (mTORC1 signaling) — **no transporter-cycle info.** LeuT fold + TM1/TM8 Na⁺ site
   (SNAT2 N82/T384) are conserved → family-level coupling chemistry is partly inferable.
4. **⚠️ Competing effort:** a cryo-EM abstract *"Cryo-EM Structure Analysis of the Amino Acid Transporter
   SNAT2/SLC38A2"* was presented at **JBS 2024 (97th annual meeting, ~Nov 6 2024)** — the only located evidence of
   an experimental SNAT2 structure. Details (states/resolution/group, PDB/EMDB) **unverifiable (HTTP 403).**

### What is / isn't novel
- ✅ **A new experimental SNAT2 structure (the sister's 3.0 Å) is genuinely novel** — first-ever SNAT2 structure.
  **BUT at risk**: the JBS-2024 competitor may publish first. This is the crown-jewel asset and it is **racing a
  clock.**
- ✅ **A full inward↔outward transition-path / enhanced-sampling model of SNAT2 is novel** — all prior computational
  work is single-state.
- ❌ **NOT novel:** another single-state homology/AlphaFold model of SNAT2, or re-deriving family-level mechanism
  already inferable from SLC38A9.

### Honest caveats (flagged, not asserted)
- Could not *positively* confirm a 2025–2026 peer-reviewed SNAT2 structure hasn't appeared (searches found none,
  but absence-of-evidence). The JBS-2024 competitor could already be ahead.
- The transition-path model's novelty is real but more **incremental** (family mechanism largely known from
  SLC38A9); its value hinges on revealing **SNAT2-specific** features (substrate specificity, N82/T384 Na⁺
  coupling), not just re-showing a generic elevator.

## Strategic implication
- The project **makes sense and is novel — without needing the M6 methodological novelty at all** (validates the
  shelve decision). Two publishable pieces: (1) the experimental structure, (2) its transition-cycle model.
- **The experimental structure is the priority and is time-sensitive.** Effort is best spent supporting/finishing
  it (confident state assignment, quality) and coupling the computational cycle to it — not on methods novelty.
- Everything here is achievable with commodity tools (state-gen + membrane MD + transition path); no M6 required.

## Next (still groundwork-gated)
Before any execution: (a) a **confident state call** on the sister's structure (pore/gate/HOLE) — cheap, decides
everything downstream; (b) **deep understanding of the specific tools** for M1/M2/M3 on a transporter (the lesson
from the OM-TPS episode). Then a concrete, feasibility-gated SNAT2 plan.

## Change log
- **2026-08-23** — created. Cited/verified prior-art verdict: no published SNAT2 structure (novel, but JBS-2024
  competitor = at-risk/time-sensitive); no prior transition-cycle model (novel); single-state model or family
  re-derivation = not novel. Project is novel+sensible without M6; structure is the time-sensitive crown jewel.
