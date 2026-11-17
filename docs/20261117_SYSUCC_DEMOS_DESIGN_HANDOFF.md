# 2026-11-17 — SYSUCC/Zhongshan tutorial demos — design hand-off index (for the Claude design reference & recording)

**What this is:** a one-page index for the design/recording team. The 8 SYSUCC oncology tutorial demos are **authored and grounded in verified-live behavior** (run-verified on DEV this session). This points at the decks, the requirement spec, and the verification evidence.

> The SYSUCC demos **reuse existing platform surfaces** (chat → workflow panel → run → outputs/findings → report). Unlike the Design-loop and Dataset-panel docs, they introduce **no new design-reference surfaces** to build — the hand-off is: **record these decks**, and keep the design reference consistent with the executed self-correction they now show.

## 1. The 8 decks (recording-ready; bilingual en + 中文)

Each = a folder under `/Users/kky/Downloads/demo_recording_pack 2/tutorials_v3/` with `narration-v4.en.md` + `narration-v4.zh.md` + `"<name> walkthrough v4 - proposal.html"`, plus a shared `_ui/runs-zs-*.js` run-script.

| # | Use case | Deck folder | Self-correction shown |
|---|----------|-------------|-----------------------|
| 1 | NPC EBV-DNA MRD | `zhongshan-npc-ebv-mrd/` | EXECUTED — LoB/LoD gate, 8-read → indeterminate |
| 2 | EBV-biomarker survival (Cox) | `zhongshan-ebv-biomarker-survival/` | **EXECUTED (refreshed)** — cox.zph PH violation → auto time-transform refit |
| 3 | ICB RNA-seq (easier) | `zhongshan-icb-rnaseq-easier/` | orchestration-level (honest) |
| 4 | Neoantigen vaccine | `zhongshan-neoantigen-vaccine/` | **EXECUTED (refreshed)** — `classII_autolaunch` auto-launches class-II arm |
| 5 | Somatic + TMB (sarek) | `zhongshan-somatic-tmb/` | orchestrated (honest); test-data, cost-gated |
| 6 | TCR/BCR repertoire (airrflow) | `zhongshan-tcr-repertoire/` | EXECUTED — rarefaction gate |
| 7 | Spatial TME (RCTD) | `zhongshan-spatial-tme/` | EXECUTED — reference mismatch → auto-swap |
| 8 | Cyclic-peptide design | `zhongshan-cyclic-peptide/` | EXECUTED — validity gate (CPU enumerator scope, honest) |

**Hand off the whole `tutorials_v3/` folder** (or each `zhongshan-*` folder **plus** `_ui/` and the framework files `_v4.js`/`_lens.js`/`_deck.css`) — the decks are not self-contained without the shared `_ui` + framework.

## 2. Requirement spec + evidence

- **Design/eval requirement (authoritative):** `/Users/kky/Desktop/business/zhongshan_sysucc_demo_usecases.md` — per-use-case Requirements + Evaluation Criteria, now carrying the **"✅ VERIFICATION STATUS — 2026-11-16"** block (supersedes the older inline KNOWN-GAP/UNVERIFIED flags).
- **Run-verification evidence (per-run IDs, output files, self-correction confirmation):** `biomate-nextphase-ci-fix/docs/20261116_SYSUCC_USECASE_RUN_VERIFICATION.md`.

## 3. What changed that the design reference must stay consistent with

- **UC2 & UC4 self-correction went narrated → EXECUTED** (Cox auto time-transform refit; class-I→class-II `classII_autolaunch`). The decks now show the product self-correcting **by itself** — the design reference's depiction of these flows should match (no "being wired / Phase-0 / advisory" caveats).
- **UC6 & UC7 workflows were built this session** (were absent): airrflow repertoire + spatial RCTD — now runnable and demoed.
- **7 of 8 pass the live output gate**; UC5 is proven-runnable but deliberately cost-gated (not billed).

## 4. One remaining visual check

The decks are validated locally (`node --check` on run-scripts; all `data-region`s present) but were **not opened in a real browser**. A quick browser open of each deck before recording confirms the lens/animation timings land.
