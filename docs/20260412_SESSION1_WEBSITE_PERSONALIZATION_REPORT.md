# Session 1 — Website & Registration Personalization: Complete
**Date:** 2026-04-12  
**Branch:** integration/next-phase  
**Session scope:** Track 1A (competitive analysis), 1B (website prototypes), 1C (registration taxonomy), 1D (personalization wiring)  
**Status:** All four tracks DONE

---

## Summary

Session 1 closed all four planned tracks. The personalization system now correctly routes users' declared domain profiles into workflow search scoring (the critical C+ → B+ upgrade from the 2026-03-30 audit). Three full-page website prototypes were built using design patterns extracted from five competitor analyses. The registration taxonomy was expanded from 14 sparse domains to 16 rich domains with subcategory hierarchies, ontology references, and institution_type. The website improvement proposal synthesizes all findings into a prioritized action plan.

---

## Track 1A — Competitive Analysis & Design Brief ✅

### Deliverables
- `docs/20260412_BENCHLING_WEBSITE_ANALYSIS.md` — Graphik font, green accent, eyebrow labels, tile template (icon + 20–25 word description + "Learn more →"), featured summary GEO pattern, meta title formula `"[Feature] for Life Sciences | Benchling"`
- `docs/20260412_SEQERA_WEBSITE_ANALYSIS.md` — Degular font, "The Intelligent Engine for Life Sciences", 3-fragment subheadlines ("Powerful agents. Reproducible workflows. Take your science further, faster."), "Your Data. Your Infrastructure. Your Science." 3-part anaphora, blog title formulas
- `docs/20260412_DNANEXUS_TETRASCIENCE_SYNTHACE_ANALYSIS.md` — DNAnexus: black+bright green, italicized emotional keyword in hero, tabbed feature sections (5 benefit tabs), "Download the ROI Study" lead magnet. TetraScience: coined "Sciborgs", "Era of AI" framing, 10x/40x stat format. Synthace: "Months off discovery biology", pain/solution alternating layout, calculator as GEO resource
- `docs/20260412_WEBSITE_COMPETITIVE_ANALYSIS.md` — Master comparison matrix (≥8 competitors, visual design, copy, SEO, GEO patterns, cross-competitor summary table)
- `docs/20260412_BIOMATE_WEBSITE_IMPROVEMENT_PROPOSAL.md` — 10 actionable recommendations in priority order:
  1. Hero rewrite (3 tested options)
  2. 25-word tile template standardization (all 16 domains)
  3. SEO meta titles (`"[Feature] | BioMate"` for every page)
  4. Domain landing pages (`/workflows/drug-discovery`, etc.)
  5. GEO featured summary blocks (all blog posts)
  6. Coined term: "Audit-Ready Science" — use in 5+ places immediately
  7. Single accent color selection (own it across the entire site)
  8. Section rhythm (alternate bg-white / bg-slate-50)
  9. ROI calculator (1 week build, high GEO value)
  10. "AI Research" as standalone nav item (mirrors Benchling's "AI" top-nav)

### Key copy rules extracted
| Rule | Apply to BioMate |
|------|-----------------|
| Lead with a verb | "Run your analysis", "Generate your workflow", "Audit every decision" |
| Attach metrics to institution names | "Texas Children's Hospital: 18 min" not "customers: 18 min" |
| Fragment subheadlines | "Peer-validated workflows. Evidence-graded QC. Publication-ready reports." |
| 25-word tile cap | Apply to all 16 domain tiles |
| Visceral time language | "Hours not weeks" / "30 minutes not 3 days" (not just "faster") |
| 3-part anaphora | "Your question. Your data. Your results." |
| Coined term | "Audit-Ready Science" — coinable, unique, GEO-optimized |

---

## Track 1B — Website Prototypes ✅

### Deliverables
**Standalone HTML subfolder** — `frontend/website-prototypes/` — no build step, open directly in any browser.

| File | Variant | Target audience | Lead message | Interactive |
|------|---------|-----------------|--------------|-------------|
| `index.html` | Comparison index | Internal/team | Overview of all 3 | Links to each |
| `variant-a.html` | Science-Forward | PI / senior researcher | "Research question to results. Under 30 minutes." | 5-tab "Why BioMate" section |
| `variant-b.html` | Product-Forward | Lab manager / dept head | "Stop waiting for your bioinformatician." | 4-tab pain switcher, pricing cards |
| `variant-c.html` | Trust & Compliance | IT / clinical / pharma | "AI bioinformatics your compliance team can approve." | 3-segment testimonials, FAQ accordion |
| `shared/styles.css` | Design system | — | CSS foundation for all 3 variants | — |

**React dev-only routes** (also built, inside the main React app):
- `/design-preview` — comparison index
- `/design-preview/a` — Variant A (Science)
- `/design-preview/b` — Variant B (Product)
- `/design-preview/c` — Variant C (Trust)
- All gated behind `import.meta.env.DEV` — zero production surface area

### Design patterns applied in prototypes

**Variant A (Science-Forward, dark):**
- Animated dot eyebrow pill + "AI-Native · 78 Workflows · AWS Batch Execution" (Benchling pattern)
- Hero headline with cyan `<em>` emphasis word (DNAnexus "Trusted" pattern)
- 3-fragment subheadline (Seqera pattern)
- Real ADMET terminal demo (actual output numbers, tool calls, QC pass/fail)
- 8-tile domain grid with workflow counts ("View 18 workflows →", not "Learn more")
- 5-tab "Why BioMate" section with metric + description + quote per tab (DNAnexus tabbed features)
- Dual audit trail cards with inline citations (GATK Van der Auwera, Redfern 2003)
- Statistics attached to institution names (Seqera pattern)

**Variant B (Product-Forward, light):**
- Hero: pain-led headline "Stop waiting for your bioinformatician"
- Stats row: 87%, 23 min, 78 workflows, 0 hallucinations — all scan-ready (DNAnexus ROI-first pattern)
- Interactive pain switcher: 4 tabs (Waiting / Config / QC / Cloud) each showing Before vs After with time callouts using visceral language ("5–14 days" → "23 minutes average")
- Live chat demo window showing GATK4 workflow card being configured
- Results window showing ADMET output with download buttons
- Visible pricing cards (removes buyer evaluation friction) — Free / Lab $199 / Enterprise Custom
- Pain-specific CTAs: "Stop waiting" echoed at bottom

**Variant C (Trust & Compliance, neutral):**
- Hero: dark slate background (institutional gravitas), compliance checklist card with color-coded status (green/blue/amber indicators)
- 8-item compliance checklist: SOC2, data sovereignty, HIPAA-ready, audit log, private deployment, SSO, container pinning, 32 QC profiles
- Private deployment option as a first-class feature section (differentiates from SaaS-only)
- Full audit log demo with timestamps, container SHA, QC citations
- Testimonials segmented by customer type (Clinical / Pharma / Academic) — each with a specific outcome metric
- 6-question FAQ accordion pre-empting IT objections (PHI in prompts? Air-gapped? SOC2 report?)
- "Download security overview" + "Download ROI Study" lead magnets (DNAnexus pattern)
- CTA footer: "SOC 2 Type II report available under NDA · HIPAA BAA on request · Private deployment scoping in 5 business days"

---

## Track 1C — Registration Taxonomy Redesign ✅

### Deliverables
- `backend/lib/galaxy/ai/domain_registry.py` — canonical domain registry (replaces `domain_taxonomy.py` as source of truth)
  - 16 domains (added `spatial_omics`, `computational_chemistry`; `synthetic_biology` already existed)
  - `DOMAIN_SUBCATEGORIES`: 3-level hierarchy (domain → subcategory → topics list)
  - All domains ≥25 topics (drug_discovery=40, spatial_omics=26, synthetic_biology=28)
  - `DOMAIN_ONTOLOGY_REFS`: MeSH, GO, ChEBI IDs for each domain
  - `DOMAIN_TOPICS`: flattened from subcategories via `_flatten_subcategories()`
- `backend/lib/galaxy/ai/domain_taxonomy.py` — re-export shim (backward compatible, exports `DOMAIN_TAXONOMY = DOMAIN_TOPICS`)
- `frontend/client/src/components/domain-profile-selector.tsx`
  - `INSTITUTION_TYPE_OPTIONS`: 6 options (academic / pharma / biotech / hospital / cro / other)
  - `institution_type` Radix Select dropdown at top of form
  - Topics replaced with subcategory accordion (3-level navigation)
  - `DomainProfile` interface now includes `institution_type?: string | null`
- `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`
  - `DomainProfileRequest.institution_type` with 6-value enum validation
  - SQLite schema: `institution_type TEXT` column, safe `ALTER TABLE` migration for existing DBs
  - POST/GET endpoints carry the field
- `backend/lib/galaxy/model/migrations/alembic/versions_gxy/c3f8a1d20260_add_institution_type_to_user_preference.py` — Alembic migration for `user_preference` table

### Fields added (only `institution_type` — no experience_level, no primary_instrument per user direction)

---

## Track 1D — Personalization: Domain Profile → Workflow Search ✅

### Problem fixed
`generate_workflow_unified()` called `workflow_search.search()` with no `user_profile` — the `+2` domain bonus was coded but **never applied**. The personalization system was wired at the storage layer but dead at the scoring layer.

### Files changed

**`backend/lib/galaxy/ai/ai_assistant.py`**
- `_get_user_domain_profile(user_id)` — reads from `user_domain_profiles` in `galaxy_ai_tools.db`, resolves Galaxy numeric user_id → email → domains, 10-min TTL cache
- `_get_preferred_workflow_ids(user_id)` — top-5 workflow IDs from user's domain, 10-min TTL cache
- `generate_workflow_unified()` — fetches profile at top, passes `user_profile=profile, boost_ids=preferred_ids` to every `workflow_search.search()` call
- `_return_nextflow_match()` — emits `scope_notice` when returned workflow's domain is not in the user's declared domains

**`backend/lib/galaxy/ai/unified_workflow_search.py`**
- Added `boost_ids: Optional[List[int]] = None` parameter to `search()`
- Boost IDs pre-seeded into FTS candidate pool before scoring (+1.5 score bonus in re-ranking)
- The `+2` user_profile domain bonus was already coded — now actually receives a profile

**`frontend/shared/galaxy-types.ts`**
- Added `scope_notice?: string` to `WorkflowGenerationResponse` (line 459)

**`frontend/client/src/components/chat-interface.tsx`**
- `scopeNotice` extracted at line 543

**`frontend/client/src/components/chat-message.tsx`**
- `ScopeNoticeBanner` component — dismissible blue info banner, shown above workflow viewer when user's query falls outside their declared domains

### Tests
`backend/lib/galaxy/ai/tests/test_personalization_domain_profile.py` — 5 tests, all passing:
1. Genomics user gets variant calling top-1
2. Drug discovery user gets ADMET top-1
3. Same query → different rankings for different profiles
4. `None` profile is backward-compatible (no crash)
5. `boost_ids` raises candidate score by +1.5

---

## What's Pending From Session 1

| Item | Status | Notes |
|------|--------|-------|
| Apply improvements to actual `landing.tsx` | ❌ Not started | Requires separate design sign-off; prototypes are the input for that decision |
| E2E test: two users, different domain profiles, different rankings | ❌ Not started | Personalization unit tests pass; need a Playwright E2E |
| Resume sync daemon to dev | ❌ Paused | Resume with `bash scripts/sync_to_dev.sh` after all changes committed |

---

## What's Next: Remaining Sessions

### Session 2 — Function Consolidation: UX Surfaces

**Track 2A — Data Upload: S3 / URL fully wired in chat input + workflow panel**
- File upload in chat → progress bar → file chip in message → auto-fill workflow param
- URL import: NCBI/ENA/EMDB accession → resolved URL → stored as `source_url`
- Workflow panel: URL-paste field, "use in workflow" button

**Track 2B — Per-phase parameters, phase control, output management**
- Step-level parameter editing in workflow viewer (not just whole-run)
- Phase resume/skip controls
- Output file management: delete, rename, re-download

**Track 2C — Notification system**
- Email + Slack on run completion/failure
- Webhook endpoint for external integrations

**Track 2D — Workflow file upload (separate from data upload)**
- Upload a custom Nextflow `.nf` + `nextflow.config` as a workflow
- Register in DB, show in search, full execution via existing path

---

### Session 3 — Backend Intelligence

**Track 3A — Cross-session memory: pgvector + semantic retrieval**
- `pgvector` embeddings for session memories
- Cross-session injection: "You asked about ADMET last week" surfaced automatically

**Track 3B — LLM chain routing improvements**
- Better chain vs single-workflow disambiguation
- Drug discovery chain false positives

**Track 3C — Autofix benchmark: 20 cases**
- 20 real failure scenarios, each with known fix
- Run evaluator on AI-generated fixes, score pass/fail

---

### Session 4 — Interface Extensions, Safety, Docker

**Track 4A — Safety: SOC2 + HIPAA audit framework**
- `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md` written (other session)
- Implementation: logging middleware, PHI scrubbing in prompts, BAA template

**Track 4B — Docker: image shrink**
- `docs/20260412_DOCKER_SHRINK_ANALYSIS.md` written (other session)
- Build multi-stage images, strip dev deps, push slim tags

**Track 4C — Virtual lab connectors**
- OpenTrons (priority): Python SDK + HTTP API at `http://<robot-ip>/server/`
- Benchling integration: data import from Benchling as partner (not competitor)
- BaseSpace Clarity LIMS, Strateos cloud lab API
- `docs/20260412_VIRTUAL_LAB_CONNECTOR_SURVEY.md` written (other session)

---

### Session 5 — Benchmarking & Autotest

**Track 5A — Consistency runner**
- Run same query N times, measure workflow selection variance
- `docs/20260412_PUBLIC_BENCHMARK_POSITIONING.md` written (other session)

**Track 5B — SimulatedUser E2E suite**
- `SimulatedUser` class + 7 Playwright E2E tests
- Tests cover multi-turn conversations, domain switching, parameter correction

**Track 5C — LLM judge for workflow quality**
- LLMJudge evaluates generated workflows against gold standard
- Autofix benchmark: 20 cases (separate session)

---

## Key Files Reference

```
docs/
  20260412_BENCHLING_WEBSITE_ANALYSIS.md
  20260412_SEQERA_WEBSITE_ANALYSIS.md
  20260412_DNANEXUS_TETRASCIENCE_SYNTHACE_ANALYSIS.md
  20260412_WEBSITE_COMPETITIVE_ANALYSIS.md
  20260412_BIOMATE_WEBSITE_IMPROVEMENT_PROPOSAL.md
  20260412_FIVE_SESSION_PARALLEL_PLAN.md
  20260412_SESSION1_WEBSITE_PERSONALIZATION_REPORT.md  ← this file

frontend/website-prototypes/
  index.html                         ← comparison index (open in browser directly)
  variant-a.html                     ← Science-Forward, dark, cyan
  variant-b.html                     ← Product-Forward, light, blue + pricing
  variant-c.html                     ← Trust/Compliance, neutral, emerald + FAQ
  shared/styles.css                  ← shared design system

frontend/client/src/pages/website-prototypes/
  index.tsx                          ← React dev-only comparison page
  variant-a-science.tsx              ← React version of Variant A
  variant-b-product.tsx              ← React version of Variant B
  variant-c-trust.tsx                ← React version of Variant C

backend/lib/galaxy/ai/
  domain_registry.py                 ← canonical taxonomy (16 domains, ≥25 topics, ontology refs)
  domain_taxonomy.py                 ← re-export shim
  ai_assistant.py                    ← personalization wiring (_get_user_domain_profile, boost_ids)
  unified_workflow_search.py         ← boost_ids + user_profile scoring
  tests/test_personalization_domain_profile.py

frontend/client/src/components/
  domain-profile-selector.tsx        ← institution_type + subcategory accordion
  chat-interface.tsx                 ← scopeNotice extraction
  chat-message.tsx                   ← ScopeNoticeBanner component

backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py   ← institution_type endpoint
backend/lib/galaxy/model/migrations/alembic/versions_gxy/c3f8a1d20260_add_institution_type_to_user_preference.py
```
