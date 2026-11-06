# Committee Review — BioMate New-Version Platform UI

**Date:** 2026-09-30 · **Convened by:** orchestrator (Chair)
**Scope:** the NEW-version platform UI (the "data-centric" redesign users see on dev today — the default chrome, *not* the flag-gated `?ui=v2` ResearchApp). Reviewed against the `reference/claude_design/data_centroid_design_v2/spec` (00–08), the settled positioning (`docs/20260922_CLAUDE_DESIGN_BRIEF_MARKETING_DECK.md`), and the live React code.
**Method:** 6 professional-lens reviewers (multi-model), each independently auditing 15 high-DPI live screenshots captured on dev + spec + code. Findings adjudicated by the Chair; items found by **≥2 lenses = consensus (high confidence)**. Screenshots live in the session scratchpad `platform_review/`.

## Committee composition
| Lens | Model | Status |
|---|---|---|
| UX & interaction | Sonnet | ✅ |
| Visual & brand design | Sonnet | ✅ |
| Product & positioning | Opus | ✅ |
| Frontend engineering & accessibility | Sonnet | ✅ |
| Spec conformance & completeness | Opus | ✅ |
| Scientific / domain correctness | Sonnet | ✅ (concise rerun after first stalled) |

---

## Overall consensus verdict

**The new platform has a sound skeleton and genuinely differentiated pieces built in code — but as it renders today it is not demo-/tutorial-ready and it under-sells its own moat.** Three named routes 404, every module screenshot is an empty state or input form (so the signature features are visually unproven), the front door reads as generic bioinformatics rather than the immune-mediated / peptide / closed-loop story the website now leads with, and there is a visible dual-design-system split. Crucially, **most of this is a surfacing / data-seeding / wiring problem, not a build-from-scratch problem** — the differentiated machinery (model object, quality gates, human-approval gate, multi-objective ranking, 2D depiction grid, provenance/lineage, honest IND report) already exists in the code.

---

## Consensus BLOCKERs (found by ≥2 lenses — high confidence)

1. **Three named routes render "Page not found."** *(Product, UX, Visual, Frontend, Spec-conformance — 5 lenses + Chair-verified.)* `/dashboard` (Runs), `/drug-discovery-cro` (CRO Library), `/billing`. **Root cause (Frontend):** the routes are commented out in `App.tsx` (`/dashboard` 608–611, `/billing` 616–619, `/drug-discovery-cro` 637–640). Billing was disabled because `BillingPage` crashes on `.toFixed()` of `undefined` (`billing.tsx:730`). Chair verified: `/dashboard`, `/drug-discovery-cro`, `/billing` = 404; `/projects`, `/workspaces` render fine. **Fix:** guard `compute.total_hours?.toFixed(1) ?? '0.0'` and re-enable billing; for dashboard/CRO add a redirect or an on-brand "coming soon" stub, or remove them from the sidebar — a labeled nav item that 404s is worse than a hidden one. CRO Library is a stated capability in CLAUDE.md and a differentiator; decide keep-or-cut.

2. **Every module screenshot is an empty state, input form, or 404 — the signature features are visually unproven.** *(Spec-conformance definitive; corroborated by UX, Product, Visual.)* The modules are ~90–100% implemented **in code**, but nothing captured shows a *result*: Search's conflict row, Data-analysis's ad-hoc compute result, Design's multi-objective ranking + 2D depiction grid, Models' model object + held-out gate — all exist in code, none render in any screenshot. **Fix:** seed **one clean demo project with a completed run per module** so tutorials capture real outputs, not blank panels. This is the single biggest blocker to the tutorial work (Track B/D of the marketing plan).

3. **The closed-loop moat is invisible in the product.** *(Product blocker; corroborated by Spec-conformance.)* The #1 differentiator — the generate→predict→make→measure→learn flywheel — has no first-class surface (no nav entry, no visualization); it's buried in a "Rounds" tab inside Models. The website now leads with it, so the platform contradicts the pitch. **Fix:** make the loop a named surface (Campaigns/Rounds nav + a signature flywheel the IL-17A pilot flows through) wiring together the pieces that already exist (Models "Rounds" + IND re-run gates + Design generate).

4. **The front door reads as generic bioinformatics, not the immune-mediated / peptide / closed-loop story.** *(Product blocker on cold-start + Capabilities; UX on off-strategy example chips.)* Cold-start says "What are you trying to do?" with four generic modules and generic example chips; the Capabilities page enumerates every modality ("we do everything") and uses the forbidden second-person "for you" (violates deck-brief §6). Peptides/macrocycles and immune-mediated disorders appear nowhere prominent. **Fix:** add a positioning line to cold-start, reorder toward the target→peptide→closed-loop journey (breadth as the engine underneath, the same reconciliation the website used), rewrite Capabilities to lead with the two moat pillars and drop "for you". Use the real IL-17A pilot as the guided first-run.

5. **Dual design-system / brand incoherence.** *(Visual blocker; Frontend; UX.)* The chat-shell surface (dark navy sidebar, "BioMate BETA" wordmark, dense ~12px UI) and the standalone "Platform" pages (`/models`, `/design`, `/files`, `/workspaces`, `/ind-report` — light header, different "BioMateᴬᴵ" lockup) read as two different apps. **Fix:** converge on one design language / persistent chrome. *(Separately, Frontend found the full `?ui=v2` ResearchApp hard-crashes — `window.SCENARIOS` undefined — so it is unusable; keeping it flag-gated is fine short-term, which validates shooting the default chrome for tutorials.)*

---

## Notable MAJOR findings

- **Test/e2e debris + duplicate flagship project pollute Projects/Data/Workspaces.** *(Product, UX, Visual.)* The `/projects` page still shows ~20–30 archived `e2e/smoke/S3-primary/latency-test` rows under the "All" filter, and the flagship "IL-17A Cyclic Peptide Pilot" is duplicated 4× with near-identical descriptions. **Chair note:** I archived 129 debris projects and shipped a sidebar filter (archived no longer shows in the *sidebar*), but the **`/projects` page needs an active-only default filter too**, and the 4 IL-17A dupes should be deduped/differentiated.
- **Off-brand blue CTAs instead of brand teal (#12808A).** *(Visual — global.)* "Generate & rank", active tab fills, selected toggles use a generic SaaS blue, diluting the teal-on-navy identity. One CSS-variable swap fixes most instances.
- **Monospace font leaking into body/description copy** on Data hub and Workspaces project rows. *(Visual — systemic CSS rule.)*
- **No-inventory copy-rule violations:** sidebar "Workflows **98**" badge and Models "**5 registered**". *(UX, Visual, Spec-conformance.)* Spec §0.15 forbids catalogue counts.
- **Intent router: send-vs-route ambiguity; the `.routebox` (lane + domain chip) never shows.** *(UX, Spec-conformance.)* The intent bar's filled-blue send button looks identical to the chat send; the routebox that restates the goal as lane+domain (the router's whole point) is in code but not visually surfaced. Closed module cards also omit the required lane label.
- **Missing spec-mandated features:** the **Agent trajectory tab** (spec 07 §7.7, a headline new feature) is absent; the **step-view over-reading guard** (3D structure + linked per-residue confidence chart/heatmap, spec 08 §8.5) is missing; the **skip-phase UI** is built but commented out ("no backend API yet"). *(Spec-conformance.)*
- **Accessibility gaps.** *(Frontend.)* Color-only status dots (sidebar history) violate WCAG 1.4.1; the full v2 surface has **no `:focus-visible`** styles and `--text-dim` (~2.5:1) fails AA; `/workspaces` has **no auth guard** (`App.tsx:708`); v2 files carry `@ts-nocheck` (12/13) and no mobile breakpoint. (Most are v2-scoped; the color-only dots and workspaces guard affect the live default chrome.)
- **v1 `--bm-*` CSS tokens may be defined only in the reference stylesheet, not globally.** *(Frontend — flagged; Chair: needs verification, since the live screenshots do show working muted greys.)*

## Scientific / domain-correctness lens
*(Domain facts checked out — PROTAC E3 ligases, CAR-T targets, cryo-EM pipeline all accurate. Key findings:)*
- **[Blocker] Design & Generate self-sabotages the peptide/macrocycle moat with Ro5 defaults.** The property envelope defaults (MW ≤500, logP ≤5, TPSA ≤140) *are* Rule-of-5 — but macrocycles/cyclic peptides (the moat) routinely live in bRo5 space (MW 600–1200, logP up to 7, TPSA up to 250). Presenting Ro5 as the envelope silently excludes the flagship category. **Fix:** switch to bRo5 defaults (MW ≤1000, logP ≤7, TPSA ≤250) when modality = Peptide/biologic; keep Ro5 only for small molecule.
- **[Blocker] "Target / seed (SMILES)" is the only input, even for Peptide modality.** SMILES is wrong for peptides — the native representation is one-letter sequence / HELM. Forcing SMILES for peptides is a credibility break in the very first interaction. **Fix:** show a sequence (FASTA/HELM) input when modality = Peptide.
- **[Major] IND report: PBPK gate FAILED yet "Ready to sign" still shows.** The panel reads "EMA criterion NOT met — AUC 0% within 2-fold" (a catastrophic DDI prediction) but the IND Document step still offers to export a CTD narrative, and the auto-generated §2.6.2.1 text cites the guideline as a *pass* — narrative and QC gate disagree on the same run. **Fix:** hard-block IND export when PBPK QC fails; the narrative generator must gate on QC-pass. This is the most damaging over-claim on the screen (regulatory-submission risk).
- **[Major] Models quality-gate card shows no metric/threshold** (no AUROC/RMSE/applicability domain) — "passed a held-out floor" is meaningless without the number. **Fix:** show e.g. "hERG AUROC ≥ 0.80 on ChEMBL held-out set".
- **[Minor] Capabilities over-claims** "IGN" as an *approved* ADC payload (it's clinical-stage only) → say "PBD dimer" or mark investigational. **[Minor]** Search example prompts lack any immune-disease framing despite the IL-17A focus.
- **Strengths:** the PBPK EMA-criterion citing (≥67% within 2-fold) is precisely correct; "property envelope not cut-off" is the right med-chem language; the training-loop "same compute/gates/tracking, not GLP-validated" framing avoids over-claim.

---

## Strengths (consensus — credit where due)

- **The IND report (`10_ind_report`) is the strongest screen** and the best embodiment of the product story: CTD Module 2.6 narratives, per-section status, an *honestly failed* PBPK/QC gate showing "measured vs threshold" (e.g. 2.4:1 vs 2-fold) with "review excluded compounds / re-run with new params" actions, regulatory-basis chips, and per-claim source badges — no composite score, no GLP over-claim. *(Product, UX, Visual, Spec-conformance.)*
- **The cold-start four-module intent-router architecture is sound** — intent-first framing, one card open at a time, examples that seed the composer. *(UX, Visual, Product.)*
- **The data-as-object / provenance-lineage model and honest empty states** are genuine differentiators for regulated buyers. *(Product, Frontend, Spec-conformance.)*
- **Search & evidence card is the best-aligned to buyer language** (target-to-disease confidence, SAR, selectivity failure). *(Product, UX.)*
- **v1 engineering discipline:** thorough `data-testid`/`data-status` coverage and a source-text "wiring-contracts" test suite; typed pages handle loading/empty/error honestly. *(Frontend.)*

---

## Prioritized remediation roadmap

**P0 — before any demo or tutorial capture:**
- Fix the 3 dead routes: one-line billing guard + re-enable; redirect-or-"coming soon" for Runs/CRO (or cut from nav).
- Seed **one clean demo project with a completed run per module** (Search answer w/ conflict row, ad-hoc compute result, Design generate → multi-objective + 2D grid, Models train → model object + gate, a workflow run → panel states + step view + after-run). Dedup the 4 IL-17A projects; add an active-only default filter to the `/projects` page.
- Keep `?ui=v2` gated (it crashes) — default chrome is the tutorial target.

**P1 — positioning & spec conformance:**
- Cold-start positioning line + reorder toward immune/peptide/closed-loop; rewrite the Capabilities page (drop "for you", lead with the two moat pillars).
- Make the closed loop a first-class surface (nav + flywheel + campaign/rounds), wiring existing pieces.
- Design & Generate: lead with Peptide/Macrocycle + "valid-by-construction"; wire generate→screen→measure→next-round.
- Add the Agent-trajectory tab; add the step-view per-residue confidence chart; wire the skip-phase UI (or descope from tutorials).
- Fix no-inventory copy, add lane labels to closed cards, surface the routebox.

**P2 — polish, brand & a11y:**
- Converge the two design systems / persistent chrome; swap blue CTAs → teal globally; fix the monospace-on-body CSS rule.
- a11y: add `:focus-visible`, raise `--text-dim` contrast to AA, give status dots a non-color carrier, add the `/workspaces` auth guard; verify global `--bm-*` token definitions.

---

## Which screens are demo-ready now vs need a run *(from Spec-conformance)*
- **Ready now:** cold-start `00` (routebox/lane-labels would improve it), the Search/Data/Design **cold-start cards** (entry-point shots only), Design & generate **input form** `03`, Capabilities `04`, and **IND report `10`** (strongest, fully populated).
- **Needs a live run / seeded data:** Search answer + conflict row, Data-analysis ad-hoc result, Models model object + gate, Design multi-objective + 2D grid, Files dataset-object tabs, and all Workflow-panel states + step view + domain viewers.
- **Broken — fix before capture:** Runs `05`, CRO `06`, Billing `09`.

---

## Change log
- 2026-09-30 — created from a 6-lens committee (UX, Visual, Product, Frontend/a11y, Spec-conformance complete; Scientific rerun pending). 5 consensus blockers (each found by ≥2 lenses; the 404s Chair-verified with root cause in `App.tsx`), major findings, strengths, and a P0–P2 roadmap. Screenshots in session scratchpad `platform_review/`.
