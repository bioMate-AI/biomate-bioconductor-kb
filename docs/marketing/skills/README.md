# BioMate Marketing Skills Toolkit

Vetted, public **agent skills** (Anthropic `SKILL.md` format) collected for BioMate's
marketing work. Each skill is a folder with a `SKILL.md` (YAML frontmatter + Markdown
instructions) and optional `references/` Markdown. These are *instruction* skills — no
executable scripts were downloaded (see **Safety** below).

Collected: 2026-10-04. All downloaded skills are license-compatible (Apache-2.0 / MIT).

## How to use

Point a Claude/Cursor agent at a skill folder, or copy a folder into a project/global
skills directory (e.g. `.claude/skills/`). This directory is a *catalog* under `docs/`;
nothing here is installed into global config.

## Source 1 — Anthropic `knowledge-work-plugins` (OFFICIAL)

- Repo: https://github.com/anthropics/knowledge-work-plugins (marketing plugin:
  https://github.com/anthropics/knowledge-work-plugins/tree/main/marketing/skills)
- License: **Apache-2.0** (`LICENSE-anthropic-knowledge-work-plugins-Apache-2.0.txt`)
- Commit pinned: `8444efcd48f7012f09797778a36a33e73d0861f4` (2026-10-01)
- Why trusted: official Anthropic repo, ~26k stars; built for Claude Cowork / Claude Code.
- Skills are pure Markdown (no bundled scripts).

| Skill | One-line purpose |
|---|---|
| `competitive-brief` | Research competitors → positioning/messaging comparison with gaps, opportunities, threats (battlecards). |
| `brand-review` | Review a draft against brand voice/style/messaging pillars; flag deviations by severity with before/after fixes. |
| `campaign-plan` | Full campaign brief: objectives, audience, messaging, channels, week-by-week content calendar, success metrics. |
| `content-creation` | Draft marketing content across channels (blog, social, email, landing, PR, case study) with channel formatting + SEO. |
| `draft-content` | Channel-specific drafting with headline/subject-line options and SEO recommendations. |
| `email-sequence` | Multi-email sequences: copy, timing, branching, exit conditions, A/B suggestions, benchmarks. |
| `performance-report` | Marketing performance report: metrics, trend analysis, wins/misses, prioritized optimizations. |
| `seo-audit` | SEO audit: keyword research, on-page, content gaps, technical checks, competitor comparison, action plan. |

## Source 2 — `coreyhaines31/marketingskills` (community, reputable author)

- Repo: https://github.com/coreyhaines31/marketingskills
- License: **MIT** (`LICENSE-coreyhaines-marketingskills-MIT.txt`)
- Commit pinned: `dda3841f0b294e01e93b1541486beefbfab0915e` (2026-10-02)
- Author: Corey Haines (technical marketer / founder, Conversion Factory & AI Marketing
  Training) — well-known SaaS-marketing practitioner.
- Downloaded **only** the gap-filling skills the official repo lacks, and only their
  `SKILL.md` + `references/*.md` (Markdown). Eval JSON and the repo's `tools/clis/*.js`
  API integrations were **NOT** downloaded (see Safety).

| Skill | One-line purpose |
|---|---|
| `pricing` | Pricing decisions, packaging, freemium/free-trial, tier structure, monetization strategy. |
| `product-marketing` | Create/update a product-marketing context document (positioning, ICP, messaging) that other skills consult. |
| `sales-enablement` | Sales collateral: pitch decks, one-pagers, objection-handling docs, demo scripts, win/loss. |
| `public-relations` | Earned media, journalist outreach, story angles, newsjacking, crisis comms, podcast prep. |
| `customer-research` | Conduct/analyze/synthesize customer & ICP research; interviews, surveys, transcript analysis. |
| `launch` | Product/feature launch and go-to-market planning (incl. Product Hunt). |
| `competitors` | Competitor comparison / "alternative" / "vs" pages for SEO and buyer-facing use. |
| `competitor-profiling` | Research & profile competitors from their URLs into structured competitor profiles. |
| `marketing-plan` | Comprehensive marketing / growth / GTM plan (AARRR, budget, market sizing, measurement). |

## Sources reviewed but NOT downloaded

- **`OpenClaudia/openclaudia-skills`** — https://github.com/OpenClaudia/openclaudia-skills
  — License **MIT**; 78 Markdown skills (SEO, content, email, ads, analytics, strategy incl.
  `pricing-strategy`, `icp-builder`, `product-marketing`). Reputable and license-clean, but
  content overlaps heavily with the two sources above; listed here as an additional vetted
  pool to draw from if a specific gap appears. Not downloaded to avoid duplicate coverage.
- **`ayrshare/marketingskills`** / **`syntax-syndicate/marketing-skills`** — forks/variants of
  the same "marketing skills for Claude Code" codebase as Source 2; not downloaded (duplicate).
- **`thatrebeccarae/claude-marketing`** — https://github.com/thatrebeccarae/claude-marketing
  — 56 skills/agents for Klaviyo, Shopify, GA4, Looker, paid media. License not confirmed at
  review time and it is tool-integration heavy (runs against live ad/e-commerce APIs); **not
  downloaded** pending a license + safety pass. Listed for future consideration.
- **`alirezarezvani/claude-skills` (`marketing-skill`)** — single community skill; license not
  confirmed; superseded by the broader vetted sources above.

## Safety notes

- Every downloaded file is Markdown instructions/reference text. No `.js`/`.py`/`.sh` scripts
  were copied.
- Source 2's repo ships `tools/clis/*.js` connectors that call third-party APIs (Ahrefs,
  Apollo, Klaviyo, GA4, etc.) with user-supplied API keys. **These were deliberately excluded.**
  The downloaded `SKILL.md` bodies do not hard-depend on those CLIs.
- `public-relations/references/newsjacking.md` contains example `curl` commands against
  **public, read-only** endpoints (Google News RSS, Hacker News Algolia API). No credentials,
  no data exfiltration, no POST/write calls. Reviewed and judged benign; the agent runs them
  only if a user explicitly follows that reference.
- No skill was found that exfiltrates data or auto-executes untrusted code.

## Provenance

Local skill inventory + full candidate vetting notes:
`internal/marketing-research/marketing_skills_inventory.md`.
