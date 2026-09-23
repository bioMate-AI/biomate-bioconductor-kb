# User Manual — screenshot & polish audit

**Date:** 2026-09-22
**Scope:** `docs/user-manual/` — all 45 chapters + the 11 embedded screenshots in `assets/`.
**Method:** visual read of every existing PNG + a reference-integrity check of every `![](…)` link across all chapters.
**Verdict:** the prose skeleton is broad and well-structured, but the manual is **not screenshot-complete or screenshot-clean**. Two classes of problem: (1) most referenced images don't exist, (2) several of the images that DO exist are captured from a debug scaffold or are stale.

---

## A. Broken image references — the biggest gap

The chapters reference **~40 screenshots; only 11 exist.** ~29 are broken links that will render as broken-image icons. Missing images are named on the `<chapter>-<n>-<slug>.png` convention but were never captured:

| Area | Missing images |
|---|---|
| **Domains (all)** | cryo-1/2, epi-1/2/3, metab-1/2, mg-1/2, mo-1/2, pk-1/2, prot-1/2, sc-1/2/3, struct-1/2, var-1/2 |
| **Data chapters** | ii01-1/2, ii02-1/2, ii03-1, ii04-1, ii05-1 |
| **Modules** | i04-1/2, i07-1/2, i08-2/3/4, i09-3, i12-1/2, i13-1 |

**Impact:** every domain chapter and every data chapter currently has at least one dead image. A reader opening `domains/variant-calling.md` sees broken images where the VCF viewer + MultiQC should be.

---

## B. Exceptions in the 11 existing screenshots

| File | Chapter | Problem | Severity |
|---|---|---|---|
| `i08-1-outputs-tab.png` | I08 | **Captured from the `/debug/viewer` scaffold.** Visible debug banner: *"Debug: NextflowWorkflowViewer chain … Mounts the workflow viewer with **hardcoded** status='completed' so the showResults gate … evaluates true. The embedded ChatOutputAttachments should render outputs."* Title reads **"Debug Workflow"**. | 🔴 High — internal debug text in a user manual |
| `i09-1-three-tabs.png` | I09 | Same debug banner **+** Summary tab stuck on **"Analysis in progress…"** on a run badged COMPLETED (the exact stuck-spinner state CLAUDE.md forbids shipping). | 🔴 High |
| `i09-2-reproducibility-record.png` | I09 | Same debug banner **+** placeholder/empty record: Workflow = **"Untitled Workflow"**, `Completed —`, `Input bindings (0)`, **all SHA-256 = "—"**. A reproducibility showcase with no hashes/inputs undercuts the chapter's point. | 🟠 Medium |
| `i01-1-cold-start.png` | I01 | **Stale** — sidebar still shows **Billing** and **IND Report** nav entries, both hidden on dev 2026-09-22. Now inconsistent with the shipped UI. | 🟠 Medium |
| `i05-0-data-hub.png` | I05 | Real product UI, but the project list is full of **E2E/test junk names** (`repro-verify-1789…`, `Chat references 1789…`, `DataUI FIX`, `E2E API Test`). Unprofessional for a manual. | 🟡 Low |
| `capabilities.png` | capabilities | **Low-resolution / blurry** — use-case cluster card text is barely legible at the embedded size. | 🟡 Low |

### Clean & usable (real product UI, professional)
`i05-1-file-tree.png`, `i05-2-dataset-header.png`, `i05-3-quality-tab.png`, `i10-1-models.png`, `i11-1-design.png` — these five are good and should be the styling/quality bar for re-captures.

---

## C. Root cause

The I08/I09 images were shot against `/debug/viewer/:runId` (a developer harness that mounts the viewer with a hardcoded `status='completed'`) instead of a real completed run. That harness prints its debug preamble on-page, so it leaks into every screenshot taken from it. It also can't populate real inputs/hashes → the "Untitled Workflow / SHA-256 —" emptiness.

## D. Recommendation (realistic, given volume + time)

1. **Re-shoot I08/I09 from a real completed run**, not `/debug/viewer` — this removes the debug banner, the "Analysis in progress…" stuck state, and the empty reproducibility record in one pass. Use the fixture account's `normqpcr` or an ADMET run that actually completed.
2. **Re-shoot i01** post-hide so the sidebar matches shipped (no Billing/IND).
3. **Either capture the ~29 missing images or remove the dead `![]()` links** so no chapter renders a broken-image icon. If time-boxed, prefer *removing* the links over shipping broken ones — a manual with fewer, correct figures beats one full of broken icons.
4. **Seed a clean demo project** (real-looking dataset names) before re-shooting I05 so no E2E junk names appear.
5. **Re-export `capabilities.png`** at 2× for legibility.
6. The clean five (I05 file-tree/header/quality, I10, I11) define the target style — match their framing (full-window, light theme, no debug chrome).

**Bottom line:** the manual is a solid outline but ~29 missing figures + 3 debug-scaffold screenshots + 1 stale + 2 low-polish means it is **not yet publishable**. The fastest path to "polished" is a single re-capture session from real runs, plus a decision to drop-or-capture the missing figures — not prose edits.
