# Pragmatic (pharma-chemist) knowledge DB — honest build/test/integration status

**Date:** 2026-10-21 · Companion to the design doc `docs/20261021_PHARMA_CHEMIST_EXPERIENCE_KB_DESIGN.md`.
Answers, without spin: is it **built**, **tested**, **integrated into BioMate**, and **documented**?

## Short answer
- **Built:** YES.
- **Tested:** unit-tested YES (10/10); in-product / E2E: **NO**.
- **Integrated into the BioMate product:** **NO — not finished.** Wired into the research loop only; the
  product bridge exists but has never been applied to the dev DB or consumed by the live composer/param-prefill.
- **Documented:** design + this status doc; a verified-on-dev integration write-up does **not** exist yet.

## What IS done
- **`cyclic_llm/medchem_kb.py`** — general evidence-grounded KB: 5 domains, 1,585 RDKit liability alerts each with
  a canonical citation, metal/physchem/pharmacophore/modality domains. Hard-evidence invariant enforced. BUILT-AND-TESTED.
- **`cyclic_llm/experience_kb.py`** — the resolver: `resolve(target)` → `{tool_params, eval_criteria(hard/advisory),
  provenance, candidates}`; `KBEntry.validate()` quarantines any claim without a real `provenance.ref` (served KB is
  100% evidence-supported). **Unit tests: `test_experience_kb.py` → 10/10 PASS** (validate, provenance-honesty,
  avb6 params/gateset, RAG-fallback, unknown-target-safe).
- **Research-loop integration:** `loop_batch.run_round` calls `experience_kb.resolve(target)` as the round's single
  source of params + gate-set (with a KB/target_spec cofactor-divergence assert). Real, used.
- **Product bridge (built, dry-run validated, NOT applied):** `register_experience_kb.py` renders `resolve()` into the
  product's existing `tools.scientific_context_v2` column (the surface the composer/search already consume). Dry-run
  confirmed it produces valid updates for **16 targets × physics tools**. `--apply` would write it.

## What is NOT done (the honest gaps)
1. **Not applied to the product DB.** `register_experience_kb.py` is **dry-run only**; `--apply` has never run against
   the **dev** `galaxy_ai_tools.db` (the canonical DB lives on dev/S3; the local copy is gitignored/stale). So the live
   product does **not** yet carry the KB knowledge. Per the no-ad-hoc-sync rule this apply must go through the dev
   process, not an out-of-band write.
2. **Read path not wired in the live product.** `kb_defaults_for(target)` (the intended composer/param-prefill read
   hook) is **not referenced anywhere in `backend/` or `frontend/`** (verified by grep). The product consumes
   `scientific_context_v2` generally, but nothing consumes the KB's target-level defaults/gates yet.
3. **No in-product / E2E test.** There is no test that the KB actually shapes param-prefill or routing in a live
   BioMate run (dev). Only the standalone unit tests exist.
4. **LLM-RAG seam is dead.** `experience_kb._llm_rag_call` returns `None` (no live LLM wired for novel-target recall).

## To finish (exact steps, in order)
1. **Apply on dev:** run `register_experience_kb.py --apply --db <dev galaxy_ai_tools.db>` through the dev deploy
   process (not ad-hoc SSM); then `rebuild_tools_fts.py` so the FTS/search surface picks up the new context.
2. **Wire the read path:** call `kb_defaults_for(target)` (or read the registered `scientific_context_v2`) in the
   param-prefill/composer path so a target-matched request actually gets KB-driven defaults + hard gates.
3. **E2E verify on dev:** a test that a cyclic-peptide request for a known target (e.g. αvβ6) returns KB-driven
   params + the hard-gate set, with provenance — against `dev-public.biomate.ai`.
4. **Document the verified integration** (screenshots/logs of the dev behaviour), and wire the live LLM for `_llm_rag_call`.

Until steps 1–3 are done, the correct statement is: **the pragmatic knowledge DB is built and unit-tested and its
product-registration mechanism is validated in dry-run, but it is not yet live in BioMate and not yet tested there.**
