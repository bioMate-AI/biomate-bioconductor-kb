# 2026-11-09 — UI-refinement close-out, tabular diffusion method, and dev deploy

**Branch:** `cursor/tutorial-live-recording-and-report-editing-4ea7`
**Final HEAD:** `9228b39e73` (feature) → `6c4d194b9f` (CI-only follow-up)
**Dev:** `https://dev-public.biomate.ai` synced to `9228b39e73`, full frontend+backend+workflows, health + smoke green.

This session closed out the 30-screenshot UI-refinement backlog, added a third diffusion
training method (general tabular / TabDDPM), and deployed both the frontend and the
(previously-behind) backend layer to dev. It also built and pushed the tabular-diffusion GPU
image to ECR.

---

## 1. UI-refinement backlog — all 30 screenshots now resolved & live

Triage + per-screenshot status table: `docs/20261108_UI_REFINEMENT_ISSUES.md` (updated this
session). The last four partial/open items were closed by two parallel sub-agents and committed
in **`9fcdea34ba`**, plus the chat-prose ID rule in **`aebf2f5b4c`**:

| Screenshot item | Resolution | Commit |
|---|---|---|
| `crowd_parameters…sameQC_eachphase` (🟡 crowded param line) | Collapsed per-phase param summary now renders **one `label: value` per row** (flex column, `overflowWrap:anywhere`) instead of a crammed ` · `-joined run-on line. `nextflow-workflow-viewer.tsx:859-868` | `9fcdea34ba` |
| `biomate_history_weirditem` (🟡 history-NAME filter) | Internal `GalaxyChat-*` history names shown as **"Chat session · <date>"** via `friendlyHistoryName()`; conservative regex (only `GalaxyChat[-_ ]` names), user-named histories untouched; still searchable by "chat". `galaxy-dataset-browser.tsx:86-108` | `9fcdea34ba` |
| `need_better_design_claude` (🟡 From-URL redesign) | **From-URL tab redesigned**: input + Import button promoted to the top; the notice + 5 example-URI rows + S3 help moved into a collapsed "Examples & accepted sources" disclosure. `galaxy-dataset-browser.tsx:558,569-680` | `9fcdea34ba` |
| `formats_duplications` (🟡 duplicate chat-start buttons) | Removed the redundant top-right header **"Chat"** button (`button-open-project-chat`); kept the center "New Chat" CTA + Chat/Files tab nav. `project-detail.tsx:661-664` | `9fcdea34ba` |
| `unnecessary_id_response` / `ID_everywhere` (❌ raw IDs in prose) | Prompt rule in `galaxy-assistant.ts:9695`: *"refer to it by its NAME only … never print its id/UUID or s3_uri in prose."* | `aebf2f5b4c` |
| `noteasexample_instruction_rule` (❌ seeded-rule labeling) | Section hint under the RULES header: seeded rules may be project defaults/examples, editable/removable (`rules_seed_hint`, `data-testid=rules-seed-hint`). `project-guidance-cards.tsx:130-134` | `9fcdea34ba` |
| `QC_wrong_under_溯源` (backend, not-yet-deployed) | Header-only CSV profiler fix + required-input classification **now deployed** (§4) | `3823ee6aa8` / `40c814f12e` |

**Result: 0 code issues open from the 30 screenshots.** The only residual action is an AWS grant
(SES, §5), not a code fix.

### Sub-agent orchestration
Two general-purpose agents ran in parallel in the main worktree, each constrained to: use
`tOr(key, englishFallback)` and **report** new i18n keys (not edit `common.json`); no
`nextflow_nfcore` edits; run `tsc` + `vitest` before hand-back.
- **Agent E** — From-URL redesign + friendly history names (`galaxy-dataset-browser.tsx` + test).
- **Agent F** — crowded-param restyle + seeded-rule hint + duplicate-chat-button removal
  (`nextflow-workflow-viewer.tsx`, `project-guidance-cards.tsx`, `project-detail.tsx` + locale test).

### i18n keys added centrally (en + zh)
Added by hand to `locales/{en,zh}/common.json` (agents only reported them):
`datasets_dialog.url_examples_toggle`, `datasets_dialog.history_auto_label`,
`datasets_dialog.history_auto_label_dated`, `project_instructions.rules_seed_hint`.

### Verification before commit
`tsc --noEmit` 0 errors; `vitest` 68/68 on the touched suites. Committed `9fcdea34ba`, pushed,
frontend-only sync to dev → healthy + smoke pass.

---

## 2. PR #341 updated

`fix(ui): dataset/workflow panel refinement + Notes→Memory + unified team invites` (base
`integration/next-phase`, head `fix/ui-refinement-20261108`). Updated by **merging the session
HEAD into the PR branch** (a merge, not cherry-pick — the PR branch already held earlier versions
of some fixes, so cherry-pick conflicted on duplicated changes). Resolved 2 conflicts (a doc + the
locale test mock — took the session version), tsc-verified the merged branch, pushed **`53dabc29b3`**.

---

## 3. New training method — general tabular diffusion (`tabular_diffusion`)

Third diffusion generative method alongside `protein_diffusion` (structure) and `scrna_diffusion`
(single-cell h5ad). **BioMate now has 9 training methods, 3 diffusion.** Full vertical slice built
by a sub-agent (mirroring the scRNA integration), reviewed diff-by-diff, committed **`9228b39e73`**.

| Diffusion method | Domain | Dataset |
|---|---|---|
| `protein_diffusion` | structure design (RFdiffusion) | PDB/mmCIF backbones |
| `scrna_diffusion` | single-cell expression | h5ad AnnData |
| **`tabular_diffusion`** *(new)* | generic tabular synthesis (TabDDPM/TabSyn) | CSV/parquet feature matrix |

**Files (new):** `tabular_diffusion_trainer.py`, `tests/test_tabular_diffusion.py` (18 tests),
`.github/workflows/tabular-diffusion-training-image.yml`, `backend/docker/tabular-diffusion-training.Dockerfile`.
**Files (modified):** `config.py` (`tabular_diffusion` in `MODEL_TYPES`+`DIFFUSION_MODEL_TYPES`,
`tabular_generation` task, `TabularDiffusionSpec`, validation/from_dict/params_schema),
`chemprop_trainer.py` (dispatch), `executor_payload.py` (`_DEFAULT_TABULAR_DIFFUSION_IMAGE` + `tab_*`
params), `cli.py` (`--tab-*`), `training_job.py`, plus UI: `deep-learning-models.tsx` (method card)
and `spec-setup.tsx` (structured panel — **not** chat-setup) + test.

**Spec:** `framework` (`tabddpm`|`tabsyn`), `finetune`+`base_checkpoint` (warm-start/scratch),
`target_column` (categorical conditioning; blank = unconditional), `n_rows_to_generate`,
`guidance_scale`, `diffusion_steps`, `noise_schedule`.

**Design discipline honored:** trainer is lazy-import-guarded (pandas/tab-ddpm/tabsyn); when the
framework is absent it raises an **honest `ImportError`/`NotImplementedError` naming the image**
(`biomate/tabular-diffusion-training:latest`) — not a crash-stub at module load. No `common.json`
or `nextflow_nfcore` edits. One intentional narrowing vs scRNA: **no chat-intent routing branch**
(the Models panel is the entry point; a chat route would need a `.nf` wrapper under
`nextflow_nfcore/`, which is off-limits).

**Independent verification (not just the agent's word):**
- `config.MODEL_TYPES`/`DIFFUSION_MODEL_TYPES` membership `True/True` (loaded config.py directly,
  bypassing this host's broken `galaxy.ai.__init__` → scipy-fitpack ABI chain).
- All four validation guards fire (task_type, missing-spec, finetune-without-checkpoint, framework).
- `py_compile` clean on all backend files (Python 3.9).
- 18 backend unit tests pass (`--import-mode=importlib`).
- Frontend `tsc` 0 errors; 54/54 models tests pass.
- 8 new i18n keys added centrally to en+zh under `models.*`.

**i18n keys added:** `models.dl_m_tabular_diffusion`, `dl_d_tabular_diffusion`,
`dl_spec_dataset_tabular`, `dl_spec_finetune_tab`, `dl_spec_base_checkpoint_tab`,
`dl_spec_tab_warmstart`, `dl_spec_target_column`, `dl_spec_n_rows`.

---

## 4. Deploy to dev

### Frontend (incremental, proven path)
`BIOMATE_ONLY_FRONTEND=1` syncs from a clean worktree (`/Users/kky/biomate-syncdeploy`):
- `9fcdea34ba` (E/F polish) → healthy + smoke pass.
- `9228b39e73` (tabular UI panel) → healthy + smoke pass.

### Full backend+workflows (brings dev's backend current with the branch)
First full-sync attempt **failed at preflight** — `infra/nfcore-patches missing from checkout` —
because the deploy worktree was **sparse** (`backend/config`, `frontend`, `scripts` only), built
for frontend-only deploys. Fixed by expanding its sparse set
(`git sparse-checkout add infra backend/biomni_workflows backend/nf-core-workflows
backend/nf-core-modules`; `backend/database`, 1.2GB, left excluded since `db=false`). Re-ran →
**green**: 679 Python files deployed into `biomate-galaxy-dev`, workflows layer synced (49M .nf
archive, nextflow caches cleared), **Galaxy HUP'd healthy in ~40s** (the `tabular_diffusion`
backend code loaded with no crash-loop), smoke pass. `Sync complete for 9228b39e (result=healthy)`.

> Note: the workflows layer fired because frontend-only syncs never advance the last-synced marker,
> so a subsequent full sync sees an empty diff baseline and treats the whole branch as pending.
> This ships accumulated backend+workflow state (incl. other sessions' committed work on the shared
> branch) — acceptable here (shared integration branch), but a deliberate op, not a one-file tweak.
> Captured in memory (`reference_syncdeploy_worktree`).

---

## 5. Tabular-diffusion GPU image — built & pushed to ECR

- **ECR repo created** `biomate/tabular-diffusion-training` + repository policy granting
  `GitHubActionsECRPush` (replicated from `sc-diffusion-training`). *These AWS mutations are
  blocked by the auto-mode classifier regardless of user authorization — the user ran the two
  `aws ecr` commands via the `!` prompt prefix.*
- **Build triggered** by pushing tag `tabular-diffusion-training-v**` (the workflow's trigger;
  `gh workflow run` doesn't work because the workflow isn't on the default branch yet).
- **First run (`v1`) stalled 55 min on `actions/checkout`** — root cause: the branch carries ~1.2GB
  of committed data (`galaxy_ai_tools.db`, `docs/*.npz`, figures), and checkout runs *before* the
  disk-cleanup step. Fixed properly (not worked around) in **`6c4d194b9f`**: sparse + blob-filtered
  checkout (`sparse-checkout: backend/lib/galaxy/ai/ml_training + the Dockerfile`, `filter:
  blob:none`) — the build needs only the one `COPY`'d dir; everything else is pip/git installs. This
  also shrinks the `context: .` build context.
- **Re-tagged `v2` → build green.** Checkout cleared in seconds; Docker build (CUDA 12.1 + torch +
  TabDDPM/TabSyn) succeeded; **pushed `:latest` + `sha-6c4d194b9fde` (5.4GB)**; the CI smoke step
  (`python -m ml_training.cli --help` *inside the pushed image*) passed.
- **Wiring verified end-to-end:** `executor_payload._resolve_container` returns exactly
  `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/tabular-diffusion-training:latest` (the
  URI pushed), matching the working sc-diffusion convention, env-overridable via
  `TABULAR_DIFFUSION_TRAINING_IMAGE`.

A `tabular_diffusion` run from the Models panel now validates server-side → dispatches to Batch →
pulls the real image; it no longer hits the `NotImplementedError` placeholder.

---

## 6. Open items

1. **SES grant (email):** the `galaxy-dev` IAM user (frontend container) lacks `ses:SendEmail`, so
   team-invite emails don't actually send (code + unified-invite flow are done & deployed). Needs a
   one-line AWS policy grant the user must authorize (classifier blocks the assistant from IAM/SES
   mutations, same as the ECR repo). Optionally also change `emailService.sendAdminAlert`'s
   hard-coded recipient.
2. **Git tags:** `tabular-diffusion-training-v1` (cancelled run) + `-v2` (successful build) are
   pushed to origin; leave or delete `v1` per preference.
3. **Repo bloat (latent):** the 1.2GB committed `galaxy_ai_tools.db` + `docs/*.npz` make a full
   `actions/checkout` impractical — every image-build workflow should adopt the sparse+blob-filter
   pattern, or the data should move out of git history (larger, cross-cutting; not done here).

---

## 7. Commit / artifact index

| Thing | Ref |
|---|---|
| UI polish (E/F) + central i18n | `9fcdea34ba` |
| Chat-prose ID rule | `aebf2f5b4c` |
| Tabular diffusion method (backend+UI+CI+tests) | `9228b39e73` |
| CI sparse-checkout fix | `6c4d194b9f` |
| PR #341 merged tip | `53dabc29b3` |
| GPU image | `…/biomate/tabular-diffusion-training:latest` (`sha-6c4d194b9fde`) |
| Tags | `tabular-diffusion-training-v1` (cancelled), `-v2` (built) |
| Dev state | `9228b39e73`, full sync, healthy |
