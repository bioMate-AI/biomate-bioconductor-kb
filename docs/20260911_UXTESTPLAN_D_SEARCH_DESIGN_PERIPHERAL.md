# UX Test Plan — Cluster D · Design, Search & Peripheral (Upgrade + V2)

*2026-09-11. The UX companion to the functional plan
`docs/20260909_TESTPLAN_DESIGN_SEARCH_SIDEBAR.md`. This doc walks **every function**
in Cluster D on **all 7 rubric dimensions** (Journey · States · Visual · Honesty ·
Interaction · Responsiveness/a11y · Cross-version Δ), for **both** the **Upgrade**
(shipped, `dev-public.biomate.ai`) and **V2** (`data_centroid_design_v2` spec)
versions, using the master test-case shape
(`docs/20260911_UXTESTPLAN_MASTER_INDEX.md`).*

**Cluster D scope (per master index):**
- **Search & evidence** — v2 §01, §09 (retrieval transparency, citation panel, search answers)
- **Design & Generate** — v2 §05, §11 (all modalities, constraints composer, generation run, candidates, honest gating)
- **Reports / exports** (standalone), **Connectors**, **Billing + Settings** dialogs

> The **sidebar** is covered in **Cluster A** — the sidebar UCs in the earlier
> functional plan (`…_DESIGN_SEARCH_SIDEBAR.md §C`) are **out of scope here**.
> This doc focuses on search / design / reports / connectors / dialogs.

**Rubric rules inherited (do not restate per case):** no mocked APIs in any
live/E2E step (real backend, fixture `lifeifei163361@163.com`, bypass
`x-e2e-test-token: biomate-e2e-bypass-token-dev-only`); a **skip is a fail**
(record why, treat as untested — never "passed"); audit by screenshot vs the
cited v2 §; every v2 element cites its spec section.

---

## 0 · Version map & real-code determinability (read first)

| # | Surface | Real component (verified) | Route / mount |
|---|---------|---------------------------|---------------|
| S1 | Search & evidence | `components/citation-panel.tsx` (+ `.retrieval.test.tsx`, `.conflict.test.tsx`, `.evidence.test.tsx`, `.save-notes.test.tsx`) + `components/source-reader-pane.tsx` (+ `.test.tsx`) | **No standalone route.** `CitationPanel` is a **child** rendered inside the chat/answer surface (e.g. `workflow-artifact.tsx`). Returns `null` unless `citations.length>0 \|\| methodsSection \|\| workflow`. |
| S2 | Design & Generate | `components/design-generate/DesignGenerate.tsx` | `/design` (App.tsx, `AuthenticatedPageLayout`) |
| S3 | Reports / exports (standalone) | Order-sheet CSV in `DesignGenerate.tsx` (`buildOrderSheetCsv`/`dg-export-order`); BibTeX + Methods in `citation-panel.tsx`; **workflow report** editing lives in `v2/AfterRunReport.tsx` (Cluster B). Report-as-file object = **not built** (see §V2GAP). | inline / download blobs |
| S4 | Connectors | `components/connectors-dialog.tsx` + `components/connector-residency.tsx` | **Modal dialog** (opened from sidebar `button-connectors-nav`). NOT a page. |
| S5 | Billing | `pages/billing.tsx` | `/billing` route exists; **no sidebar entry links to it** (reach by URL). |
| S6 | Settings | `components/settings-dialog.tsx` | Dialog (opened from sidebar Settings; Cluster A). Tabs: profile/general/appearance/chat/data/notifications/privacy/security/advanced/api-keys. |

**Determinability flags (verified in code, load-bearing for the plan):**

1. **There is NO search-answer route/surface.** `grep` for `SearchAnswer` / `answer-surface` / `/answer` in `App.tsx`/`components`/`pages` → **0 hits**. The v2 §09 *answer-as-surface* (Spec 09 `SearchAnswer.jsx`) is **unbuilt**; the deployed evidence surface is the inline `CitationPanel`. Every "search answer" UC below is written against `CitationPanel`, with the v2 §09 delta flagged **[V2-NEW / UNBUILT]**.
2. **`retrieval` prop is spec-ready but NOT wired from any caller.** `RetrievalSource[]` + the `retrieval-transparency` section exist and are unit-tested (`citation-panel.retrieval.test.tsx`), but the increment doc (`docs/20260911_V2GAP…INCREMENT.md §Surface B`) states **no caller passes it** (no backend supplies per-source found/kept). Live/E2E therefore observes **honest-empty** (section absent); the section is only observable via the component test. Mark **[V2-NEW / spec-ready, not wired]**.
3. **Design run is HONESTLY GATED by modality.** `canRun = modality === "small_molecule"`. Peptide/protein: `dg-run` **disabled**, `dg-modality-unrunnable` amber note shows, `onRun` early-returns (`if (modality !== "small_molecule") return`). No fabricated peptide/protein shortlist. **[V2-NEW §11]**
4. **Connectors is a MODAL with 2 of 4 kinds.** `TabId = 'databases' | 'ai'`; the **Skills tab is commented out** (`connectors-dialog.tsx:65,524-526,626` — `/api/skills` returns 0). No MCP tab, no "Add a connector" flow. **[V2-NEW §Connectors partial]**
5. **Reports are read-only downloads, not file objects.** No report in the file tree, no chat-edit-with-diff, no versioning, no multi-format export — the single biggest v2 gap (`docs/20260909_V2GAP…md Surface A`). The one editable increment (Methods report Edit/Save) is in `v2/AfterRunReport.tsx` → **Cluster B**.
6. **`answer-make-instruction` is permanently disabled** (no write endpoint) — tooltip "coming soon". Its UX-pass = *stays honestly disabled*.
7. **Billing page has honest-empty states but no `data-testid`s** — assert on visible copy ("No on-demand usage this cycle", "No invoices found"), not testids.

**Rubric legend for the Δ tables:** ✅ present & honest · ⚠️ partial · ✖ absent · 🔒 honestly-gated/disabled.

---

# PART 1 — SEARCH & EVIDENCE (v2 §01, §09)

Component: `citation-panel.tsx` + `source-reader-pane.tsx`. Render guard: returns
`null` when `citations.length === 0 && !displayMethodsSection && !workflow`
(line 301). Preconditions assume a parent renders it with a non-empty `citations`
prop carrying `doi || pmid || title`.

> **Test-layer guidance (Search):** UC-D101–D109, D111–D116 are best as
> **component tests** with prop fixtures. **UC-D110 (save-to-notes SUCCESS/FAIL)
> MUST hit the real `POST /api/memory/projects/:id/knowledge`** per the no-mock
> rule — fixture account + real active project (success) and a not-owned project
> id (403/404 failure). The retrieval section (D107) is **only** component-testable
> today (not wired live — flag 2).

### Search › Panel collapse/expand + tool-count badge (v2 §01.3.2)
- **Journey:** answer renders → user sees a collapsed "Citations" header with a `{kept}/{total} tools` badge → clicks header → panel expands to Tool Citations / Methods tabs. 1 click to open.
- **Precondition / data setup:** `CitationPanel` mounted with 4 citations, 3 carrying doi/pmid/title; `isCollapsed` default (true).
- **Steps:** 1. Assert collapsed header: BookOpen icon + "Citations" + badge `3/4 tools`. 2. Click the `CollapsibleTrigger`. 3. Assert tabs "Tool Citations" + "Methods Section" appear.
- **Expected UX:** states=collapsed↔expanded animate via `Collapsible`, no stuck state; visual=chevron flips ChevronRight→ChevronDown, badge reads `{toolsWithCitations.length}/{totalTools} tools` (no "undefined"/NaN); honesty=badge counts only citations with doi/pmid/title (`toolsWithCitations`), not all; interaction=header is a real button, hover feedback; a11y=trigger keyboard-focusable, chevron conveys state.
- **Acceptance (UX-pass ⇔):** badge text = `3/4 tools`; content shows/hides on toggle; on all-untitled citations the citations tab shows "No citations available for tools in this workflow" (honest-empty), not a blank box.
- **Upgrade:** ✅ as above. **V2:** ✅ identical (§01 byte-identical old→v2). **Δ:** none.

### Search › Retrieval transparency — "How this was searched" (v2 §09) **[V2-NEW]**
- **Journey:** on an answer, above the source list, a "How this was searched" block shows one row per source with `found · kept` counts, a proportional bar, and a `N of M kept` summary chip — the user sees the *retrieval funnel* before the references.
- **Precondition / data setup:** **component test only** — `retrieval={[{name:"PubMed",found:214,kept:18},{name:"Europe PMC",found:96,kept:11},{name:"bioRxiv",found:40,kept:3}]}`, `isCollapsed={false}`. (Live: no caller supplies `retrieval` — flag 2 → section absent; that live absence is the honest-empty pass, not a bug.)
- **Steps:** 1. Assert `retrieval-transparency` present. 2. Assert `retrieval-source-PubMed` reads "214 found" + "18 kept"; one row per source. 3. Assert `retrieval-summary` = "32 of 350 kept" (sum: 18+11+3 of 214+96+40). 4. Bar width per row = `round(kept/found*100)%`.
- **Expected UX:** states=static (no async); visual=w-28 truncated source name, primary/60 bar, tabular-nums counts, "kept" bolded in foreground; honesty=**renders ONLY when real per-source counts supplied** — omitted entirely when `retrieval` absent/`[]`, and malformed rows (missing name / non-finite `found`/`kept`) dropped (never a fabricated "kept" derived from the citation list); interaction=read-only; a11y=numeric contrast adequate.
- **Acceptance (UX-pass ⇔):** all 6 `citation-panel.retrieval.test.tsx` assertions hold — rows render, per-source counts correct, summary = sum, honest-empty on omit AND on `[]`, malformed dropped (summary reflects only valid row "10 of 100 kept").
- **Upgrade:** ✖ absent — no retrieval-transparency UI. **V2:** ⚠️ **spec-ready but not wired** — UI + honesty contract present and unit-passing; no live data source, so live shows honest-empty. **Δ:** V2 adds the section (a UX improvement toward Spec 09) **but the improvement is only observable in the component test until a caller passes `retrieval`** — mark honestly as partial. Full §09 answer-surface (editable filter chips that re-derive, "what was dropped and why", claim-level lead labels, Boundary section, study/system/finding/strength disagreement table, two exits) = **✖ UNBUILT** (`INCREMENT.md §Surface B deferred`).
- **Known gap / deferred:** wiring `retrieval` from a live retrieval path (per-source found/kept) — deferred, would require fabricating counts otherwise (forbidden).

### Search › Conflict row — "Sources disagree" (v2 §01.3.2)
- **Journey:** when retrieval flags materially disagreeing findings, an amber "Sources disagree — N conflicting finding(s)" row shows above the source list; click expands both positions with their sources, side by side.
- **Precondition / data setup:** `conflicts=[{topic:"Effect at physiological dose", positions:[{claim,source},{claim,source}]}]`, panel expanded.
- **Steps:** 1. Assert `conflict-row` present with amber Flag icon + "Sources disagree — 1 conflicting finding". 2. Click. 3. Assert topic + each position's `claim` with "— <source>" render.
- **Expected UX:** states=collapse↔expand; visual=amber border/bg (`border-amber-500/40`), positions in `bg-background/60` cards; honesty=**disagreement is NOT resolved** by preferring newer/more-cited — both kept verbatim; renders ONLY when `positions.length>0` (never fabricated); interaction=full-width toggle button, hover `amber-500/10`; a11y=chevron state, amber contrast on dark ok.
- **Acceptance (UX-pass ⇔):** row renders only for a real conflict; on expand both positions + sources visible; absent/empty conflicts → row never renders.
- **Upgrade:** ✅. **V2:** ⚠️ present as **text boxes**; §09 wants a **study/system/finding/strength evidence table** — deployed lacks the tabular form. **Δ:** V2 escalates to a structured table (improvement, unbuilt).

### Search › Citation item — locus ("cited for") + recency (v2 §01.3.2 / §01.4.2)
- **Journey:** expanding a source shows *what it was cited for* (locus) and *when it was retrieved* (recency), not just a bare DOI.
- **Precondition / data setup:** a citation with `locus:"Fig 3B"`, `retrieval_date:"2026-08-01"`, `corpus_version:"pubmed-2026-07"`.
- **Steps:** 1. Expand panel. 2. Expand the citation item chevron. 3. Assert `citation-locus` = map-pin + "cited for: Fig 3B" (compact locus badge also in the collapsed row header). 4. Assert `citation-recency` = "Retrieved 2026-08-01 · pubmed-2026-07". 5. DOI/PMID render as external anchors (target=_blank, rel=noopener).
- **Expected UX:** states=static; visual=MapPin primary color, recency muted 11px; honesty=locus/recency render **only when present** (`hasRecency` guard) — no invented Fig/date; interaction=external links open new tab; a11y=links have discernible text (DOI:/PMID:), external icon decorative.
- **Acceptance (UX-pass ⇔):** locus + recency lines present & correct; a citation without locus shows no `citation-locus`; without recency fields shows no `citation-recency`.
- **Upgrade:** ✅. **V2:** ⚠️ §09 also wants a **snippet** + **kind classification** + a "every link confirmed to resolve" footer — deployed lacks these. **Δ:** V2 enriches the reference card (unbuilt).

### Search › Per-source "open ▸" and "Read" → SourceReaderPane (v2 §01.3.3)
- **Journey:** clicking "open ▸" on a source (or "Read" inside the expanded item) opens a right-hand reader Sheet at that source, auditable without leaving the thread.
- **Precondition / data setup:** ≥2 `toolsWithCitations`.
- **Steps:** 1. Expand panel. 2. Click `source-open-0`. 3. Assert `source-reader-pane` opens: "Source 1 of N", title/venue/year, `reader-locus` "cited for" badge when present, recency when present, and either `reader-open-source` (external DOI/PubMed link) or italic "No DOI or PubMed link available for this source." 4. Alt path: expand a citation, click `read-<tool_id>` → same reader at that index.
- **Expected UX:** states=Sheet slide-in from right; visual=w-full sm:max-w-md, centered fallback card; honesty=**full text is NOT faked** — honest "Open at source" fallback; when no DOI/PMID, italic "no link" not a dead button; interaction=Sheet closes on overlay/esc → index back to null; a11y=SheetTitle/Description present, focus trapped in sheet.
- **Acceptance (UX-pass ⇔):** reader opens at the clicked source; "Source X of N" correct; closing resets index to null.
- **Upgrade:** ✅. **V2:** ✅ same reader. **Δ:** §09 wants ref-card **inline expansion under the claim** on `[1][2]` marks; deployed marks jump to a References list (`chat-message.tsx`) — not inline. Mark inline-expansion **✖ UNBUILT**.

### Search › Source reader prev/next navigation (v2 §01.3.3)
- **Journey:** in the reader, prev/next walk the ordered source list; boundaries disable.
- **Precondition / data setup:** reader open at index 0 of N≥3.
- **Steps:** 1. Assert `reader-prev` disabled at index 0. 2. Click `reader-next` → "Source 2 of N". 3. Click `reader-prev` → back to 0. 4. Go to last index → `reader-next` disabled.
- **Expected UX:** states=header count + body update per index; visual=chevron-left/right buttons; honesty=count reflects real list length; interaction=disabled at ends (no wraparound surprise), immediate body update; a11y=disabled buttons announce disabled.
- **Acceptance (UX-pass ⇔):** navigation walks ordered list; `reader-prev` disabled at 0, `reader-next` disabled at N-1; single source → both disabled.
- **Upgrade:** ✅. **V2:** ✅. **Δ:** none.

### Search › Save to project notes — SUCCESS (v2 §01.5) *(live, no-mock)*
- **Journey:** with an active project, "Save to notes" persists the answer + its sources into project knowledge; spinner → success toast.
- **Precondition / data setup:** **real** active project (`useActiveProjectIdSafe()` returns id), ≥1 cited source, optional `answerText`. **E2E hits real `POST /api/memory/projects/:id/knowledge`.**
- **Steps:** 1. Expand panel. 2. Assert `answer-save-notes` ENABLED, tooltip "Save this answer and its sources to the project's notes". 3. Click → Loader2 spinner. 4. Assert toast "Saved to project notes".
- **Expected UX:** states=idle→saving(spinner)→success(toast), spinner clears; visual=StickyNote↔Loader2 swap; honesty=saved markdown includes `answerText` + "## Sources" list (label, venue·year, "cited for: <locus>", resolved URL) — no fabricated success; interaction=guarded against double-click (`isSavingNote` early-return); a11y=button has testid + tooltip.
- **Acceptance (UX-pass ⇔):** POST returns 2xx; success toast; spinner clears (`isSavingNote` false). Empty content (no text AND no sources) → destructive toast "Nothing to save" and **NO POST**.
- **Upgrade:** ✅. **V2:** ⚠️ §09 wants "Save as a **doc**" → an **editable/versioned file object** (Spec 12), not just project-knowledge notes. **Δ:** V2 promotes this to a file-object exit (**✖ UNBUILT** — cross-depends on report-as-file).

### Search › Save to project notes — FAILURE + NO-project (v2 §01.5) *(live, no-mock)*
- **Journey:** on backend failure the user sees a destructive toast, not a fake green; with no active project the button is disabled with an explaining tooltip.
- **Precondition / data setup:** (a) active project + force endpoint failure (use a project id the fixture does NOT own → 403/404); (b) no active project (`useActiveProjectIdSafe()` null).
- **Steps (a):** 1. Click save → api rejects. 2. Assert destructive toast "Could not save" / error msg; console logs `[citations] save to notes failed:`; button re-enabled. **Steps (b):** 1. Assert `answer-save-notes` `disabled`. 2. Hover the wrapping `<span>` → tooltip "Select a project to save this answer to its notes".
- **Expected UX:** states=(a) saving→error, spinner cleared, not stuck; honesty=no fake success on failure; disabled-explains-why via tooltip; interaction=`<span>` wrapper lets tooltip fire on the disabled button; a11y=span `tabIndex=0` when disabled so tooltip is keyboard-reachable.
- **Acceptance (UX-pass ⇔):** (a) failure toast shown, button not stuck spinning, no fake success; (b) disabled + correct tooltip, click is a no-op (early return).
- **Upgrade:** ✅. **V2:** ✅ same. **Δ:** none.

### Search › "Make a project instruction" — honestly disabled (v2 §01.5)
- **Journey:** the second sanctioned exit is present but honestly disabled (no write endpoint) — tooltip explains "coming soon".
- **Precondition / data setup:** any (hard-disabled regardless of project).
- **Steps:** 1. Assert `answer-make-instruction` `disabled` unconditionally. 2. Hover → tooltip "Promote to a standing project instruction — coming soon". 3. Confirm no POST on click.
- **Expected UX:** honesty=**disabled rather than fabricating a success** — the load-bearing honesty case; interaction=tooltip via `<span tabIndex=0>`; a11y=disabled announced.
- **Acceptance (UX-pass ⇔):** always disabled; tooltip "coming soon"; no network call. **[SPEC-DRIFT vs task-brief working-exit expectation — honesty wins.]**
- **Upgrade:** 🔒 disabled. **V2:** §09 wants it working ("turn into a run" / editable-doc exits). **Δ:** V2 expects two live exits; deployed ships them 🔒/⚠️ (unbuilt) rather than fake.

### Search › Export BibTeX
- **Journey:** one click exports all citations as a `.bib` file (API export when a `workflow` prop is present, else concatenated `formatted_bibtex`).
- **Precondition / data setup:** ≥1 `toolsWithCitations`; `workflow` prop present OR citations carrying `formatted_bibtex`.
- **Steps:** 1. Click "Export BibTeX" → Loader2 spinner. 2. Assert `workflow_citations.bib` downloads. 3. Spinner clears.
- **Expected UX:** states=idle→exporting→done; honesty=fallback concatenation only from real `formatted_bibtex` (no invented entries); with neither workflow nor bibtex → nothing downloads (no empty file); interaction=button only rendered when `toolsWithCitations.length>0`.
- **Acceptance (UX-pass ⇔):** `.bib` downloads; spinner clears (`isExporting` false).
- **Upgrade:** ✅. **V2:** ✅ (BibTeX is not a §09 change). **Δ:** none.

### Search › Methods Section tab (regenerate + copy)
- **Journey:** the Methods tab renders a read-only methods narrative; user changes Style (short/apa/numbered) → regenerates; clicks Copy → green check.
- **Precondition / data setup:** `workflow` prop present (enables generation).
- **Steps:** 1. Open "Methods Section" tab (enabled only when `displayMethodsSection || workflow`). 2. If empty, click "Generate Methods Section". 3. Change Style → regenerate call fires. 4. Click "Regenerate". 5. Click "Copy" → check for 2s. 6. Assert "N tool(s) cited" + any "N tool(s) missing citations".
- **Expected UX:** states=generating spinner (Loader2/RefreshCw spin) resolves; visual=read-only Textarea, muted counts; honesty=missing-citation count surfaced (not hidden); interaction=Copy feedback (green check), style change triggers regenerate; a11y=Select labelled "Style:".
- **Acceptance (UX-pass ⇔):** methods text populates; style change triggers a regenerate; copy feedback shows; tab `disabled` when `!displayMethodsSection && !workflow`; without workflow → "Methods section not available" (honest-empty).
- **Upgrade:** ✅ (read-only Textarea). **V2:** §12 promotes Methods to an **editable document** with **Edit/Save-version** (`v2/AfterRunReport.tsx MethodsTab`, testids `methods-edit-toggle`/`methods-editor`/`methods-save-edited`). **Δ:** V2 makes Methods editable — **that increment lives in Cluster B**; here Methods stays read-only.

**Δ(upgrade→v2) — Search & Evidence**

| Function | Upgrade | V2 spec (§01/§09) | V2 deployed | Δ verdict |
|---|---|---|---|---|
| Panel collapse + tool badge | ✅ | §01.3.2 (unchanged) | ✅ | neutral |
| Retrieval transparency (found·kept, N of M, bars) | ✖ | §09 | ⚠️ spec-ready, **not wired** (honest-empty live) | improvement (component-only) |
| Conflict row (both positions) | ✅ text boxes | §09 study/system/finding/strength table | ⚠️ text boxes | improvement (table unbuilt) |
| Locus + recency | ✅ | §01.3.2/§01.4.2 | ✅ | neutral |
| Snippet / kind / link-resolution footer | ✖ | §09 | ✖ | unbuilt |
| Source reader (open/read, prev/next) | ✅ | §01.3.3 | ✅ | neutral |
| Inline ref-card under a claim on `[n]` mark | ✖ (jumps to list) | §09 | ✖ | unbuilt |
| Boundary ("not evidence for" + index date) | ✖ | §09 | ✖ | unbuilt |
| Editable filter chips re-derive / "what was dropped" | ✖ | §09 | ✖ | unbuilt |
| Save to notes (success/fail/no-project) | ✅ | §01.5 | ✅ | neutral |
| Save as editable **doc** (file object) | ✖ (notes only) | §09 + §12 | ✖ | unbuilt |
| "Make instruction" exit | 🔒 disabled | §01.5 (working) | 🔒 disabled | honest-gate |
| "Turn into a run" exit | ✖ | §09 | ✖ | unbuilt |
| Export BibTeX / Methods tab | ✅ read-only | §12 editable methods | ✅ (edit → Cluster B) | neutral here |
| **Answer-as-surface (dedicated route)** | ✖ (inline panel) | §09 `SearchAnswer.jsx` | ✖ | **major unbuilt** |

---

# PART 2 — DESIGN & GENERATE (v2 §05, §11)

Component: `design-generate/DesignGenerate.tsx`, route `/design`. Four Spec-05
commitments enforced: constraints ARE the interface; NO composite score; safety
is a GATE (rejected stay visible); honest failure profile. Spec-11 adds the
modality selector. Backend: `POST /api/generate` → `{run_id,status}`;
`GET /api/generate/{id}` polled every 1500 ms while running.

> **Test-layer guidance (Design):** most UCs are **component tests** injecting a
> fake `GenerateClient` with deterministic `GenerationRun` fixtures. **UC-D212
> (re-rank purity)** is load-bearing: assert the injected client's `start`/`poll`
> call counts do NOT increase on a weight edit. `isContradiction`,
> `classifyRejection`, `reRank`, `rankKey`, `buildOrderSheetCsv`, `modalityOf`
> are exported → directly unit-testable. Full-stack E2E only to prove the
> `/api/generate` proxy.

### Design › Entry routes strip (§5.6)
- **Journey:** an "Start from…" strip offers three real navigations into the design flow: From a dataset → `/files?from=design`; From Models → `/models?from=design`; From Search → `/?from=design`.
- **Precondition / data setup:** `/design` mounted, no host override props.
- **Steps:** 1. Assert `entry-routes` strip with "Start from…" label. 2. Click `design-entry-dataset` → path `/files`, search `from=design`. 3. `design-entry-models` → `/models`. 4. `design-entry-search` → `/`.
- **Expected UX:** journey=each chip a discoverable outline Button with a title tooltip explaining the hand-off intent; honesty=`?from=design` is a **provenance marker only** (no consumer today — navigate-only, not a fake hand-off); interaction=host callback (`onStartFromDataset` etc.) wins over default nav; visual=icon+label chips; a11y=`data-testid` + legacy alias `entry-<key>`, title tooltip.
- **Acceptance (UX-pass ⇔):** each chip lands on the cited pathname+search; callback override precedence holds when supplied.
- **Upgrade:** ✖ — Design & Generate is a **v2-new module**; not present in the pre-v2 Upgrade UI. **V2:** ✅ §5.6. **Δ:** whole module is V2-new (mark Upgrade column ✖ for all Design UCs).

### Design › Modality selector — chips + constraint swap (§11.2)
- **Journey:** three chips (Small molecule / Peptide / Protein·biologic) under the composer header pick which constraint set shows and the "… to stay on" slot; the choice is held and travels into the payload.
- **Precondition / data setup:** fresh `/design`; default `small_molecule`.
- **Steps:** 1. Assert `dg-modality` group with `dg-modality-small_molecule` (active, `data-selected="true"`), `dg-modality-peptide`, `dg-modality-protein`. 2. Assert `dg-modality-blurb` shows the modality blurb + "What the generation should stay on: **scaffold**". 3. Click `dg-modality-peptide` → `dg-constraints-peptide` appears (`dg-sequence` + `dg-cyclization`), `dg-constraints-small_molecule` unmounts. 4. Click `dg-modality-protein` → `dg-constraints-protein` (`dg-framework`) appears. 5. Back to small molecule → `dg-constraints-small_molecule` returns.
- **Expected UX:** states=exactly one chip `variant="default"` (`data-selected="true"`) at a time; visual=blurb + stay-on slot updates (scaffold / sequence motif / framework); honesty=**seeds live in separate fields** — switching modality does NOT reinterpret a SMILES seed as a sequence (`buildBody` only attaches `sequence`/`cyclization` for peptide, `framework` for protein, never cross-fed); interaction=click is authoritative (outranks `modalityOf` text inference); a11y=Buttons keyboard-navigable, `data-selected` conveys state.
- **Acceptance (UX-pass ⇔):** selecting a chip swaps to `dg-constraints-{sm,peptide,protein}` and sets `data-selected="true"` on exactly one; `MODALITY_META[m].stayOn` shows in the blurb.
- **Upgrade:** ✖. **V2:** ✅ §11.2. **Δ:** V2-new.

### Design › Modality run-gating — HONEST "Generator coming" (§11.6) **[load-bearing honesty]**
- **Journey:** for peptide/protein the run is disabled with a clear amber "Generator coming" note; only small-molecule runs today — no fabricated peptide/protein result.
- **Precondition / data setup:** select `dg-modality-peptide` (then `protein`).
- **Steps:** 1. Assert `dg-modality-unrunnable` amber card: "**Generator coming.** Peptide constraints are captured and travel with the request, but the peptide generator is not wired yet — no result is fabricated. Small-molecule design runs today." 2. Assert `dg-run` is **disabled** (`disabled={running || !canRun}`, `canRun = modality==='small_molecule'`). 3. (Belt-and-braces) confirm `onRun` early-returns for non-SM (`if (modality !== "small_molecule") return`). 4. Switch to `small_molecule` → note gone, `dg-run` enabled.
- **Expected UX:** states=disabled↔enabled tracks modality; visual=amber-500/40 border, "Generator coming" bold amber; honesty=**the entire point** — captured constraints travel in the payload (honest about what was asked) but NO peptide/protein shortlist is invented; interaction=disabled `dg-run` explains why via the adjacent note (not a silent dead button); a11y=disabled button + visible reason.
- **Acceptance (UX-pass ⇔):** `dg-modality-unrunnable` shown for peptide/protein; `dg-run` disabled; clicking run is a no-op; NO candidates/rejected/pareto render for peptide/protein; small-molecule remains runnable with the note absent.
- **Upgrade:** ✖. **V2:** ✅ §11.6. **Δ:** V2-new; this is the canonical honest-gating case for the whole cluster.

### Design › Peptide / Protein constraint controls (§11.3)
- **Journey:** peptide shows a sequence field + cyclisation chips (none/head-to-tail/disulfide/staple); protein shows a framework textarea.
- **Precondition / data setup:** peptide (then protein) modality selected.
- **Steps:** 1. Peptide: type into `dg-sequence` (placeholder "e.g. ACDEFGHIK"); click `dg-cyclization-staple` → active; assert `dg-cyclization` group has 4 chips. 2. Protein: type into `dg-framework` (placeholder mentions VHH framework / grafting CDRs).
- **Expected UX:** states=chip active state; visual=mono inputs; honesty=values reach `buildBody().constraints.sequence/cyclization` (peptide) / `.framework` (protein) only for their modality; interaction=one active cyclisation chip; a11y=labelled inputs.
- **Acceptance (UX-pass ⇔):** payload carries `sequence`+`cyclization` for peptide (cyclization omitted when "none"), `framework` for protein; never cross-fed.
- **Upgrade:** ✖. **V2:** ✅ §11.3. **Δ:** V2-new.

### Design › Constraints composer — seed SMILES / scaffold / envelope / exclusions / seed-series (§5.2)
- **Journey (small molecule):** the constraints ARE the interface — seed SMILES, scaffold policy (stay/hop/grow), property envelope (MW/logP/TPSA), exclusion SMARTS, seed series — all resolve to run params shown before the run.
- **Precondition / data setup:** small-molecule modality.
- **Steps:** 1. Assert `constraints-composer` heading "Design constraints" + copy "Generation is only useful when constrained…". 2. Type `dg-seed-smiles` (placeholder `CC(=O)Oc1ccccc1C(=O)O`). 3. Toggle `dg-policy-hop`/`-grow` (exactly one active). 4. Edit `dg-mw`/`dg-logp`/`dg-tpsa` (defaults 500/5/140; label "a window, not a cut-off"). 5. Fill `dg-exclusions` (placeholder `[N+](=O)[O-]`) + `dg-seed-series` ("One SMILES per line").
- **Expected UX:** states=static form; visual=3-col envelope grid, mono inputs; honesty=non-numeric envelope → field omitted (undefined), not 0; `parseList` drops empties; interaction=one active scaffold chip; a11y=all inputs labelled.
- **Acceptance (UX-pass ⇔):** payload reflects each control (`seed_smiles`, `scaffold_policy`, `property_envelope.{mw,logp,tpsa}_max`, `exclusions[]`, `seed_series[]`); blank/abc envelope field omitted; policy is one of stay/hop/grow.
- **Upgrade:** ✖. **V2:** ✅ §5.2. **Δ:** V2-new.

### Design › Count + virtual-library size + compute-cost hint (§5.2)
- **Journey:** the user states how many candidates to keep and the virtual library size; a transparent compute-cost hint updates live before running.
- **Precondition / data setup:** defaults count=20, nGenerate=200.
- **Steps:** 1. Read `dg-cost` = "Compute cost before run: ~4 compute units" (`max(1,round((200+20)/50))`). 2. Set count=40, `dg-ngenerate`=400 → `dg-cost` = "~9 compute units". 3. N=1 → singular "unit".
- **Expected UX:** honesty=explicitly "not a billing figure" (UI heuristic); visual=cost line + run button on a bordered footer; interaction=recomputed every render.
- **Acceptance (UX-pass ⇔):** displayed unit count matches `max(1,round((nGenerate+count)/50))` for entered numbers; singular/plural correct.
- **Upgrade:** ✖. **V2:** ✅ §5.2. **Δ:** V2-new.

### Design › Run start → running state (§5.8)
- **Journey:** clicking "Generate & rank" enters a running state — button shows "Running…" and disables; a status badge reads `running`.
- **Precondition / data setup:** inject client whose `start`→`{run_id:"r1",status:"running"}`, first `poll`→ running.
- **Steps:** 1. Click `dg-run`. 2. Assert button label "Running…" + disabled; `dg-status` badge `data-status="running"` reading "running". 3. Poll schedules a 1500 ms retry.
- **Expected UX:** states=idle→running immediate; visual=Play icon, badge outline; honesty=running reflects real poll state; interaction=second click blocked by `disabled`; a11y=`data-status` attr for observation.
- **Acceptance (UX-pass ⇔):** button disabled + "Running…"; badge `data-status="running"`.
- **Upgrade:** ✖. **V2:** ✅. **Δ:** V2-new.

### Design › Poll resolves to completed — status/notes/generator line (§5.8)
- **Journey:** on completion the status line states generator + generated/scored counts; notes list renders; the run reseeds criteria.
- **Precondition / data setup:** injected `poll` returns completed run (`generator:"brics"`, `generator_is_learned:false`, `n_generated:200`, `n_scored:180`, `notes:[…]`, candidates+objectives).
- **Steps:** 1. Run → let poll resolve. 2. Assert `dg-status` `data-status="completed"` reading "completed"; line shows "generator: brics (deterministic enumeration, not learned)", "generated: 200", "scored: 180". 3. `dg-notes` renders each note as `<li>`.
- **Expected UX:** states=running→completed, poll loop stops; honesty="(deterministic enumeration, not learned)" only when `generator_is_learned===false` — never implies a learned model that isn't; visual=muted status strip; interaction=none.
- **Acceptance (UX-pass ⇔):** badge completed; generator/generated/scored line correct; notes list matches `run.notes`.
- **Upgrade:** ✖. **V2:** ✅. **Δ:** V2-new.

### Design › Completed results — HitGrid + Multi-objective view (NO composite score) (§5.4)
- **Journey:** completed candidates show in HitGrid and a multi-objective table where each objective keeps its own units and target — no single blended number as the headline.
- **Precondition / data setup:** completed run, ≥2 candidates with `objectives[]`, ≥1 `verdict:"held"`.
- **Steps:** 1. Assert `hit-grid` + `hit-table`; each candidate a `hit-row-<id>`; held candidate shows `hit-held-note`. 2. Assert `multi-objective-view`: header "Each objective keeps its own units and its own target — no single blended number"; each objective col header `name /unit`; the `score*` header `title="Ranking key only"`; footer note "score is a ranking key… not a composite the pipeline optimises." 3. Each `mobj-row-<id>` has one `obj-<name>` per objective, green when target met, amber when not, slate when no target.
- **Expected UX:** honesty=**score is explicitly a ranking key**, not "the one number" — the load-bearing §5.4 case; held candidate visible (not filtered); objective missing → cell "n/a" italic; visual=color-coded target status; a11y=table headers.
- **Acceptance (UX-pass ⇔):** both views render; no composite presented as headline; held candidate visible.
- **Upgrade:** ✖. **V2:** ✅ §5.4. **Δ:** V2-new.

### Design › Editable criteria/weights re-rank WITHOUT re-running (§5.5) **[load-bearing purity]**
- **Journey:** the user edits per-objective targets/weights; rows reorder instantly with NO new prediction run.
- **Precondition / data setup:** completed run; `criteria-strip` visible, seeded from run.
- **Steps:** 1. Note HitGrid/`mobj` row order. 2. Bump a `criteria-weight-<name>` to 5 and/or set `criteria-target-<name>`. 3. Observe reorder. 4. Assert NO new `client.start`/`client.poll` fires.
- **Expected UX:** states=instant client-side re-sort (`useMemo reRank`); visual=`criteria-stated` line updates ("Ranking criteria: <name> (↑ ≥ t, w=5) · …"); honesty=re-rank is a pure re-sort of already-returned candidates (no re-prediction), held sort to end; interaction=weight 0 excludes objective; all-zero → falls back to `c.score`; a11y=numeric inputs labelled.
- **Acceptance (UX-pass ⇔):** order changes AND injected client `start`/`poll` counts unchanged after the edit.
- **Upgrade:** ✖. **V2:** ✅ §5.5. **Δ:** V2-new.

### Design › Pareto / trade-off view (§5.4)
- **Journey:** a 2-objective scatter shows the trade-off, front members highlighted; axes re-pickable.
- **Precondition / data setup:** completed run, ≥2 objectives, non-empty `pareto[]`.
- **Steps:** 1. Assert `pareto-view` + `pareto-svg`. 2. Each candidate = `pareto-point-<id>`; front members `data-on-front="true"` (indigo, larger r); `pareto-front-path` when ≥2 front points. 3. Change `pareto-x-axis`/`pareto-y-axis` → re-plot with no network call.
- **Expected UX:** honesty="The trade-off is shown, not collapsed"; gate-rejected dots red, held slate; empty `pareto[]` → note "No front members were returned for this run"; visual=legend with on-front count; interaction=axis selects pure client-side.
- **Acceptance (UX-pass ⇔):** front points flagged `data-on-front="true"`; axis change re-plots without a network call; `<2` objectives → `pareto-empty` note; no candidate carries both selected → `pareto-empty` note.
- **Upgrade:** ✖. **V2:** ✅ §5.4. **Δ:** V2-new.

### Design › Per-row "why?" drill-in (§5.3/§5.5)
- **Journey:** expanding a row's "why?" shows model / version / confidence / what-drove-it and an honest nearest-analogue line.
- **Precondition / data setup:** completed run.
- **Steps:** 1. Click `why-toggle-<id>` (`aria-expanded`→true). 2. Assert `why-detail-<id>`: Model = "<generator> + objective predictors (…)"; `why-version-<id>` = "deterministic enumeration (unversioned)" when `generator_is_learned===false"; `why-confidence-<id>` capitalized; "What drove it" per-objective list; `why-analogue-<id>` = "not available — no measured assay series was returned with this run". Held → amber applicability note.
- **Expected UX:** honesty=**nearest analogue honestly says unavailable** — not invented; version honest about unversioned enumeration; a11y=`aria-expanded` on toggle.
- **Acceptance (UX-pass ⇔):** four labelled fields populated from real run data; analogue states unavailability; empty objectives → "no per-objective values available".
- **Upgrade:** ✖. **V2:** ✅. **Δ:** V2-new.

### Design › Rejection profile + rejected set stays visible (§5.2/§5.8) **[safety-as-gate]**
- **Journey:** rejections are counted AND characterised by cause; rejected candidates stay visible with their gate reason (never filtered).
- **Precondition / data setup:** completed run with `rejected[]` of mixed reasons.
- **Steps:** 1. Assert `rejection-profile` + total badge; one `rejection-cause-<cause>` per bucket (`structural_alert/banned_moiety/sa_floor/valence/other` fixed order) with `rejection-count-<cause>`; `passedNote` "<n_scored> scored of <n_generated> generated". 2. Expand `rejected-set` → each `rejected-row-<id>` shows id + `rejected-reason-<id>` + SMILES, red left-border.
- **Expected UX:** honesty=**safety is a gate, never traded away** — rejected NEVER filtered out; visual=red accents; interaction=collapsible rejected set; a11y=collapse chevron.
- **Acceptance (UX-pass ⇔):** each cause bucketed via `classifyRejection`; rejected rows visible with reason; `rejected.length===0` → both render null.
- **Upgrade:** ✖. **V2:** ✅ §5.2. **Δ:** V2-new.

### Design › Honest empty state — no candidates fabricated (§5.8)
- **Journey:** when nothing clears the pipeline, an honest empty card + the rejection profile explain why — no fabricated shortlist.
- **Precondition / data setup:** completed run with `candidates: []`, populated `rejected[]`.
- **Steps:** 1. Assert `dg-empty` card: "No candidates cleared the pipeline… Nothing was fabricated to fill a shortlist." 2. Followed by `rejection-profile`. 3. No HitGrid / criteria strip / order sheet (gated on `candidates.length>0`).
- **Expected UX:** honesty=**explicitly states nothing was fabricated**; visual=muted card; interaction=none.
- **Acceptance (UX-pass ⇔):** `dg-empty` shown; no fabricated candidates; rejection profile explains why (or profile null if also zero rejected).
- **Upgrade:** ✖. **V2:** ✅. **Δ:** V2-new.

### Design › Predicted-vs-measured — contradiction flag (§5.7)
- **Journey:** when the bench returns measurements, they show against the predictions per candidate; large divergence is flagged as a contradiction.
- **Precondition / data setup:** completed run + `measuredResults` prop with a measured objective diverging >50% from prediction.
- **Steps:** 1. Assert `predicted-vs-measured` with `pvm-row-<id>` per measured candidate; each `pvm-cell-<id>-<name>` "pred → meas"; divergence >tol → `data-contradiction="true"`, measured value red, `pvm-flag-<id>-<name>` "contradiction". 2. Header `pvm-contradiction-count` "N flagged".
- **Expected UX:** honesty=**surrogate not trusted silently after a bad round** — flags divergence; no measurements → `pvm-empty` "No measured results yet…"; unmatched id dropped; a11y=`data-contradiction` attr.
- **Acceptance (UX-pass ⇔):** contradiction cell flagged red + count correct; `isContradiction(pred,meas,0.5)` honored.
- **Upgrade:** ✖. **V2:** ✅ §5.7. **Δ:** V2-new.

### Design › Order-sheet export (§5.5/§5.7)
- **Journey:** the shortlist leaves the platform as an order-sheet CSV pairing candidate + registry ids, per-objective values in own units, in current re-ranked order.
- **Precondition / data setup:** completed run, ≥1 candidate.
- **Steps:** 1. Assert `order-sheet` strip + copy "Leave the platform as an order…". 2. Click `dg-export-order` → `order-sheet-<run_id>.csv` downloads. 3. Header `rank,candidate_id,registry_id,smiles,verdict,score,<obj (unit)>…`; `registry_id = REG-<id>`; rows in re-ranked order.
- **Expected UX:** honesty=only on-screen candidate data (nothing fabricated); RFC-4180 quoting for commas/quotes; interaction=`disabled` when `candidates.length===0`.
- **Acceptance (UX-pass ⇔):** CSV parses to expected header+rows; `REG-` prefix present; disabled with no candidates.
- **Upgrade:** ✖. **V2:** ✅ §5.5/§5.7. **Δ:** V2-new.

### Design › Backend failure banner (§5.8)
- **Journey:** a start/poll failure surfaces the real error string honestly; no fake results; run not stuck "Running…".
- **Precondition / data setup:** inject `client.start` that rejects ("start failed: 500").
- **Steps:** 1. Click `dg-run`. 2. Assert `dg-error` banner shows the error string; no candidate view; button not stuck (run never set to running because start threw before `setRun`).
- **Expected UX:** honesty=real error, no fabricated candidates; a poll rejection mid-run also routes to `dg-error`; visual=red text.
- **Acceptance (UX-pass ⇔):** `dg-error` visible with the real string; no fabricated candidate view.
- **Upgrade:** ✖. **V2:** ✅. **Δ:** V2-new.

**Δ(upgrade→v2) — Design & Generate**

| Function | Upgrade | V2 spec | V2 deployed | Δ verdict |
|---|---|---|---|---|
| Whole module (`/design`) | ✖ | §5 / §11 | ✅ | **V2-new module** |
| Entry routes strip | ✖ | §5.6 | ✅ | new |
| Modality chips + constraint swap (`dg-modality-*`, `dg-constraints-*`) | ✖ | §11.2 | ✅ | new |
| Modality run-gating (`dg-modality-unrunnable`, `dg-run` disabled) | ✖ | §11.6 | 🔒✅ honest-gate | new (peptide/protein NOT runnable; SM only) |
| Peptide/protein constraints | ✖ | §11.3 | ✅ (captured, not run) | new |
| Constraints composer (SM) | ✖ | §5.2 | ✅ | new |
| Count + cost hint | ✖ | §5.2 | ✅ | new |
| Run/running/completed states | ✖ | §5.8 | ✅ | new |
| HitGrid + multi-objective (no composite) | ✖ | §5.4 | ✅ | new |
| Criteria/weights re-rank w/o re-run | ✖ | §5.5 | ✅ | new |
| Pareto view | ✖ | §5.4 | ✅ | new |
| Per-row "why?" | ✖ | §5.3/§5.5 | ✅ | new |
| Rejection profile + rejected-set (gate) | ✖ | §5.2/§5.8 | ✅ | new |
| Honest empty state | ✖ | §5.8 | ✅ | new |
| Predicted-vs-measured contradiction | ✖ | §5.7 | ✅ | new |
| Order-sheet export | ✖ | §5.5/§5.7 | ✅ | new |
| Error banner | ✖ | §5.8 | ✅ | new |

---

# PART 3 — REPORTS / EXPORTS · CONNECTORS · BILLING + SETTINGS

## 3A · Reports / exports (standalone)

> **Scope note:** the v2 §12 "reports as editable files" thesis (report-in-file-tree,
> chat-edit-with-diff, versioning, multi-format PDF/DOCX/HTML/ZIP) is the **biggest
> v2 gap** and is **unbuilt** for workflow reports. The one editable increment —
> Methods report Edit/Save-version in `v2/AfterRunReport.tsx` — is covered in
> **Cluster B**. **Cluster D's standalone reports/exports surface = the download
> exits already built:** the design **order-sheet CSV** (Part 2), **BibTeX** +
> **Methods copy/download** (Part 1), and the after-run **"Download report" (MD)**
> button (Cluster B). Below tests the *export exits'* UX-honesty as a group.

### Reports › Download exits render honest formats (v2 §12 delta) **[V2-partial]**
- **Journey:** a user finishing a run/answer/design can take the result out — as CSV (order sheet), `.bib` (citations), copied/downloaded methods text, or a Markdown report.
- **Precondition / data setup:** a completed design run (order sheet) + a citation set with a workflow (BibTeX/Methods). No mocks.
- **Steps:** 1. Design: `dg-export-order` → CSV downloads (Part 2). 2. Citations: "Export BibTeX" → `.bib` downloads; Methods "Copy" → clipboard + green check (Part 1). 3. After-run: "Download report" (Cluster B) → MD blob.
- **Expected UX:** states=each export has spinner/feedback; visual=Download icons; honesty=**exports carry only real on-screen data**; MD-only download honestly labels itself (the codebase notes "Future: DOCX/PDF generator" — no fake PDF/DOCX menu presented); interaction=disabled export when nothing to export.
- **Acceptance (UX-pass ⇔):** each export produces the stated file/format from real data; no export offers a format it cannot actually produce.
- **Upgrade:** ⚠️ read-only MD download + CSV + BibTeX; no report file-object, no multi-format, no chat-edit. **V2:** §12 = report is a **file object**: PDF/DOCX/MD/HTML/ZIP, edit-by-hand (contentEditable, save new version), edit-by-asking (before/after diff → new version), versioning via `fileVersions(id)`, cell-level ask-and-diff for data files. **Δ:** V2 makes reports first-class editable objects — **✖ UNBUILT** for workflow reports (only Methods Edit/Save lives in Cluster B, and its "version" is a local MD download, not persisted — versioning deferred honestly, `INCREMENT.md §Surface A`).
- **Known gap / deferred:** report-in-file-tree, chat-propose-diff (NOW/PROPOSED/accept→new version), server-side `fileVersions(id)` endpoint, PDF/DOCX/HTML/ZIP export — all deferred (no backend version endpoint; a version chip would be fabricated).

## 3B · Connectors (`connectors-dialog.tsx` + `connector-residency.tsx`)

> **Structure note:** deployed is a **MODAL DIALOG**, opened from the sidebar
> `button-connectors-nav` (Cluster A). v2 §Connectors wants a **full page** with
> **four kinds** (Data sources / Models & LLMs / Skills & experts / MCP servers)
> and an "Add a connector" pre-attach preview. Deployed ships **2 of 4** kinds
> (Databases + AI & Platforms); Skills tab is **built-but-commented-out**
> (`/api/skills` returns 0); no MCP tab; no Add flow. Residency is **DONE**.

### Connectors › Open / close / tab switch
- **Journey:** click sidebar Connectors → modal opens on the Databases tab → switch to AI & Platforms → close.
- **Precondition / data setup:** authenticated; open via `button-connectors-nav` (or render `ConnectorsDialog open`).
- **Steps:** 1. Assert `connectors-dialog` opens; title "Connectors" + subtitle explaining residency. 2. Assert tabs `connector-tab-databases` (count badge `DB.length`=63) + `connector-tab-ai` (count `AI.length`). 3. Click `connector-tab-ai` → AI `ConnectorTable` renders. 4. Close (overlay/esc).
- **Expected UX:** states=open/close, tab active underline; visual=count badges, "N on" badge on databases when selections>0; honesty=**only 2 tabs** — Skills/MCP not faked as present; interaction=tab hover/active; a11y=DialogTitle present, tabs are buttons.
- **Acceptance (UX-pass ⇔):** dialog opens; both tabs switch content; Skills/MCP tabs absent (not disabled-but-visible — they are commented out).
- **Upgrade:** ✅ (residency modal shipped). **V2:** ⚠️ full page, 4 kinds. **Δ:** V2 re-hosts as a page + adds Skills/MCP + Add flow — structural gap; deployed is honest about the 2 kinds it has.

### Connectors › Databases tab — sub-groups, selection, residency, declared facts
- **Journey:** the user browses 63 databases by sub-group, toggles which are active, and reads residency + declared facts per row.
- **Precondition / data setup:** Databases tab.
- **Steps:** 1. Assert sub-tabs (All / Protein & Structure / … / Literature / Other) with per-group counts + "N✓" selected badges. 2. Toggle a `connector-row-<name>` → checkbox flips, row highlights, persisted to `biomate-active-databases`. 3. Assert each row shows `ResidencyBadge` (all "cloud" — uniform declared fact for public DBs) + `DeclaredFact needs/produces/where it runs` (honest "not declared" italic when absent). 4. `ScopeSelector` per row (account/project/request, default account).
- **Expected UX:** states=selection persists (localStorage), footer "N of 63 selected" with Select all/Deselect all; visual=residency legend at top; honesty=**"not declared"** rendered (not guessed) for absent facts; interaction=whole-row click toggles; a11y=`fact-<label>` testids with `data-declared`.
- **Acceptance (UX-pass ⇔):** toggle updates count + footer; residency badge on every row; absent facts show "not declared" (`data-declared="no"`).
- **Upgrade:** ✅. **V2:** ⚠️ §Connectors wants on-prem/mounted sources + index-in-place vs copy-in + per-scan versioning. **Δ:** V2 adds non-cloud residencies + lifecycle — cloud-only today (honest, since all listed are public web APIs).

### Connectors › AI & Platforms tab — per-row residency
- **Journey:** LLMs / local runners / platforms each carry their own residency (hosted cloud leaves the estate; Ollama/Cursor stay local).
- **Precondition / data setup:** AI tab.
- **Steps:** 1. Assert `ConnectorTable` of AI rows; 2. `Anthropic Claude`/`Gemini`/`OpenAI GPT` residency "cloud" + needs "API key"; `Ollama` residency "local" + "this host — never leaves"; `Cursor` local MCP. 3. Footer "N connectors".
- **Expected UX:** honesty=residency is a genuine per-row declared fact; visual=same table; a11y=residency badges.
- **Acceptance (UX-pass ⇔):** each AI row shows correct residency; local rows honestly state data never leaves.
- **Upgrade:** ✅. **V2:** ⚠️ missing "vendor prediction service" concept + MCP-servers kind. **Δ:** V2 adds MCP tab; deployed only mentions MCP on the Cursor row.

### Connectors › Skills tab — honestly ABSENT (not empty)
- **Journey:** the Skills & experts kind is intentionally not shown because `/api/skills` returns 0 — showing an empty/loading tab would be a poor honest state.
- **Precondition / data setup:** any.
- **Steps:** 1. Assert `TabId` union is `'databases' | 'ai'` only; no `connector-tab-skills` in the DOM. 2. Confirm `SkillsTab` component exists in the file but is not wired (commented out at `:524-526,626`).
- **Expected UX:** honesty=**built-but-dark rather than shipping an empty surface**; no fake "0 skills" tab.
- **Acceptance (UX-pass ⇔):** no Skills tab rendered; `SkillsTab` unreferenced by `TABS`. **[V2-partial — document as coverage gap, not a bug: enabling blind would ship an empty surface.]**
- **Upgrade:** 🔒 dark. **V2:** ✖ wants 12 skill rows + MCP + Add-with-preview. **Δ:** V2 unbuilt; gated on backend `/api/skills` population.

## 3C · Billing (`pages/billing.tsx`, `/billing`)

> **Reach note:** `/billing` route exists but **no sidebar entry links to it**
> (functional plan flag). Reach by direct URL. Page uses honest-empty copy but
> has **no `data-testid`s** — assert on visible text.

### Billing › Page loads — plan, usage breakdown, honest-empty states
- **Journey:** navigate to `/billing` → see current plan, an itemised usage table (LLM tokens, compute vCPU/GPU hrs, storage), credit packs, invoices.
- **Precondition / data setup:** authenticated fixture; live `GET /api/billing/usage` + `/api/billing/quota` (real backend, no mock).
- **Steps:** 1. Load `/billing`; assert loading resolves (Loader2 → content), no stuck spinner. 2. Usage table rows: LLM (tokens_in/out + $), Compute (vCPU $0.10/hr, GPU $1.50/hr), Storage (S3 $0.15/GB). 3. If no usage → row "No on-demand usage this cycle" (honest-empty). 4. Invoices section: rows or "No invoices found"; footer "Invoices are generated at the end of each billing cycle."
- **Expected UX:** states=loading/loaded/error (`error` state exists); visual=Table layout, tabular-nums; honesty=**"No on-demand usage this cycle" / "No invoices found"** honest-empty (not blank/NaN); interaction=invoice-month Select filters; a11y=table headers uppercase labels.
- **Acceptance (UX-pass ⇔):** page loads real usage; empty states show the honest copy; no "$NaN"/"undefined"; payment-unavailable path shows "Payment is not available right now. Please contact support." (not a broken checkout).
- **Upgrade:** ✅ (Stripe + internal quota per CLAUDE.md flat-tier). **V2:** billing is not a v2-spec surface. **Δ:** neutral (no v2 change).

### Billing › Credit packs + auto-charge prefs
- **Journey:** user picks a credit pack ($10/$25/$50) and optionally sets auto-charge (threshold % + top-up amount).
- **Precondition / data setup:** billing page; `CREDIT_PACKS` rendered; `biomate_auto_charge` localStorage.
- **Steps:** 1. Assert three packs, "$25" marked popular. 2. Toggle auto-charge Switch → threshold/amount inputs appear; persisted. 3. Initiate a pack purchase → real Stripe checkout path (do NOT complete a live charge; assert the redirect/dialog opens, or the honest "Payment is not available" message when unconfigured).
- **Expected UX:** honesty=never a fake "purchase succeeded"; disabled/loading during checkout init; a11y=Switch + inputs labelled.
- **Acceptance (UX-pass ⇔):** packs render; auto-charge persists; checkout either opens real Stripe or shows the honest unavailable message.
- **Upgrade:** ✅. **V2:** — **Δ:** neutral.

## 3D · Settings (`settings-dialog.tsx`)

> Opened from sidebar (Cluster A). Here we test the dialog's own tabs/states/honesty.

### Settings › Dialog opens; tab navigation across all panes
- **Journey:** open Settings → vertical tab list (Profile/General/Appearance/Chat/Data/Notifications/Privacy/Security/Advanced/API Keys) → switch tabs → each pane renders.
- **Precondition / data setup:** authenticated; `SettingsDialog open`.
- **Steps:** 1. Assert DialogTitle + vertical `Tabs`. 2. Click each `TabsTrigger` (`profile`→…→`api-keys` / `tab-api-keys`) and assert its `TabsContent` renders. 3. Profile: `input-display-name`/`input-email`/`input-role`. 4. General: `select-language` (incl. 中文). 5. Appearance: `select-theme` (system/light/dark). 6. Data: `select-default-storage`, `s3-credentials-card` (`input-aws-*`, `button-s3-clear`, `button-toggle-secret-visibility`).
- **Expected UX:** states=each pane mounts on select; visual=vertical tab rail; honesty=values reflect saved `UserSettings` (not placeholders); interaction=switches/inputs give immediate state; a11y=labelled inputs + testids; secret masked with a visibility toggle.
- **Acceptance (UX-pass ⇔):** all 10 tabs switch content; profile/general/appearance/data controls render with real values; no "undefined" in any field.
- **Upgrade:** ✅. **V2:** not a v2-spec surface. **Δ:** neutral.

### Settings › API Keys tab — create/show-once/revoke honesty
- **Journey:** create a per-user API key (headless / biomate-connector access); the plaintext is shown ONCE then cleared; revoke removes it.
- **Precondition / data setup:** `tab-api-keys`; live `/api/user/api-keys` (no mock).
- **Steps:** 1. Assert existing keys list (prefix + createdAt + lastUsedAt). 2. Create with a name → `freshKey` plaintext shown once with a Copy control + green "copied" feedback. 3. Re-open → plaintext no longer shown (only prefix). 4. Revoke a key.
- **Expected UX:** states=creating spinner; visual=key rows; honesty=**plaintext shown once, then cleared** (never re-displayed) — a security-honesty case; load/error states surface real messages ("Failed to load API keys"); a11y=copy button feedback.
- **Acceptance (UX-pass ⇔):** create returns a key shown once; subsequent views show only prefix; revoke reflected; load error shows the real message, not a silent empty list.
- **Upgrade:** ✅. **V2:** — **Δ:** neutral.

### Settings › MFA + Retrain-adapter cards
- **Journey:** Security tab exposes MFA setup (`MfaSettings`); an adapter-retrain card (`RetrainAdapterCard`) is present.
- **Precondition / data setup:** relevant tabs.
- **Steps:** 1. Security → assert `MfaSettings` renders (enroll/verify states). 2. Assert `RetrainAdapterCard` present.
- **Expected UX:** states=MFA enroll/verify/enabled; honesty=real MFA status, no fake "enabled".
- **Acceptance (UX-pass ⇔):** MFA card shows the real enrollment state; retrain card renders without error.
- **Upgrade:** ✅. **V2:** — **Δ:** neutral.

**Δ(upgrade→v2) — Peripheral (Reports / Connectors / Billing / Settings)**

| Function | Upgrade | V2 spec | V2 deployed | Δ verdict |
|---|---|---|---|---|
| Report as file object in file tree | ✖ | §12 | ✖ | **major unbuilt** |
| Report edit-by-hand (new version) | ✖ | §12 | ⚠️ Methods only (Cluster B) | partial (local MD, not persisted) |
| Report edit-by-asking (before/after diff) | ✖ | §12 | ✖ | unbuilt |
| Report versioning (`fileVersions(id)`) | ✖ | §12 | ✖ | unbuilt (no backend endpoint) |
| Multi-format export (PDF/DOCX/HTML/ZIP) | ✖ MD only | §12 | ✖ MD only | unbuilt (honest "future" note) |
| Data-file cell-level ask-and-diff | ✖ | §12 | ✖ | unbuilt |
| Connectors surface type | ✅ modal | §C full page | ✅ modal | structural gap |
| Connectors — Data sources kind | ✅ cloud-only | §C mixed residency | ⚠️ cloud-only | partial |
| Connectors — Models & LLMs kind | ✅ | §C | ✅ | neutral |
| Connectors — Skills & experts kind | 🔒 dark | §C 12 rows | ✖ | gated on `/api/skills` |
| Connectors — MCP servers kind | ✖ | §C | ✖ | unbuilt |
| Connectors — residency badge | ✅ | §C | ✅ (adds honest "unspecified") | **DONE / improved** |
| Connectors — Add-with-preview flow | ✖ | §C | ✖ | unbuilt |
| Billing (plan/usage/invoices/credits) | ✅ | (not v2) | ✅ | neutral |
| Settings (10 tabs, API keys, MFA) | ✅ | (not v2) | ✅ | neutral |

---

## 4 · Audit protocol (apply per state, both versions)

1. **Screenshot each state** — Search: collapsed/expanded panel, conflict expanded, reader open+prev/next, save success/fail/disabled, (component-only) retrieval section. Design: modality SM/peptide/protein (peptide/protein must show `dg-modality-unrunnable` + disabled `dg-run`), pre-run, running, completed (HitGrid+multi-objective+pareto+why+rejection), empty, error, predicted-vs-measured. Connectors: databases/AI tabs, a selected row, residency legend. Billing: loaded + empty. Settings: each tab.
2. **Audit vs the cited v2 §** — list every deviation (wrong/undefined text, stuck spinner, missing element, fabricated number, faked green, wrong state).
3. **Honesty gates (must all hold):** peptide/protein NEVER produce a shortlist; `dg-empty` states nothing fabricated; rejected candidates stay visible; `answer-make-instruction` stays disabled; retrieval/conflict sections omit when no real data; API-key plaintext shown once; billing empty states use the honest copy; no export offers a format it can't produce.
4. **A skip is a fail** — record why (e.g. retrieval-transparency not live-observable) and treat as untested.

---

## 5 · Open drift / gaps to raise with the owner

1. **No search-answer surface (v2 §09).** The entire answer-as-surface (retrieval funnel, editable filters, "what was dropped", Boundary, inline ref-cards, disagreement table, turn-into-a-run / save-as-doc exits) is unbuilt; deployed is the inline `CitationPanel`. Only *retrieval-transparency* is spec-ready — and **not wired** (no caller passes `retrieval`; live shows honest-empty).
2. **Reports are not file objects (v2 §12) — biggest gap.** Read-only MD download; no file-tree object, no chat-edit-with-diff, no versioning, no multi-format. Only the Methods Edit/Save increment exists (Cluster B) and its "version" is a local MD download, not persisted.
3. **Connectors is a modal with 2 of 4 kinds.** Skills tab built-but-commented (`/api/skills` returns 0); no MCP tab; no Add-with-preview; not a full page. Residency is genuinely DONE (with an honest "unspecified" fallback the prototype lacks).
4. **`answer-make-instruction` permanently disabled** (no write endpoint) — brief expected a working exit; deployed honestly ships it disabled.
5. **Billing has no sidebar entry and no `data-testid`s** — reachable only by URL; UX assertions must use visible copy.
6. **Peptide/protein design is honestly ungated of results but runnably-gated** — the correct behavior; ensure any future E2E does NOT assert peptide/protein candidates (there are none by design).
