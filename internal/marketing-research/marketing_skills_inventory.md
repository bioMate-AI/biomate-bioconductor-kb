# Marketing Skills Inventory & Public-Skill Research

Date: 2026-10-04. Researcher notes for BioMate's marketing toolkit.
Deliverables: (A) local skill inventory; (B) vetted public marketing skills collected under
`docs/marketing/skills/` (+ README there).

---

## A. Local skill inventory (what already exists)

Enumerated these dirs: `/Users/kky/.claude/skills`, `/Users/kky/.cursor/skills-cursor`,
`/Users/kky/biomate-review/.claude/skills`, `/Users/kky/biomate/.claude/skills`,
`/Users/kky/biomate/skills`.

### `/Users/kky/.claude/skills/synced/<uuid>/` (Anthropic default skills, synced)
`morning, deep-research, xlsx, pdf, import-memory, docs, skill-creator, pptx,
google-workspace, chrome-browser, built-in-browser, computer-use, docx`.
→ General-purpose Anthropic skills. **None marketing-related.** (`deep-research` is generic
research, not marketing.)

### `/Users/kky/.cursor/skills-cursor/` (Cursor workflow skills)
`automate, autopilot, canvas, create-hook, create-rule, create-skill, create-subagent,
deploy-with-vercel, goal, loop, migrate-to-skills, new-repo, onboard, origin, rename-chat,
review, review-bugbot, review-security, sdk, share, shell, split-to-prs, statusline,
update-cli-config, update-cursor-settings, visualize`.
→ All dev/coding-agent workflow tools (code review, repo ops, hooks, Vercel deploy,
visualization of code/data). **None marketing-related.**

### `/Users/kky/biomate-review/.claude/skills/` and `/Users/kky/biomate/.claude/skills/`
`systemic-root-cause` (debugging playbook). **Not marketing.**

### `/Users/kky/biomate/skills/`
`biomate` (run bioinformatics/drug-discovery/clinical workflows). **Not marketing.**

### Inventory conclusion
**No marketing-specific skill exists anywhere locally.** Closest adjacency is the generic
`deep-research` skill (useful for market/competitor research but not marketing-specific) and
Cursor's `visualize`/`canvas` (generic visualization). Confirms the known prior assessment.

---

## B. Public marketing-skill candidates & vetting

Search queries used (WebSearch): "anthropics skills github marketing SKILL.md";
"awesome claude skills marketing collection github".

### Candidate 1 — anthropics/knowledge-work-plugins (OFFICIAL) — COLLECTED
- URL: https://github.com/anthropics/knowledge-work-plugins ; marketing plugin at
  `/tree/main/marketing/skills`.
- License: **Apache-2.0**. Trust: official Anthropic, ~26.1k stars, 1,067 commits; built for
  Claude Cowork / Claude Code. Pinned commit `8444efcd48f7012f09797778a36a33e73d0861f4`
  (2026-10-01).
- Contents: 8 marketing skills — `brand-review, campaign-plan, competitive-brief,
  content-creation, draft-content, email-sequence, performance-report, seo-audit`.
- Safety: each is a single `SKILL.md`, pure Markdown. Grep for
  `curl/wget/requests.post/eval/base64 -d/exfiltrat` across skill bodies → **NONE**.
- Decision: **DOWNLOAD ALL 8** (SKILL.md each) + repo LICENSE. Covers competitor analysis,
  positioning/voice, launch/campaign, content/copy, email, SEO, analytics/reporting.

### Candidate 2 — coreyhaines31/marketingskills (community) — PARTIALLY COLLECTED
- URL: https://github.com/coreyhaines31/marketingskills . License **MIT**. Author Corey
  Haines (reputable SaaS marketer; Conversion Factory). Pinned commit
  `dda3841f0b294e01e93b1541486beefbfab0915e` (2026-10-02).
- Contents: 60+ skills. Skills themselves are Markdown (`SKILL.md` + `references/*.md` +
  `evals/*.json`). Repo ALSO ships `tools/clis/*.js` (65+ third-party API connectors:
  Ahrefs, Apollo, Klaviyo, GA4, HubSpot-adjacent, etc.) and validator shell scripts.
- Safety assessment:
  - The JS CLIs are real network integrations requiring API keys — **not downloaded**
    (out of scope + reduces attack surface; not malicious, just unnecessary).
  - Selected gap skills have **no hard dependency** on the CLIs in their SKILL.md bodies
    (grep for `tools/clis|node tools|you must run` → none).
  - Only `curl` hits in selected references are in `public-relations/references/newsjacking.md`:
    read-only GETs to Google News RSS + HN Algolia API (no creds, no POST). Benign.
  - No `requests.post/eval/base64 -d/.env/AWS_SECRET/private.key` in any selected reference.
- Decision: **DOWNLOAD the 9 gap-filling skills** the official repo lacks, SKILL.md +
  `references/*.md` only (skip evals JSON and all JS/sh): `pricing, product-marketing,
  sales-enablement, public-relations, customer-research, launch, competitors,
  competitor-profiling, marketing-plan`. Rationale: these cover pricing, positioning/PMM,
  sales enablement, PR, customer research, GTM — categories absent from Candidate 1.

### Candidate 3 — OpenClaudia/openclaudia-skills — REVIEWED, NOT DOWNLOADED
- URL: https://github.com/OpenClaudia/openclaudia-skills . License **MIT**. 78 Markdown
  skills across 11 categories (SEO, content, email, ads, analytics/research, strategy incl.
  `pricing-strategy, icp-builder, product-marketing, demand-gen`). Claims API-integration
  ("write/publish/send") execution model.
- Decision: **LIST, not download.** License-clean and reputable, but heavy overlap with
  Candidates 1 & 2. Kept as a vetted backup pool. (No PR / sales-enablement category.)

### Candidate 4 — ayrshare/marketingskills & syntax-syndicate/marketing-skills — NOT DOWNLOADED
- Forks/variants of the same "Marketing skills for Claude Code (CRO, copywriting, SEO,
  analytics, growth)" codebase as Candidate 2. Duplicate coverage. Listed only.

### Candidate 5 — thatrebeccarae/claude-marketing — NOT DOWNLOADED (license unconfirmed)
- URL: https://github.com/thatrebeccarae/claude-marketing . 56 skills/agents for Klaviyo,
  Shopify, GA4, Looker Studio, paid media. **License not confirmed** at review; tool-
  integration heavy (operates on live ad/e-commerce accounts). Deferred pending license +
  deeper safety pass. Listed in README.

### Candidate 6 — alirezarezvani/claude-skills (`marketing-skill`) — NOT DOWNLOADED
- Single community skill; license not confirmed; superseded by broader vetted sources.

### Other references seen in search (context only, not skill sources)
- `BehiSecc/awesome-claude-skills` and `hesreallyhim/awesome-claude-code` issues #1019/#1033
  are curated lists / resource pointers, not skill repos themselves.

---

## Collection result
- 17 skill folders downloaded under `/Users/kky/biomate-review/docs/marketing/skills/`
  (8 Apache-2.0 official + 9 MIT gap-fillers), plus both LICENSE files and a README.
- No global config touched (`~/.claude`, `~/.cursor` untouched).
- All writes confined to `docs/marketing/skills/` and this notes file.

## Gaps / open items
- `thatrebeccarae/claude-marketing` license needs confirming before any use.
- Did not exhaustively diff OpenClaudia's 78 skills vs. the collected set for unique niche
  skills (e.g. demand-gen, ASO); flagged as a backup pool instead.
