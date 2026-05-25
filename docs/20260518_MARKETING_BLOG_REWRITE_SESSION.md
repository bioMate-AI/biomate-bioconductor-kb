# Marketing blog rewrite session — 2026-05-18

## Goal

The previous teammate had drafted four "Agentic Biology" founder-voice
essays (posts 1, 5, 8, 9) in `reference/` for the BioMate marketing
funnel. They were heavily LC-MS / metabolomics-centric, reflecting an
early scope. Current BioMate scope is much broader: 2,455 nf-core
workflows across 34 domains, end-to-end drug development (ADMET, docking,
PBPK, BOIN dose-escalation, IND §2.6.1 LLM narrative), cryo-EM, multi-
omics, CRO compliance, auto-loop QC, and the regulatory LLM v6/v7
trained in-house.

The task was to reframe the four posts around the current scope, demote
LC-MS to one example among many, and stage them for publication.

## Decisions

- **Two surfaces per post:** Substack long-form (~1,500 words) +
  LinkedIn feed post (~2,400 chars, under the 3,000-char limit).
  Rationale: LinkedIn Articles get heavily downranked vs. native feed
  posts. The dominant playbook is short teaser → Substack/site link.
- **Figures in draw.io XML.** Plain text, git-diffable, round-trips
  losslessly with PNG/SVG export. Edit in [app.diagrams.net]
  (https://app.diagrams.net), VS Code extension, or desktop app.
  README documents alternative tools (Excalidraw, Figma, Mermaid, D2,
  Penpot) and per-platform export sizes.
- **BioMate trial link:** `https://biomate.ai/try` used as the CTA.
  ⚠️ Confirm correct production URL before publishing — may need
  global sed to `biomate.ai/signup`, `app.biomate.ai`, etc.
- **Post 5 framing rebuilt around a triangle:** prediction → simulation
  → real-world validation, with explicit complementary relationships
  (none of the three is useful alone) and four application-level
  benefits (fewer failed trials, faster decisions, compounding learning,
  audit-ready submissions). This was the user's specific framing
  request after the first draft over-emphasized prediction+simulation
  without real-world validation.

## Files

```
business/marketing/blog_posts/
├── post_1_agentic_biology_intro.md       ← Life science fragmentation; what BioMate does/doesn't
├── post_5_substack.md                    ← Triangle framing, long-form
├── post_5_linkedin.md                    ← Short feed post + hero image instructions
├── post_8_evidence_grounded_ai.md        ← Hallucination data + curated RAG sources
├── post_9_domain_specific_llms.md        ← Frontier+RAG default; regulatory LLM is the exception
└── figures/
    ├── README.md                                  ← Export sizes + alternative tools
    ├── post_5_triangle.drawio.xml                 ← Figure 1 (closed loop)
    └── post_5_benefits_stack.drawio.xml           ← Figure 2 (program → portfolio → business)
```

## Key reframings vs. the originals

| Post | Original framing                        | Rewritten framing                                              |
|------|-----------------------------------------|----------------------------------------------------------------|
| 1    | LC-MS queue + mass spec core            | 40-year fragmentation across 8 drug-program specialties        |
| 5    | Prediction tracking only                | Prediction + simulation + real-world validation triangle       |
| 8    | LC-MS retention times, HMDB/GNPS focus  | FIH dosing, nf-core ATAC-seq, hERG/Cmax, cryo-EM resolution    |
| 9    | Frontier+RAG, no exceptions             | Frontier+RAG default + regulatory LLM v6/v7 as principled exception |

## Pending

- Confirm `biomate.ai/try` is the correct CTA URL. If different, sed
  across all 8 markdown files in `business/marketing/blog_posts/`.
- Render `figures/*.drawio.xml` to PNG/SVG at the sizes in
  `figures/README.md` before publishing.
- Decide host for the long-form essays (Substack vs. on-domain blog).
- User to review readability of posts 1/8/9 substack versions and the
  short LinkedIn versions of all four posts.

## Session 2 — 2026-05-19

Applied the two-version + draw.io treatment to posts 1, 8, 9:

- Renamed `post_{1,8,9}_*.md` → `post_{1,8,9}_substack.md`.
- Added figure callouts + trial link to each substack.
- Lightly restructured post 1's opening paragraph into a bullet list
  for scannability (the eight-specialty walk-through).
- Created LinkedIn feed posts (~2,500 chars each) for posts 1, 8, 9.
- Created three new draw.io figures:
  - `post_1_fragmentation_map.drawio.xml` — 8 specialty silos with the
    human-handoff wall and BioMate orchestration layer underneath.
  - `post_8_rag_stack.drawio.xml` — 4-layer evidence-grounded
    architecture from user query through curated sources to grounded
    response.
  - `post_9_options_matrix.drawio.xml` — 4 LLM build options as a
    cost/control gradient with "default" (option 1) and "exception"
    (option 3 = regulatory LLM) callouts.
- Updated `figures/README.md` with all five current figures.

## Commits

- `27eef3f87` (2026-05-18) — initial 4 posts + post 5 two versions + 2
  figures
- `45b6a38e2` (2026-05-18) — this session doc
- Session 2 (2026-05-19) — pending commit at end of this session
