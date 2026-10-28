# Committee review — does BioMate's dry↔wet lab R&D cycle follow rigorous wet-lab protocols?

**Date:** 2026-09-22 · **Convened by:** orchestrator (Chair) · **Scope (as clarified by the user):**
strictly the **dry–wet lab R&D cycle of drug development** — computational prediction → wet-lab
validation → feedback/retrain. Not billing/i18n/other surfaces.

## Scope note (added 2026-09-22, per user)
The **Guangzhou deck is discovery-scoped** (generation + optimization; SA/affinity/safety). For that
deck, the **regulatory-compliance lane is OUT OF SCOPE** and should not gate it: GLP / 21 CFR Part 11
e-signatures & audit trail, the IND/CTD §2.6 document assembly, PBPK-qualification-for-submission,
Ames-strain-completeness-for-submission, NOAEL-for-first-in-human, EMA/ICH guideline citations. Those
belong to the separate CRO-compliance/IND module and are retained below only for when that module is in
scope. **Deck-relevant findings = the discovery dry-wet loop only:** assay-feedback data handling,
compound ranking/scoring, the multi-objective optimization loop, and its benchmark. See
"Deck-relevant subset" immediately below.

## Deck-relevant subset (discovery dry-wet loop)
Keep for the deck (these affect whether the loop's *scientific* outputs are trustworthy):
- **Assay ranking is statistically invalid** (geometric mean, replicate collapse, censored `>`/`<`, QC
  gating) — corrupts the compound rankings the loop produces. *(Assay: Opus + Sonnet)* — top priority.
- **DMTA simulation can't support "beats baselines"** (unfair frozen baselines + AD-index bug + silent
  random-FP fallback + non-deterministic seeding) — undermines any optimization-superiority claim.
  *(AL: Opus + Haiku)*
- **Benchling random-mock reachable in production** — fabricated assay values corrupt rankings/retrain.
  *(Assay: Opus + Sonnet)*
- **hERG margin uses total not free Cmax** — the *safety* optimization axis (one of the 3 tender
  dimensions) is computed wrong. *(reframed as discovery scoring, not IND compliance)* *(Tox: Opus + Sonnet)*
- Discovery MAJORs: non-idempotent ingestion (duplicate data), **unweighted MPO** (all objectives equal —
  directly relevant to multi-objective optimization), retroactively-shifting normalization bounds, GP
  uncertainty calibration, missing pM/% units.

Out of scope for the deck (regulatory module): blockers #1, #2 (e-sig/audit), #6 (Ames strains), #7, #8
(PBPK qualification / EMA citation), and the IND/NOAEL/M7 MAJORs.

## Committee composition (multi-LLM, professional roles)
Each professional role reviewed the ACTUAL code and was independently reviewed by **two different
LLMs** to avoid single-model blind spots (**10 reviews total, all complete**).

| Role | Model A (primary) | Model B (2nd opinion) |
|---|---|---|
| Bioanalytical / Assay-QC | Opus | Sonnet |
| DMPK / PK / PBPK | Opus | Fable |
| Preclinical Safety / Tox | Opus | Sonnet |
| GLP / Data-integrity / 21 CFR Part 11 | Opus | Fable |
| Active-learning / cheminformatics | Opus | Haiku |

Standards applied: ICH S7B/S7B(R1), S2(R1), M3(R2), M7(R2), M4S, OECD TG 471, FDA/EMA PBPK
guidance (FDA 2018, EMA/CHMP/458101/2016), ICH M12, FDA MRSD 2005, Redfern 2003, 21 CFR Part 11,
EU Annex 11, GLP (21 CFR 58 / OECD), ALCOA+, Truchon & Bayly 2007, Renz 2019.

## Overall consensus verdict
**Strong governance scaffolding, but NOT yet wet-lab/regulatory-defensible as-is.** The loop has
genuinely good *honesty discipline* and several *correctly-built primitives*, but carries multiple
**BLOCKER-level defects in scientific rigor AND data integrity**. Crucially, **most fixes are known,
surgical, and much of the right machinery already exists but isn't wired in.**

## Consensus BLOCKERs (independently found by ≥2 models — high confidence)

1. **hERG safety margin uses TOTAL, not FREE (unbound), Cmax.** *(Tox: Opus + Sonnet)*
   `ind_assembly.py ~3491`. `fu_plasma` is available but not applied → overstates margin by 1/fu (up
   to orders of magnitude); a torsadogenic compound can read as safe. ICH S7B §3.1 / Redfern 30×.

2. **Assay ranking is statistically invalid.** *(Assay: Opus + Sonnet)* `assay_ingestion.py`.
   (a) arithmetic (not geometric) mean of log-normal IC50/Ki/Kd; (b) **no replicate collapse** →
   multi-replicate compounds over-weighted + distort normalization; (c) censored `>`/`<` values
   stored then **ingested as real numbers** → inactives (`>50 µM`) rank like real hits; (d) **no QC
   gating** (Z′/%CV/curve-fit R²/Hill). Would corrupt rankings. ICH M10 / ALCOA+.

3. **Benchling random-mock reachable in production.** *(Assay: Opus + Sonnet)* `benchling_connector.py:56`.
   `mock_mode` auto-activates when the API key is unset → fabricated `random.uniform` IC50s enter the
   campaign DB with **no synthetic-provenance flag**. Data-integrity violation.

4. **E-signature fails OPEN in production.** *(GLP: Opus + Fable)* `ind_actions_router.py:103,128`.
   Any 6-digit code is accepted as a 21 CFR Part 11 signature when `BIOMATE_REQUIRE_AUTH != "1"`
   (the default), with no environment gate. **Opus found a compounding blocker** (`feedback_auth.py:100`):
   the first auth factor also falls back to `user_id="anonymous"` on the *same* flag → default posture =
   anonymous + any-6-digits "signature."

5. **Signature audit log is not tamper-evident.** *(GLP: Opus + Fable)* The sign path writes a mutable
   `sign_audit_chain.jsonl` whose "hash chain" is recomputed at PDF-render time (edit a row → it
   re-verifies). The genuinely correct hash-chained `AuditStore` **exists but the sign path doesn't use
   it**; the S3 WORM mirror is off by default. 21 CFR Part 11 §11.10(c)/(e).

6. **Ames strain set incomplete/inconsistent.** *(Tox: Opus + Sonnet)* Rendered table
   (`ind_assembly.py:3332`) omits **TA102 / E. coli WP2 uvrA** (oxidative-mutagen coverage required by
   ICH S2(R1) §4.1 / OECD TG 471) and contradicts the YAML's own correct list.

7. **DMTA simulation cannot support "beats baselines."** *(AL: Opus + Haiku agree on the core)*
   Only BioMate runs the closed feedback loop; baselines are frozen / don't get oracle updates
   (Renz-2019 unfair-baseline failure). Opus adds: analog leakage from random split, mislabeled EF,
   silent random-fingerprint fallback, non-deterministic `hash()` seeding. Haiku adds a concrete
   **AD-index off-by-one bug** (`bayesian_optimizer.py:445-451`).

8. **PBPK "qualification" is circularity, laundered at the consumption layer.** *(DMPK: Opus + Fable)*
   `model_validation.py` is *honest* that it feeds OBSERVED CL/Vd/F into a 1-compartment equation
   (verification, not qualification) — but `ind_assembly.py:782` **strips that disclaimer** and relabels
   the result "PBPK model qualification: AFE=… / EMA criterion Met ✓" in the CTD 2.6.2 text and API
   ("suitable for attachment to IND"). An EMA assessor spots observed-input circularity immediately.

9. **Fabricated EMA guideline ID — and the QC loop enforces it.** *(DMPK: Opus + Fable)* The PBPK
   guideline is cited throughout as **`EMA/CHMP/EWP/37498/2011`** with an invented revision lineage;
   the correct ID is **EMA/CHMP/458101/2016**. Worse, the auditor's `CITE_001` + autoloop **force this
   wrong citation into every regenerated IND narrative** — the QC loop enforces the error. Compounded by
   a **fabricated "EMA requires ≥67% within 2-fold"** criterion attributed to EMA, which sets no numeric
   threshold. An instant credibility kill in EMA review.

## Notable MAJOR findings
- **PK extraction is context-blind first-regex-match** — no analyte(parent/metabolite)/species/route
  disambiguation; CL conflated with CL/F; species silently defaults to human at HIGH confidence; no NCA
  (λz, %AUC-extrap) and no AUCinf-vs-last discriminator. *(DMPK: Opus + Fable — consensus)*
- **NOAEL negation trap** — "a NOAEL was **not** established; highest dose 100 mg/kg" → NOAEL=100; also
  first-match (not most-sensitive species); feeds a wrong first-in-human dose. *(Tox: Opus+Sonnet; DMPK: Fable)*
- **Per-value provenance destroyed at the IND merge** (`to_pk_summary_override` flattens to bare floats). *(DMPK: Opus)*
- **ChEMBL hERG mislabeled `measured_patch_clamp`** — literature aggregate presented as GLP IKr. *(Tox: Sonnet)*
- **False GLP-NOAEL dose anchor** — §2.6.7.1 references "the GLP NOAEL" when none exists; genotox "Option 2 deferral" misreads ICH S2(R1). *(Tox: Sonnet)*
- **ICH M7 TTC units error** — 1.5 µg/day mislabeled as ppm. *(Tox: Opus)*
- **Plaintext MFA secrets + self-service MFA reset** → downgrade to bypass; **unauthenticated export/delete/rerun endpoints**; **unverified-JWT attribution**. *(GLP: Opus + Fable)*
- **Non-idempotent assay ingestion** → duplicate CSV re-uploads silently double data. *(Assay: Sonnet)*

## Strengths (consensus — credit where due)
- **Measured-vs-predicted provenance** tagging and **"in silico never satisfies GLP"** messaging are
  correctly and pervasively implemented. *(all reviewers)*
- The code is **honest** that feeding observed CL/Vd into a 1-compartment model is equation-verification,
  **not** PBPK qualification; **AFE/AAFE computed correctly**. *(DMPK: Opus)*
- **`audit_store.py`**: correct append-only SHA-256 hash chain, race-safe `BEGIN IMMEDIATE` writer, real
  `verify_chain()`. **`esig.py`**: correct RFC 6238 TOTP, true single-use replay protection, AES-256-GCM
  secrets. *(GLP: Opus + Fable)* — the right primitives exist; they're just not wired into the sign path.
- Real held-out **ChEMBL oracle** + multi-seed bootstrap + sensible comparator set in the sim. *(AL: both)*

## Dissents (Chair adjudication)
- **AL lane:** Opus judged the EF mislabeled/non-standard with deep methodology flaws; Haiku called the
  EF "correct" and was more lenient. **Chair ruling:** Opus is technically right — the metric is a batch
  hit-rate ratio, not a ranked EF_f (Truchon & Bayly); treat the methodology critique as authoritative.
  But Haiku's concrete AD-index bug is a real find both must fix. Net: **the sim needs a per-method
  independent-loop refactor + scaffold split + greedy-exploit baseline + paired significance before any
  "wins" claim.**

## Prioritized remediation roadmap
**P0 — integrity & safety (before ANY real data or external claim):**
- Fail-closed auth/signature defaults (deny-by-default; no anonymous signer; remove any-6-digits path from
  GxP-capable builds); route `/sign` through the real hash-chained `AuditStore`; make WORM mirror mandatory.
- Hard-fail Benchling on missing key (no random mock in prod; tag synthetic rows, refuse to ingest them).
- hERG margin over **free** Cmax (`× fu_plasma`); abstain if `fu` unknown.
- Assay ranking: geometric mean + replicate collapse + censored-value handling + QC gating.

**P1 — scientific correctness:**
- Ames strain set (add TA102/WP2 uvrA; single-source from YAML); ChEMBL hERG provenance relabel.
- NCA engine + context-anchored PK extraction (analyte/matrix/route/dose); carry per-value provenance to IND.
- Sim: per-method independent loops, scaffold-disjoint split, greedy-exploit baseline, paired significance,
  hard RDKit/determinism guards, fix AD-index bug — before citing any benchmark.

**P2 — hardening:**
- Idempotent ingestion; pM/% unit coverage; ICH M7 TTC units; correct EMA PBPK citation; encrypt MFA
  secrets; auth on all mutating/export endpoints; correct the "NOT WIRED" comment on the live sign overlay.

## Honest framing for the Guangzhou deck
- **Do NOT** claim the dry-wet loop is GLP/Part-11 compliant, or that the simulation shows BioMate beats
  baselines — neither is currently defensible.
- **DO** claim: an integrated DMTA architecture with real measured-vs-predicted provenance discipline and
  correctly-built compliance primitives, under active hardening; **prospective wet-lab validation is the
  moat and has not yet been run.** Frame any ROI numbers as pilot-validated, not asserted.

## Remediation shipped (PR #239 → integration/next-phase)
The four deck-relevant (discovery-loop) P0 fixes were implemented + tested on branch
`feat/drywet-loop-p0-fixes` (sparse worktree off next-phase):
- **Assay ranking:** geometric mean, replicate collapse, censored-value handling, QC quarantine,
  log-space pIC50 normalization, idempotent re-ingest, value sanity, pM/% units.
- **Benchling:** fail-closed on missing key, synthetic tagging, explicit field mapping.
- **DMTA sim + BO:** per-method independent state (fair baselines), greedy-exploit baseline, RDKit
  guard, stable hashlib seeding.

**Test audit (a second multi-LLM committee, 5 reviewers across Sonnet/Fable):** the fix agents' tests
were adversarially audited with one acid test — *would each test FAIL on the pre-fix code?* This caught
several tests that passed on BOTH old and new code (worthless as regression guards): the replicate-collapse
test (identical replicates), two censored tests (censored value at the numeric extreme), the per-method
isolation test (invariant computed but never asserted), and the `_fresh_state` tautology. All were
**rewritten and empirically re-verified** (fail on `origin/next-phase`, pass on the branch). Final: **48
tests**, regression ones proven fail-on-old / pass-on-new.

**Two originally-flagged findings were verified NON-BUGS and honestly reframed (not faked into tests):**
- **AD-index "off-by-one"** (orig. rated BLOCKER by Haiku): `proposed_smiles[len(ad_statuses)]` equals
  `proposed_smiles[ad_idx]` in every reachable path — cosmetic clarity refactor, no behavioral change.
- **EHVI reference point** (orig. MINOR): `MinMaxScaler` in `fit()` forces each objective's training min
  to ~0, so `observed_worst − eps` clips back to zeros — equals the old zeros reference for any fitted
  dataset. Cosmetic.
These corrections show the value of the second (test-audit) pass — the first committee over-flagged two
items; verification caught it.

## Change log
- 2026-09-22 — created from a **complete 10-review multi-LLM committee** (5 roles × 2 models across
  Opus/Sonnet/Fable/Haiku). 9 consensus blockers (each independently found by ≥2 models), MAJORs,
  dissents, and a prioritized remediation roadmap recorded. DMPK/Fable second-opinion folded in: elevated
  the PBPK circularity-laundering and the fabricated+QC-enforced EMA guideline ID to consensus blockers.
