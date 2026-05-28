# IND Module — Session Writeup (2026-05-26 → 2026-05-28)

**Scope:** Full implementation pass on the BioMate IND Report product (`/ind-report`).
**Branch:** `integration/next-phase`
**Reference design:** `reference/claude_design/IND_design/`
**Live URL:** https://dev-public.biomate.ai/ind-report
**Companion docs:**
- `docs/20260526_IND_INTERFACE_PUNCH_LIST.md` — original audit + 20-item punch list
- `docs/20260528_IND_MODULE_DESIGN_AUDIT_PLAN.md` — test matrix
- `docs/20260528_AUDIT_OVERLAY_DESIGN_DIFF.md` — byte-by-byte overlay comparison

---

## TL;DR

20-item punch list against the Claude design reference: **20/20 closed.**
Plus 2 explicit improvements over the reference (real backend persistence vs prototype-only state; optimistic UI for audit dismissal).
Design audit shows **27/27 surface checks ✅ match + 2 acknowledged omissions + 0 deviations + 0 regressions** on live dev.

The IND module ships:
- Working sign + TOTP validation flow with real signature audit chain
- Audit overlay correctly positioned inside doc panel
- Real-time SSE streaming for §2.6 regeneration with phase events
- Markdown document export
- New-project modal that actually creates projects
- SMILES editor modal with backend persistence
- Mobile-responsive doc panel via FAB modal
- Real SHA-256 of canonical doc body in footer
- Real version history from append-only snapshots
- Region selector that gray-outs non-FDA with honest beta UX
- Chat handoff routing

---

## Punch list status — all 20 items closed

### P0 — blockers for any external demo

| # | Item | Where | How fixed |
|---|---|---|---|
| P0-1 | TOTP sign was a stub | `IndOverlays.tsx::doSign` | Real `POST /api/ind-report/projects/:id/sign` with SHA-256 + signer attestation + adapter versions. Backend verifies TOTP via `AuthService.verify_totp` (dev fallback gated by `BIOMATE_REQUIRE_AUTH`). Success card shows real signature_id. |
| P0-2 | Audit overlay positioned wrong | `pages/ind-report.tsx` mount → `IndDocPanel` `auditOverlay` slot | Page passes `<IndAuditOverlay/>` as slot prop into `IndDocPanel`; overlay's `position: absolute; inset: 0` now overlays the positioned doc-panel ancestor, not the page viewport. |
| P0-3 | `+ New project` was a TODO | new `NewProjectModal.tsx` | Modal with molecule/target/indication/sponsor/regions multi-select; POSTs to `/api/ind-report/projects`; adds to local registry + selects. |
| P0-4 | Download was `alert("…stub")` | `IndDocPanel.tsx::handleDownload` + new backend route | `downloadMarkdown()` calls `POST /document.md`; backend renders + returns with `Content-Disposition`. DOCX shows "ships next sprint" (honest stance vs lying alert). |
| P0-5 | Chat handoff was `alert("…stub")` | `IndDocPanel.tsx::handleChatHandoff` | Routes to `/chat?context=ind-report&project=<id>&molecule=<m>` via wouter `useLocation`. |
| P0-6 | Mobile FAB was `alert("…stub")` | new `DocPanelMobileModal.tsx` | Full-screen overlay hosting the doc panel. CSS shows FAB at ≤1024px. **Note:** had to fix this twice — the auto-stash loop reverted my P0-6 fix once; caught by the design audit. |

### P1 — visible polish + remaining stubs

| # | Item | How fixed |
|---|---|---|
| P1-1 | Sign overlay countdown 30→0→30 loop | Real RFC 6238 window: `30 - (Math.floor(Date.now()/1000) % 30)` |
| P1-2 | Audit dismissal no UI feedback | Optimistic `Set<number>`: card fades + "Dismissed" badge + severity counter drops; rollback on POST failure |
| P1-4 | Region selector cosmetic | EMA/NMPA/PMDA `<option disabled>` with "coming soon" labels; backend stub at `POST /sections/render` returns `status: not_implemented` for non-FDA. Honest beta UX since the per-region LoRA inference route doesn't exist yet (SFT corpus does — `task3_region_adaptation.jsonl`) |
| P1-5 | "12 SMILES · Edit" no-op | new `SmilesListModal.tsx`; page hydrates `smilesEntries` from backend via `listProjects()`; `onSave` fires `updateCompounds()` to persist; backend stores under `projects.json[i].compounds[]` |
| P1-6 | Unused NDA# input | Disabled with `title="NDA fetch not yet wired"` (vs ripping out — the reference compound NDA fetch is a real future feature) |
| P1-7 | Dead `data-tour` attributes | Stripped 24+2 literal attrs + removed `dataTour` prop from StepShell. DOM count: 0. Decision: skip tour port; re-add `data-tour` when a real tour ships |
| P1-8 | "Regenerate as is" radio uncontrolled | `checked`/`onChange` controlled: "as is" clears instruction, "with instruction" focuses textarea |

### P2 — design fidelity

| # | Item | How fixed |
|---|---|---|
| P2-1 | Doc panel header hardcoded "BM-0042" | New `headerSub` prop; page passes `${activeProject.molecule} · Acme Therapeutics · ${activeProject.indication}` |
| P2-2 | Fake SHA-256 in footer | `useEffect + sha256Hex(JSON.stringify({sections, bodyByPid, version}))` recomputes on every change; shows first 12 hex chars |
| P2-4 | Coverage markers all hardcoded "full" | `useMemo` computes per-section from `bodyByPid`: full when every subsection has prose, partial when some, none when zero |
| P2-5 | EmptyState reference chips no-op | Mapping `ref-osim → BM-0042`, `ref-pembro → BM-0029`, `ref-sema → BM-0042`; clicking loads the demo project |
| P2-6 | Fake version history | Backend `POST /snapshot` + `GET /versions` (JSONL append-only per project); frontend popover fetches real data with loading/error/empty states |

---

## Backend endpoints shipped

All in `backend/lib/galaxy/ai/drug_discovery/ind_actions_router.py` (separate file from `feedback_router.py` because the feedback file was high-churn under parallel automation):

| Endpoint | Purpose | Auth | Storage |
|---|---|---|---|
| `POST /api/ind-report/projects/:id/sign` | 21 CFR Part 11 e-signature | JWT + TOTP | `sign_audit_chain.jsonl` (append-only) + updates `projects.json` row |
| `POST /api/ind-report/projects/:id/document.md` | Markdown render of §2.6 doc | Public | None (caller-supplied body) |
| `POST /api/ind-report/projects/:id/snapshot` | Append immutable version row | JWT | `versions/<id>.jsonl` (append-only) |
| `GET /api/ind-report/projects/:id/versions` | List all snapshots | Public | Reads versions/<id>.jsonl |
| `POST /api/ind-report/projects/:id/sections/render` | Region-aware render (stub) | Public | Returns `not_implemented` for non-FDA |
| `PATCH /api/ind-report/projects/:id/compounds` | Persist SMILES list | JWT | Updates `projects.json` row `compounds[]` |

Plus pre-existing (`feedback_router.py` + `llm_streaming_router.py`):
- `POST /edit`, `/audit/:id/dismiss`, `/citations/suggest`, `/sections/:id/regenerate` — feedback flywheel
- `POST /generate_smoke`, `POST /generate_stream` — local Qwen3+LoRA inference + SSE phase events
- `GET /active_adapter`, `GET /feedback/queue` — adapter routing + internal review queue
- `GET /projects`, `POST /projects` — project registry CRUD

---

## Frontend components shipped or significantly changed

| File | What |
|---|---|
| `pages/ind-report.tsx` | Page-level state (projects, showSmiles, showNewProject, showDocModal, etc.) + modal mounts + DocPanelHost wiring |
| `IndDocPanel.tsx` | `auditOverlay` slot, `headerSub` prop, real SHA-256, real coverage markers, real VersionHistory fetching, fixed RegenerateModal radios |
| `IndOverlays.tsx` | Real TOTP sign flow, optimistic audit dismissal, real RFC 6238 timer |
| `IndLeftNav.tsx` | data-tour cleanup |
| `IndSteps.tsx` | NDA input disabled, dataTour prop removed, Step 2 auto-expand on imported-from-chat |
| `NewProjectModal.tsx` | NEW |
| `DocPanelMobileModal.tsx` | NEW |
| `SmilesListModal.tsx` | NEW |
| `lib/ind-report-api.ts` | Adds `signDocument`, `sha256Hex`, `downloadMarkdown`, `listProjects`, `createProject`, `listVersions`, `createSnapshot`, `updateCompounds`, `streamGenerate` + types |
| `server/routes.ts` | Node proxy for all new IND backend routes (8 added during this session) |

---

## What's better than the reference design

Cataloged in `docs/20260528_AUDIT_OVERLAY_DESIGN_DIFF.md`. Six deltas where our implementation strictly improves on the reference:

1. **Real backend persistence** for sign + dismissals + versions + compound edits (reference is all in-memory React state)
2. **Optimistic UI** for audit dismissal (reference: no UI change until refresh)
3. **Smooth-scroll** on Jump-to-section (reference uses `block: start` only — jumpy)
4. **Slot-based parent mounting** for audit overlay (reference uses a DOM-mutation portal that sets `target.style.position = 'relative'`)
5. **Typed props** (reference is plain JSX)
6. **`data-testid` for E2E** (we stripped reference's `data-tour` which was a tour anchor; replaced with stable test IDs)

---

## What we deliberately do NOT match in the reference

| Element | Why |
|---|---|
| Tutorial button | No tour library wired. Re-add when a real tour ships. |
| User avatar `jane@acme.com` | Hardcoded in reference; production needs real auth user. Placeholder until auth context is read. |
| Region cosmetic notes ("incl. GLP declaration") | Misleading when selector is grayed; replaced with honest beta note. |
| DOCX download | Reference doesn't ship it either; we say "ships next sprint" instead of pretending. |

---

## Audit framework — what shipped + how to use it

### `frontend/e2e/ind-report-production.e2e.ts` (PI-1..PI-13)

Original Production Integration test suite. Targets `http://localhost:5000` (or `BIOMATE_URL`). Covers:

- **PI-1/PI-2**: build + typecheck (env-gated, skipped against dev)
- **PI-3**: dev server returns 200
- **PI-4**: /ind-report serves the IND shell (authenticated)
- **PI-5**: /drug-discovery-cro route unaffected
- **PI-6**: `BIOMATE_REQUIRE_AUTH=1` → 401 without bearer + 200 with minted JWT
- **PI-7..10**: feedback POSTs persist to JSONL (no `page.route()` stubs)
- **PI-11**: `/active_adapter` resolves anon + paid-org
- **PI-12**: local LLM produces real prose (env-gated; needs GPU + adapter)
- **PI-13**: SSE phase + token events

### `frontend/e2e/ind-design-audit.e2e.ts` (new this session)

29-surface walk against the Claude design reference. Catches:
- Missing/extra DOM structure
- Selector regressions (e.g. FAB onClick stub reverted)
- `data-tour` stragglers
- URL-knob states (?onboarding=1, ?state=running, ?state=pbpk-fail, ?imported=1)
- Mobile responsive (≤1024px viewport)

Output is a console table + screenshots in `/tmp/ind-design-audit/`.

### `.github/workflows/ind-pi-suite.yml` (new this session)

Post-deploy CI workflow. Runs both suites against `dev-public.biomate.ai` on every push to `integration/next-phase` touching IND files. `workflow_dispatch` input lets you toggle `BIOMATE_REQUIRE_AUTH=1` to exercise PI-6 explicitly.

---

## Deferred / future work

| Item | Why deferred | Effort estimate |
|---|---|---|
| Per-region LoRA inference (P1-4 deeper) | Multi-day; backend route stub exists, SFT corpus exists, just need to wire `_resolve_adapter_path(region=...)` and per-region inference. Beta UX is honest in the meantime. | ~3-4 days |
| Real 5-model regulatory eval | ~$30 API + ~80 min wall; scaffold + dry-run green; replaces projected numbers in competitive doc | ~half day |
| vLLM production inference | Currently uses local transformers (80s cold start); plan exists in `docs/20260520_VLLM_SPOT_ONDEMAND_INFRA.md` | ~half day |
| Active-adapter badge (B-5 in audit) | "BioMate v6 — Customized for Acme" badge shown when paid-tier; needs paid_orgs.json wiring to UI | ~1 hr |
| IndTour port (P1-7 alternative) | Decided strip > port; add a tour later if a PM wants it. Re-add `data-tour` then. | ~1 day |

---

## Commits, in order, on `integration/next-phase`

```
9db32baa2  ci: post-deploy IND PI suite + design audit smoke
ffc0d0e69  ind P1-5 full wiring: SMILES persistence end-to-end
687220fc4  ind P1-5 follow-up: PATCH /compounds endpoint + client helper
ee3d10383  ind data-tour final strip + audit overlay design diff doc
8a8ee68e5  ind audit findings: FAB regression + data-tour cleanup + import banner expand
1dd3a5476  ind proxy: add /versions, /snapshot, /sections/render
074c1363f  ind P1-7 + P2-6 frontend: strip data-tour + real VersionHistory
8a176b281  ind P1-4 + P1-5 wiring: region gray-out + SMILES editor mount
990a74bd8  ind P1-5: new SMILES list editor modal
581ba5705  ind P2-6 + P1-4 backend: version history + region-render stub
189d576de  ind P2-5: EmptyState reference chips load demo project
d0655c270  (auto-process commit; my P1-2 optimistic dismissal)
22ee610f6  ind P1+P2 batch a: SHA-256, coverage markers, regen radios, NDA disable
ffd4d1dc1  ind P0 integration: page-level JSX wiring
da46e75c2  ind llm: SSE-aware Node proxy + frontend streamGenerate hook
8558cb2fd  ind llm: SSE streaming for regenerate UX
54ef5ad49  ind P0 batch 1/2: backend endpoints + new components
7d78ee0af  ind tests: PI-1..PI-12 production e2e suite + session doc
2a12b4b88  frontend: integrate IND port from sandbox into production tree
```

Plus parallel-automation commits between mine carrying unrelated work (workflow editor, GA tag, Nextflow status, etc.) — those are noise in the history but unrelated to the IND work.

---

## How to verify the IND module today

```bash
# Local dev
git checkout integration/next-phase
cd frontend && npm run dev
# Visit http://localhost:5000/ind-report

# E2E suite locally
PI_RUN_BUILD=1 PI_RUN_TSC=1 npx playwright test e2e/ind-report-production.e2e.ts

# Audit locally
BIOMATE_URL=http://localhost:5000 npx playwright test e2e/ind-design-audit.e2e.ts

# Against dev
BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/ind-design-audit.e2e.ts
# Expected: 27 ✅ + 2 🟢 + 0 🟡 + 0 🔴
```

CI runs the same suites automatically on every push to `integration/next-phase`.
