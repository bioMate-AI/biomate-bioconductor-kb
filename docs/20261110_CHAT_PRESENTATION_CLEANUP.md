# Chat presentation cleanup — Track D (2026-11-10)

Branch `track/d-chatui` → PR into `integration/unmerged-20261110`. Source issues:
`docs/20261110_EPAR_DATASET_CHAT_UX_REVIEW.md` §3 (C2–C6) plus the founder's
binding corrections given during the work (listed below). Not deployed; no
`sync_to_dev.sh` was run.

## Founder corrections that override the original spec

1. Remove the two buttons under research answers ("Save to project",
   "规划我的数据分析") outright. No "⋯" menu. Also remove the duplicate
   "Save to notes" / "Make instruction" buttons in the citation panel. Keep only
   the existing icon row: copy · save as file · regenerate · 👍 · 👎.
2. The UI shows one language at a time, for both locales. Every user-visible
   string on the touched surfaces goes through i18n with complete en and zh
   entries. There is no cross-language fallback and no mixed text.

## What changed (root cause → fix)

| # | Problem | Root cause | Fix |
|---|---|---|---|
| C2 | Two action rows under each answer | `ResearchResponseDisplay` rendered its own button row. The thumbs-up/down widget appeared only on workflow messages. | Removed the button row. Removed `onCheckAgainstData` / `onPlanAnalysisWithData`, `lib/analysis-plan-draft.ts` and the `research_plan.*` keys. `chat-message.tsx` now renders **one** quiet row (`data-testid="message-action-row"`) for every assistant type: copy · save as file · regenerate · 👍 · 👎, plus the existing conditional extras (download outputs, read aloud, redo as validated run). On older answers the row is muted and appears on hover. `InlineFeedbackWidget` is localized, and its rules-of-hooks bug is fixed (it returned early before `useState`). |
| C2 | Duplicate save/instruction in the citation panel | — | Deleted both, along with their handlers. |
| C3 | Over-built citations, expanded by default | `showCitations=true`; per-item expand cards; "open" and "Read" opened the same pane | Literature sources start collapsed as a single "N sources" line. Expanding shows numbered one-line references (`[n] title · journal · year`); the title links to DOI → PubMed → URL, followed by one **Read** action. "How this was searched" is now a footnote ("Searched · 3 of 15 kept"), with the per-source rows in a tooltip and aria-label. Workflow tool citations keep their card (APA/BibTeX copy and methods tab), minus the duplicate "open". |
| C3 | "Read" never showed full text | No fetch path existed. `toEvidenceCitations` dropped ids. | New authenticated route `GET /api/literature/fulltext?pmcid|pmid|doi` (`server/literature-fulltext-routes.ts`). It queries Europe PMC `search` (resultType=core) and, for OA articles, `{PMCID}/fullTextXML`. JATS is parsed to sections and paragraphs; figures, tables, formulas and refs are dropped. It returns abstract, full text, license and links, or an honest `fullTextStatus` of `not_open_access`, `not_found` or `unavailable`. Inputs are validated, results cached for 6 h (200 entries), upstream timeout is 12 s, and upstream failure returns 502. `SourceReaderPane` fetches it on open and shows the abstract, the full text and an honest status line. `toEvidenceCitations` now passes doi/pmid/pmcid/url/locus/recency. |
| C4 | Redundant title (breadcrumb + title + banner) | Hard-coded `'Unfiled' / 'chat'` breadcrumb, plus `ActiveProjectBanner` on every route | New `ChatHeaderTitle` component: one line with the title, a small project chip (links to the project) and a live dot. The breadcrumb is removed. `ActiveProjectBanner` returns null on the chat route (`isChatRoute('/')`). The stored "New Chat" sentinel displays as `chat.new_chat`. |
| C5 | Landing redundancy; design card | — | The heading is kept. `chat.placeholder` now reads "描述您的研究目标，或附加数据…" / "Describe your research goal, or attach data…". The design card is hidden by the new `DESIGN_GENERATE_ENABLED` flag (`VITE_ENABLE_DESIGN_GENERATE`, default off), which also gates the `/design` route (NotFound when off). `nav.design_generate` has no nav entry in this tree, so the route is the only other gate. The catalogue keeps the design module for the router self-test (`landingModules()` filters it). |
| 5 | Composer kept the draft after send (`/?project&attachFile&draft`) | `initialDraft` lived in RootRoute state for the page's lifetime. `ChatWithArtifacts` is keyed by the session id, so the first send (new chat → real session) remounted it with a fresh "applied" ref, and the draft was applied again. `?q=` had the same latent re-send risk. | The draft is consumed at its source: `lib/one-shot-url-param.ts` (`useOneShotUrlParam`, `useApplyInitialDraft`) strips only `draft` (`project`/`attachFile` stay) and clears it once applied. `initialMessage` (`?q=`) is likewise cleared via `onInitialMessageConsumed`. |
| 6 | Titles like "[BioMate dataset: …" | Titles were sliced from the raw first user message, including composer system blocks | `shared/chat-system-blocks.ts` (`stripSystemBlocks`, `attachedNamesFromBlocks`, `titleSourceText`, `fallbackTitle`) is used by `POST /api/sessions/generate-title`, the client title derivation in `lib/chat-history.ts` (with a legacy-title cleanup on load) and the user bubble in `chat-message.tsx`. An attachment-only message is titled after its file names. The LLM title prompt now asks for the query's language. |
| C6 | English leaks in chat | Hard-coded literals | Chips (Completed/Running/Ready/…), Open, the answer-block links, "You", chain-suggestion copy, review prompts, IND chips, the benchmark-evidence card, the whole citation panel, the reader, the feedback popover, show/hide chat, sheet close label (new `closeLabel` prop) and the landing card copy are all localized. Landing copy uses `cold_start.copy.<slug>`, 154 strings in both bundles. The redundant "已在面板中" chip is removed (`chat.in_panel` deleted). |

Research follow-up questions (previously `console.log` only) now pre-fill the composer for review. They never auto-send.

## Locale keys

New keys exist only under `chat.*`, `citations.*` and `cold_start.*`, each in
both `en` and `zh`. Removed: `chat.in_panel`, `citation_reader.*`,
`research_plan.*`, `cold_start.hospital_*` (now covered by `cold_start.copy`).

## Tests

- `server/literature-fulltext-routes.test.ts`: the route contract against
  **recorded, unmodified Europe PMC responses** in
  `server/__fixtures__/europepmc/`. It covers auth 401, 400 on invalid ids, OA
  full text (DESeq2, PMC4302049), the cache, closed access (Hallmarks of cancer
  DOI), not indexed (an EPAR-test DOI), full-text-leg failure and the 502 path.
- `__locale__/chat-surfaces.locale-{en,zh}.test.tsx`: strict single-bundle i18n
  with no fallback; a missing key renders `⟦MISSING⟧`. Each renders the action
  row and 👎 popover, the research answer with expanded references, footnote and
  conflict row, the reader, the workflow chip in five states plus Open, the
  header, and every landing card, track and domain. en must contain no CJK. zh
  must contain no Latin words except an allowlist of proper nouns and scientific
  identifiers; paper titles and other user data are excluded.
- `lib/one-shot-url-param.test.tsx`: reproduces the remount and asserts the
  draft is applied once. It also contains a guard test showing the old
  behaviour re-applies the draft.
- `shared/chat-system-blocks.test.ts` and `lib/chat-history.test.ts`: the title
  sanitizer, legacy titles, and `updateSession` title derivation.
- `chat-header-and-chip.test.tsx`, `chat-message.research-citation-panel.test.tsx`,
  `benchmark-evidence.research-answer.test.tsx`,
  `citation-panel.{evidence,retrieval}.test.tsx`, `source-reader-pane.test.tsx`
  and `cold-start-dashboard.test.tsx` were updated or added. They assert the
  removed buttons are absent and that the single row is present on research and
  plain answers.

## Known gaps / next steps

- The landing **seed prompts** (the text placed in the composer when a card
  example is clicked) remain canonical English. They are the prepared-example
  lookup keys and the router self-test surface. Translating them means
  re-verifying chat routing on Chinese prompts, which belongs to the routing
  track. The card copy itself is fully localized.
- Research citations from the backend carry title/authors/year/journal/doi/pmid
  and the abstract, but not pmcid or url. The reader resolves by DOI/PMID, which
  covers them. Passing `pmcid` from `research_agent.Citation` would save one
  lookup but is not required.
- Retrieval relevance (unrelated sources kept for the EPAR question, review §3
  C3) is research-agent quality and was not addressed here.
- **Needs live verification on dev after merge and sync:** Read on an OA PMID
  shows full text, and on a closed DOI shows the honest status (dev egress to
  `www.ebi.ac.uk`). Sending from `/?project=…&attachFile=…&draft=…` leaves an
  empty composer. A new chat with an attached dataset gets a clean title. The
  chat route shows the one-line header with no banner. The landing has three
  cards and the new placeholder. Visual check of the quiet action row (hover
  reveal on older answers).
