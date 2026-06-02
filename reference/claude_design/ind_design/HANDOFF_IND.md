# BioMate IND Report — Claude Code Handoff

**Date:** 2026-05-16
**Prototype:** `BioMate IND Report.html` + `ind/`
**Target route:** `/ind-report` (new top-level page; companion to the existing `/drug-discovery-cro` CRO compliance workspace)
**Spec:** `uploads/20260504_IND_PRODUCT_UI_REQUIREMENTS.md`

This document covers (1) the file map and what each file does, (2) the API contracts the prototype implies, (3) the customer-feedback loop wiring from Appendix B, and (4) a test plan with prioritised acceptance criteria. The CRO compliance handoff (`HANDOFF_CRO.md`) is unchanged and still authoritative for the existing DMTA workspace.

---

## 1. File map (prototype → production)

### Entry point

| Prototype | Ports to |
|---|---|
| `BioMate IND Report.html` | `frontend/client/src/pages/ind-report/IndReportPage.tsx` — new route registered at `/ind-report` |

The prototype's `App` component covers: shell layout, knob state, modal routing, tweaks mounting, audit/settings overlay portals. In production:
- Replace knob state with React Query + URL state (`?project=p-bm0042`).
- Replace `localStorage` knob persistence with the backend (`GET /api/ind-report/projects/:id`).
- Replace the `IndTweaks` panel with nothing; it is dev-only.

### Components

| Prototype | Ports to | Notes |
|---|---|---|
| `ind/LeftNav.jsx` | `IndLeftNav.tsx` | shadcn `NavigationMenu` + `Badge` for region chips. Status dots → `<span>` with `bg-*-500`. |
| `ind/Steps.jsx` | One file per step: `Step1ProjectSetup.tsx`, `Step2Admet.tsx`, `Step3Pbpk.tsx`, `Step4Leads.tsx`, `Step5Document.tsx`. The shared `StepShell` becomes `<PipelineStep>` | Reuse existing `Collapsible` from shadcn. |
| `ind/DocPanel.jsx` | `IndDocViewer.tsx` + `DocSection.tsx` + `CitePopover.tsx` + `RegenerateModal.tsx` + `VersionHistory.tsx` | Replace `contentEditable` with **TipTap** editor (see Appendix B wiring below). |
| `ind/Overlays.jsx` | `IndSignOverlay.tsx`, `IndAuditOverlay.tsx`, `IndEmptyState.tsx` | Sign overlay must trap focus + announce on screen readers. |
| `ind/IndTour.jsx` | Optional. Use `@reactour/tour` or `shepherd.js` if a production tour is desired. The 24-step script translates 1:1. |
| `ind/data-ind.js` | Delete. Replaced by API responses. |
| `ind/styles-ind.css` | Merge into `styles/ind-report.css` or convert to Tailwind utilities. Region-chip colors should become CSS variables on `:root` to match the existing BioMate design tokens (`reference-design.css`). |
| `cro/CroIcon.jsx` | Replace with `lucide-react`. Mapping below. |
| `cro/primitives.jsx` | Replace with shadcn equivalents (`RegChip → Badge`, `Callout → Alert`, `Modal → Dialog`, `Toast → useToast`). |

#### `CroIcon` → `lucide-react` mapping

| CroIcon name | lucide-react |
|---|---|
| `check`, `checkCircle` | `Check`, `CircleCheck` |
| `x`, `xCircle` | `X`, `CircleX` |
| `warn` | `TriangleAlert` |
| `info` | `Info` |
| `chevronRight`, `chevronDown`, `chevronLeft` | `ChevronRight`, `ChevronDown`, `ChevronLeft` |
| `shield` | `Shield` |
| `download`, `upload` | `Download`, `Upload` |
| `signature` | `Signature` |
| `eye` | `Eye` |
| `file` | `FileText` |
| `external` | `ExternalLink` |
| `refresh` | `RefreshCw` |
| `plus` | `Plus` |

---

## 2. State model (per project)

The prototype carries this state in `knobs`; in production it should be split between server (project) and client (UI):

```ts
// Server-side (persisted)
type IndProject = {
  id: string;                            // p-bm0042
  molecule: string;
  target: string;
  indication: string;
  sponsor: string;
  regions: ('FDA' | 'EMA' | 'NMPA' | 'PMDA')[];
  status: 'signed' | 'in_progress' | 'blocked' | 'not_started';
  // Step-level state — drives the 5-step pipeline UI
  steps: {
    s1_setup: { complete: boolean; smiles_count: number; lead_smiles: string };
    s2_admet: { state: 'pending' | 'running' | 'complete' | 'failed';
                progress?: number;
                imported_from_chat?: { chat_run_id: string; ts: string };
                summary?: { pass: number; total: number };
                results_url?: string; };
    s3_pbpk:  { state: 'pending' | 'running' | 'complete' | 'failed';
                metrics?: { cmaxWithin2: number; aucWithin2: number; afe: number; aafe: number };
                ema_pass: boolean;
                fail_reason?: string; };
    s4_leads: { state: 'pending' | 'complete';
                ranking?: LeadRow[];
                in_domain: number;
                out_of_domain: number; };
    s5_doc:   { state: 'pending' | 'generating' | 'ready' | 'signed';
                version: number;
                sha256: string;
                generated_at: string;
                characters: number;
                signed_by?: string;
                sig_id?: string;
                signed_at?: string;
                sections: SectionCoverage[]; };
  };
  // Audit findings + chain — populated post-generation
  audit: {
    findings: AuditFinding[];
    chain_records: number;
    chain_valid: boolean;
    last_verified_at: string;
  };
};

// Client-side (UI-only)
type IndUiState = {
  activeProjectId: string;
  expandedSteps: Record<string, boolean>;
  region: 'FDA' | 'EMA' | 'NMPA' | 'PMDA' | 'ALL';
  showSign: boolean;
  showAudit: boolean;
  showVersions: boolean;
  showSettings: boolean;
};
```

---

## 3. API contract (full)

All under `/api/ind-report/`. JWT bearer auth. Regulated endpoints (🔒) require eSig when `BIOMATE_ESIG_REQUIRED=1`.

### Project management

| Method | Path | Returns | Notes |
|---|---|---|---|
| `GET`  | `/projects` | `IndProject[]` | List user's projects |
| `POST` | `/projects` | `IndProject` | Create from `{ molecule, target, indication, sponsor, regions, compounds[] }` |
| `GET`  | `/projects/:id` | `IndProject` | Full state for active project |
| `PATCH`| `/projects/:id` | `IndProject` | Edit project metadata; triggers downstream invalidation if regions change |
| `DELETE`| `/projects/:id` | `204` | Soft-delete only; signed versions are preserved |

### Pipeline steps (wraps existing drug-discovery workflows)

| Method | Path | Notes |
|---|---|---|
| `POST` | `/projects/:id/run/:step` | Dispatch step workflow. `:step` ∈ `admet \| pbpk \| leads \| document`. Returns `{ run_id, sse_url }`. |
| `GET`  | `/projects/:id/admet` | ADMET table rows + summary + `imported_from_chat` flag |
| `POST` | `/projects/:id/admet/wetlab` 🔒 | Multipart: NTP/NDA PDF or CSV. Auto-extract overrides predictions. |
| `GET`  | `/projects/:id/pbpk` | Qualification metrics + per-drug fold-error table |
| `GET`  | `/projects/:id/leads` | Ranked compound list with AD status |
| `POST` | `/projects/:id/generate` 🔒 | Trigger document generation. Returns `{ version, sha256, generated_at, sections }`. |
| `GET`  | `/projects/:id/document` | Document sections + audit findings (paginated by section) |
| `GET`  | `/projects/:id/document/versions` | All versions, including superseded |
| `GET`  | `/projects/:id/document/download?format=docx\|md` | DOCX or Markdown bundle |
| `POST` | `/projects/:id/sign` 🔒 | eSig + freeze. Body: `{ totp_token, meaning_text, reviewer_title, reviewer_credentials, review_scope }`. Returns `{ sig_id, signed_at, sha256_frozen, signed_pdf_url }`. |
| `GET`  | `/projects/:id/audit` | Findings + chain status. Same shape as `cro/audit` for consistency. |

### Server-Sent Events

| Method | Path | Streams |
|---|---|---|
| `GET` | `/projects/:id/events` | `{ step: 's2_admet', state: 'running', progress: 80 }`, `{ step: 's5_doc', section: '2.6.1.3', state: 'ready', body_md: '…' }`, `{ audit_findings_added: [...] }` |

### Cross-product handoff (chat ↔ IND)

| Method | Path | Notes |
|---|---|---|
| `GET` | `/projects/:id/from-chat?chat_run_id=…` | Server: if the user passes a chat workflow run ID, hydrate Step 2 with those results. Sets `imported_from_chat` flag. |
| `POST`| `/projects/:id/discuss-in-chat` | Returns a deep-link to the main BioMate chat with the campaign context pre-loaded. |

**Chat-side chip** (lives in the main chat workflow result panel, not in the IND Report):
```
<Alert variant="default">
  ✓ ADMET screening complete — 8/12 compounds passed all gates
  <Button onClick={() => router.push(`/ind-report?from_chat=${runId}`)}>
    → Generate IND §2.6 report from these results
  </Button>
</Alert>
```
Trigger conditions per spec:
- `predict_admet_properties` workflow completes with ≥2 compounds
- `pbpk_simulation` workflow completes
- user message matches `/herg|dili|admet/i` and context is drug-discovery
- user message matches `/\b(IND|regulatory|submission|CTD)\b/i`

### Customer feedback loop (Appendix B)

These are NEW endpoints — not in the existing `/api/drug-discovery/` namespace.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/projects/:id/edit` | Capture paragraph edit. Body: `{ paragraph_id, section_id, original_text, edited_text, prompt_context }`. Backend writes to `data/regulatory_training/dpo/customer_pairs.jsonl`. |
| `POST` | `/audit/:finding_id/dismiss` | Capture dismissal. Body: `{ reason: 'na' \| 'done' \| 'accept' \| 'disagree' }`. Writes to `checker_feedback.jsonl`. |
| `POST` | `/citations/suggest` | Customer citation suggestion. Body: `{ guideline_id, why_applies, paragraph_id, also_for_biomate: boolean }`. |
| `POST` | `/sections/:section_id/regenerate` | Now accepts `{ instruction?: string }`. The instruction is appended to the section system prompt for that regeneration only. |
| `GET`  | `/feedback/queue` | Internal — review queue for the BioMate regulatory science team. Not customer-facing. |
| `GET`  | `/active_adapter` | Returns `{ adapter_name: 'regulatory_llm_v6' | 'regulatory_llm_v6_<org_id>_lora', is_customer_specific: boolean }`. |

---

## 4. Customer feedback loop — implementation wiring

### B2 · Edit tracking (TipTap → DPO pair)

In production, replace the prototype's `contentEditable` paragraph with **TipTap** Editor. Wire two transactions:

```ts
const editor = useEditor({
  extensions: [
    StarterKit,
    ParagraphIdExt,  // custom — attaches data-pid="2.6.6.repeat-dose-7"
    EditTrackerExt,  // custom — see below
  ],
});

// EditTrackerExt — debounced 5s after last keystroke, computes diff
onSave(editedText, paragraphId) {
  const original = ORIGINAL_BODIES[paragraphId];
  const diffSize = levenshtein(original, editedText);
  if (diffSize <= 5) return;  // whitespace-level edit

  // ONLY post if the user has consented (Settings → Contribute edits)
  if (!getPrivacySettings().contributeEdits) return;

  fetch(`/api/ind-report/projects/${projectId}/edit`, {
    method: 'POST',
    body: JSON.stringify({
      paragraph_id: paragraphId,
      section_id: paragraphId.split('.').slice(0, 3).join('.'),
      original_text: original,
      edited_text: editedText,
      prompt_context: getPromptContextFor(paragraphId),
    }),
  });
}
```

The UI signal is a small italic suffix appended via CSS (`p[data-edited="true"]::after { content: ' ✎ edited — saved for model improvement' }`). Do **not** show a confirm dialog.

**PII stripping** happens server-side: drug names, study IDs, sponsor names are masked before the row enters `customer_pairs.jsonl`.

### B3 · Dismissal-reason picker

Already designed as an inline picker beneath the dismissed finding. Production wiring:

```ts
function dismissFinding(findingId: string, reason: DismissReason) {
  fetch(`/api/ind-report/audit/${findingId}/dismiss`, {
    method: 'POST',
    body: JSON.stringify({ reason }),
  });
  // Optimistic: mark the finding as dismissed in local state
}
```

The four reason codes map directly to checker-rule refinement candidates. Aggregated patterns (e.g. 12 customers dismissing "missing hERG" on topical products) surface in the internal review queue.

### B4 · Citation suggest

Two-button popover. Both buttons POST `/citations/suggest`, but `also_for_biomate: true` is what enters the corpus extension queue.

### B5 · Regenerate-with-instruction

Replace the existing `[Regenerate]` button with a dropdown. Selecting "with instruction" reveals a textarea. The instruction is passed via:

```ts
POST /api/ind-report/sections/2.6.6.3/regenerate
{ "instruction": "Use more conservative language about the Ames equivocal finding" }
```

The instruction is appended to the section's system prompt for this regeneration only. If the customer doesn't edit further within 60 seconds, the `(instruction, before, after)` tuple is stored as a **prompt-tuning signal**. This 60-second timer lives client-side; emit a final telemetry event on the 60s mark or on next-save, whichever comes first.

### B6 · Privacy toggle

Single toggle in Project Settings: **Contribute edits to model improvement**.
- Default `ON` for free tier
- Default `OFF` for paid tier (explicit opt-in)
- Stored on the project, not the user (per-project sensitivity)
- Read by the EditTrackerExt before posting any edit

### B7 · Active-model adapter badge

Show only when `GET /active_adapter` returns `is_customer_specific: true`. Renders as a small pill in the top bar:

```
◆ Active model: BioMate v6 — Customized for {Org Name}
```

The backend's `_resolve_adapter_path` checks for `regulatory_llm_v6_{org_id}_lora` via the `X-BioMate-Org-Id` header.

---

## 5. Design system notes

### Region chip colours (in styles-ind.css; should match `reference-design.css`)
- FDA → blue
- EMA → purple
- NMPA → red
- PMDA → orange

### Severity colours
- CRITICAL → red
- MAJOR → amber
- MINOR → yellow
- INFO → gray

### Typography
- Section headers: 15px medium (Inter)
- Document body in viewer: 14px regular — must read as a **document**, not UI
- Monospace (`JetBrains Mono`): SHA-256, Sig IDs, ICH section numbers (`§2.6.1.2`), timestamps

### Component reuse mapping (existing CRO components on `/drug-discovery-cro`)
- `DrugDiscoveryAuditViewer` — reuse for "View full audit log →" link inside the IND audit overlay
- `EsigSignModal` — extend with `reviewer_title` / `reviewer_credentials` / `review_scope` fields (just added)
- Existing audit chain primitives — reuse end-to-end

---

## 6. State machine (per step)

```
Step 2 ADMET:    pending → (run) → running → complete|failed
                          → (import_from_chat) → complete

Step 3 PBPK:     pending → (run) → running → complete (pass)
                                         → blocked (fail, downstream gates locked)

Step 4 Leads:    pending → (run) → complete  [no failure state — deterministic optimizer]

Step 5 Document: pending → (generate) → generating → ready
                 ready → (sign) → signed [version frozen]
                 signed → (new version) → pending → … → ready_v(n+1) [supersedes signed]
```

Notes:
- A PBPK failure **blocks** Step 5 generation but does NOT block Steps 4 (lead selection is independent).
- A signed Step 5 is immutable. Edits trigger a new version; the previous one stays in the audit chain.
- Steps 2-4 can be re-run independently; each re-run re-invalidates downstream steps (regenerated document, new audit pass).

---

## 7. Section coverage logic

Server determines coverage per section from data availability:

| Section | Full when | Partial when | None when |
|---|---|---|---|
| §2.6.1.x | Always full (computational-only is acceptable here) | — | Step 4 not run |
| §2.6.2 | PBPK qualification passed | PBPK qualification failed (limitation statement included) | Step 3 not run |
| §2.6.3 | DILI + Ames predicted + (optionally) wet-lab confirmatory | Computational only | Step 2 not run |
| §2.6.4 | Always full (computational predictions are sufficient) | — | Step 2 not run |
| §2.6.5 | Measured CL_int provided | Predicted CL_int only | Step 3 not run |
| §2.6.6 | GLP in vivo data provided | Computational only | Step 2 not run |

§2.6.5 and §2.6.6 are the wet-lab-dependent sections — they will be "Partial" for any pre-IND screening campaign.

---

## 8. Test plan

### Priority 0 (must pass for ship)

| ID | Test | Acceptance |
|---|---|---|
| IND-P0-1 | Create project, upload SMILES, run full pipeline | All 5 steps complete; document reaches `ready` state; audit returns ≤2 MINOR; no CRITICAL |
| IND-P0-2 | Sign with TOTP | Signed state visible in step 5, doc panel footer, version chip. SHA-256 frozen. Cannot edit document afterward (TipTap enters read-only). |
| IND-P0-3 | Generate v2 after v1 signed | v2 appears in version history; v1 marked superseded; v1 signature record preserved (returned by `GET /document/versions`). |
| IND-P0-4 | PBPK fail | Step 3 shows red banner; Step 5 generation blocked; §2.6.2 includes limitation statement when next generated. |
| IND-P0-5 | Multi-region (FDA + EMA + NMPA + PMDA) | All 4 region tabs renderable in doc viewer; NMPA adds GLP declaration paragraph; PMDA adds ethnic bridging table. |
| IND-P0-6 | Chat → IND handoff | Open `/ind-report?from_chat=<run_id>` → Step 1 + Step 2 pre-filled; "Imported from chat" chip visible; Step 2 ADMET shows cached results, not a fresh run. |
| IND-P0-7 | Wet-lab override | Upload NTP PDF → measured values replace predictions for matching compounds; §2.6.6 coverage flips Partial → Full. |

### Priority 1

| ID | Test | Acceptance |
|---|---|---|
| IND-P1-1 | Audit dismissal | Click Dismiss on a MINOR → reason picker appears → choose reason → POST `/audit/:id/dismiss`. Finding marked dismissed. Reason recorded with finding. |
| IND-P1-2 | Citation suggest | Click `[+]` near a citation → form appears → choose "Also suggest for BioMate" → POST `/citations/suggest`. |
| IND-P1-3 | Regenerate with instruction | Click `[Regenerate ▾]` → enter instruction → POST `/sections/:id/regenerate` with `instruction` param. Section text changes. |
| IND-P1-4 | Edit-tracking opt-out | Settings → "Contribute edits to model improvement" off → edit a paragraph → no POST to `/projects/:id/edit`. |
| IND-P1-5 | Adapter badge | Backend returns `is_customer_specific: true` → "Active model: BioMate v6 — Customized for {Org}" appears in top bar and Settings. |
| IND-P1-6 | Audit chain integrity | Manually corrupt one audit row in DB → `GET /audit` returns `chain_valid: false` → audit panel header flips to red. |

### Priority 2 (polish)

| ID | Test | Acceptance |
|---|---|---|
| IND-P2-1 | Mobile (≤1024px) | Right panel collapses to floating "View Document" button; bottom sheet opens on tap. |
| IND-P2-2 | Reference compounds | Empty state → click "Ibuprofen (all-clear)" → full pipeline runs in ~2 min with seeded data. |
| IND-P2-3 | Version diff | Two signed versions → user can request a diff view (future, not in v1). |
| IND-P2-4 | Tour replay | Tutorial button in top bar opens 24-step tour. Last step "Start recording" closes overlay. |
| IND-P2-5 | Section loading | While Step 2 is running, §2.6.1.3 in doc viewer shows skeleton "§2.6.1.3 — awaiting ADMET results" until SSE delivers content. |

---

## 9. Security checklist

- [ ] TOTP secret returned **once only** on first eSig enrollment — never again.
- [ ] Hash-chain verification runs on every audit mount, with a 30-second cache to avoid re-hashing on tab switch.
- [ ] Edit-tracking is **gated** on the privacy toggle; the toggle defaults differ by tier (free=on, paid=off).
- [ ] PII stripping (drug names, study IDs, sponsor) happens server-side before edits enter `customer_pairs.jsonl`.
- [ ] Reviewer credentials are recorded in the frozen document, not just the audit row.
- [ ] DOCX bundle includes the signed audit packet as a supplementary file.

---

## 10. Known prototype simplifications (fix on port)

| Item | Today | Fix |
|---|---|---|
| Paragraph editing | `contentEditable` | TipTap with `data-pid` stable IDs + `EditTrackerExt` |
| SMILES structure rendering | Text only ("CC(=O)Nc1…") | RDKit.js / Kekule.js 2D renderer; click compound row → side panel with structure + raw prediction + TDC confidence |
| Doc panel SSE | Static seeded text | SSE-driven section-by-section streaming with skeleton placeholders |
| Wet-lab upload | Button only | Multipart upload + auto-extract pipeline (`POST /admet/wetlab`) |
| Audit overlay | Inline mock | Wire to real `GET /audit` + reuse `DrugDiscoveryAuditViewer` for "View full audit log →" |
| Version diff | Not implemented | Future v1.1 |
| ChimeraX-style structure preview | Not in IND Report | Could embed for §2.6.3 toxicology results |

---

## Files to ship in this PR

```
frontend/client/src/pages/ind-report/
├── IndReportPage.tsx           — route entry
├── components/
│   ├── IndLeftNav.tsx
│   ├── PipelineStep.tsx        — shared step shell
│   ├── Step1ProjectSetup.tsx
│   ├── Step2Admet.tsx
│   ├── Step3Pbpk.tsx
│   ├── Step4Leads.tsx
│   ├── Step5Document.tsx
│   ├── IndDocViewer.tsx
│   ├── DocSection.tsx
│   ├── CitePopover.tsx
│   ├── RegenerateModal.tsx
│   ├── VersionHistory.tsx
│   ├── IndSignOverlay.tsx
│   ├── IndAuditOverlay.tsx
│   ├── IndEmptyState.tsx
│   ├── IndSettings.tsx
│   └── ChatHandoffChip.tsx     — lives in chat workflow result panel
├── hooks/
│   ├── useIndProject.ts        — React Query wrapper
│   ├── useIndSSE.ts            — SSE subscription
│   ├── useEditTracker.ts       — TipTap + debounced /edit POST
│   └── usePrivacySettings.ts
├── api/
│   └── ind-report.ts           — typed fetch wrappers for all endpoints in §3
└── types.ts                    — IndProject, IndUiState, AuditFinding, LeadRow, etc.

backend/services/regulatory_llm/
├── feedback/                   — NEW
│   ├── customer_pairs.jsonl    — DPO pairs from B2
│   ├── checker_feedback.jsonl  — dismissal reasons from B3
│   ├── citation_extensions.jsonl — citation suggestions from B4
│   └── regulatory_science_overrides.yaml — checker refinements
├── api.py                      — add the new endpoints from §3
└── pii_strip.py                — NEW; mask drug names, sponsor, etc.
```

---

*End of handoff. Questions: contact the BioMate frontend team or open an issue in `biomate/ind-report` tagged `handoff-q`.*
