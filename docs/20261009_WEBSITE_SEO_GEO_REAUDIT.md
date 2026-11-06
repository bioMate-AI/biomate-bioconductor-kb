# BioMate website: search and AI-answer visibility re-audit

Date: 2026-10-09. Scope: local marketing source, earlier SEO/GEO documents, public search spot checks, current official search documentation. This is not a Search Console, Bing Webmaster, server-log or measured ChatGPT citation audit. The user's reported low AI-search score has not been independently reproduced; the scoring tool, prompt set, model settings and baseline are not yet available.

## Conclusion

BioMate is discoverable by name. The next priority is non-branded task discovery and trustworthy, current, citable evidence. More keywords, more FAQ markup or an enlarged llms.txt are not a sufficient strategy. Preserve the restrained homepage and put scientific depth on well-linked capability, evaluation and research pages.

The redesign introduced real metadata regressions: the homepage lost its entity markup and social card metadata, and the two new service/research pages omitted social metadata, structured data and analytics. These are implementation defects, not evidence of a measured ranking loss.

## Observations and repairs in this change

| Finding | Action/status |
| --- | --- |
| Benchmark FAQ static rows collided with global accordion `.bm-faq-item` CSS: rounded boxes with zero horizontal padding | Scoped editorial component; divided question/answer columns on desktop, stacked on mobile; all seven answers remain in HTML without scripts |
| Summary table extended beyond the mobile viewport | Accessible, keyboard-focusable horizontal scroll region; table semantics retained |
| Homepage metadata removed | Restored Organization, WebSite, WebPage and SoftwareApplication JSON-LD; social cards and site-guide link. No invented search endpoint, ratings or hidden FAQ |
| New drug-discovery and research-engines pages lacked metadata/measurement | Added canonical-aligned Open Graph, Twitter cards, WebPage/Breadcrumb JSON-LD and existing GA4 tag |
| FAQ schema covered only part of the visible Q&A and differed in wording | Synchronized all seven questions and answers. This verifies consistency, not scientific validity |
| Public canonical pages absent from sitemap, including benchmark deep dives, connectors and recent articles | Added missing canonical public URLs; excluded authentication and noindex pages. No guessed lastmod dates for added legacy pages |
| Homepage, service/library and five survey sitemap dates predated this redesign | Updated dates for known October 9 changes, not every page |
| Extended AI index retained drug-only positioning and July facts | Updated positioning; explicitly preserved July snapshot date and marked detailed facts for revalidation rather than claiming all are fresh |

Initial inventory: 97 top-level HTML files. Two lacked canonicals (blog-tmc and LLM comparison supplement); four authentication pages are not SEO landing pages. Thirteen pages lacked a conventional external GA tag, including the two new pages now repaired. Script presence is not proof that analytics events are delivered. All existing JSON-LD parsed as JSON; parsing is not schema validation or Google eligibility.

Existing protections retained: canonical homepage `/`, robots allowance for OAI-SearchBot, public sitemap and llms.txt, substantial static page text, dedicated task landing pages, Wikidata identity. Existing external-profile sameAs links on About require verification: listing drafts are not proof a profile exists or belongs to BioMate.

## Public retrieval spot checks

Queries tested via the available web search tool on October 9:

- `BioMate AI biomedical research platform`: returned BioMate homepage, About, Tutorials, Features, Blog, Pricing and public connector repository. Homepage result used older wording; search cache freshness differs from current deployed content.
- `"AI drug discovery platform" "BioMate"`: returned the older drug-focused homepage description.
- `"AI bioinformatics workbench" RNA-seq drug discovery`: BioMate did not appear in the returned result list; other scientific skills repositories and services did.

These are a small convenience sample, not a controlled rank test, full query coverage, proof of a Google/Bing index state or actual ChatGPT-answer citations. Search-engine output is not evidence that BioMate is absent everywhere. No causal claim is made between markup and observed results.

## Prioritized remaining work

### 1. Verify discovery and measure a reproducible baseline

- Inspect Google Search Console and Bing Webmaster coverage/canonicals for homepage, drug discovery, engines, benchmark deep dives, connectors, and five surveys. Inspect `/`, `/index.html`, www/non-www and HTTP/HTTPS redirects before changing them.
- Verify real crawler access in server/CDN logs: successful requests, response bodies, challenge/403/429 rates. Merely sending a spoofed bot user-agent does not prove access from the genuine crawler IPs. OAI-SearchBot is already allowed by robots; verify network/security rules against official ranges without weakening security generally.
- Submit updated sitemap or request recrawl through the existing verified webmaster account. IndexNow is an optional supported submission route after configuration, not a replacement for indexing quality.
- Use 24 fixed prompts: 4 branded, 8 task-specific, 4 comparisons, 4 evidence/methodology, 4 Chinese-language. Include RNA-seq analysis, multi-omics comparison, target prioritization, ADMET, cyclic-peptide design and reproducibility. Keep model/version, search enabled, geography, fresh conversation state and date recorded. Run three repeats per prompt/system; retain answers and cited URLs.
- Report separate metrics: discovery, mention rate, citation rate, correct capability attribution, correct limitations and qualified visits. Do not collapse them into an unexplained “AI score.” Measure generic and branded queries separately. Account for stochastic answers and indexing lag.
- Track actual AI referral visits and demo/signup conversions in existing analytics, with attribution limitations. Do not promise an uplift percentage.

### 2. Make the science citable, not merely promotional

- Audit each public benchmark claim against the exact run artifact: evaluation date, software/model version, dataset/split, numerator/denominator, metric definition, scorer, baseline conditions and limitations. Publish public-safe methods and downloadable results where disclosure is permitted.
- Existing `realbio.html` and benchmark topic pages are the starting point; strengthen and connect them rather than create another overlapping benchmark page.
- Resolve 20 vs 26 QC gate counts across FAQ/index/other pages and define “indexed,” “validated,” “tested,” and “production execution.” A catalog count is not evidence every workflow was validated end-to-end.
- Review BixBench 92.7% vs Biomni 88.7% comparability before presenting it as direct superiority. Separate self-run internal scores from published competitor numbers and independent evaluation. Homepage restoration deliberately did not add these statistics.
- Review “96.3% ADMET accuracy”: endpoint-specific prediction performance is not interchangeable with workflow/property-check correctness. Give the endpoint, metric, reference labels and sample composition.
- Review “FDA-accepted 2-fold accuracy window” and “FDA-standard compounds”: a benchmark acceptance criterion must not imply regulatory endorsement. Resolve against original study and relevant guidance before rewriting.
- Remove unsupported blanket statements that all general-purpose models fail or that all results are independently evaluated. Fix metadata as well as visible prose once the evidence review establishes exact replacements.
- Give every major capability page a concise task definition, suitable inputs, methods/models, actual output example, QC/uncertainty, supported boundaries and a worked example link. Distinguish deployed capabilities from active research. Cite original scientific sources and BioMate-specific evaluations separately.

### 3. Improve coherent navigation and topic coverage

- Pre-render shared navigation/footer into static HTML during site preparation while preserving the current menu interaction. Main content is already static, but menu/footer links currently depend on shell.js. This reduces dependence on JavaScript rendering without stuffing hidden crawler-only text.
- Build a clear hub-to-detail path: platform → task page → worked example → evaluation; drug discovery → target/design/developability → relevant evidence; engines → Virtual Cell/cyclic peptides → research stage and results.
- Audit old descriptions against revised positioning across About, Features, llms files, social metadata and public repositories. Maintain one fact registry to prevent counts, pricing, titles and research-status drift.
- Correct residual survey metadata labels to Research Perspectives where appropriate; retain genuine research snapshot dates distinct from formatting revisions.
- Review real Chinese-language demand, then create human-reviewed Chinese priority pages with matching canonicals/hreflang if justified. Do not create machine-translated near-duplicate pages solely to target keywords.

### 4. Establish independent corroboration

- Link genuine papers/preprints, reproducible public benchmarks, public repositories and attributable collaborators where approved. Update organization-owned profiles to the same name, URL and accurate scope.
- Verify existing Wikidata and other profile claims; don't invent listings, reviews, customer logos or partner endorsements. The June listing document contains prepared submission copy, not proof of submission.
- Seek real partner case studies and reproducible demonstrations, not mass directory submissions or paid/artificial mentions. External corroboration is a recommendation for credibility, not a guaranteed ranking mechanism.

### 5. Performance and maintainability

- The shared OG cover is approximately 5.5 MB; prepare an appropriately sized social image and validate actual dimensions before declaring image width/height. Optimize large display assets without duplicating imagery or degrading the design.
- Validate LCP/CLS/INP and page rendering on mobile, not only source metadata.
- Use a shared page-head template/build step plus metadata/sitemap regression tests so future redesigns cannot silently remove earlier SEO work. Revalidate protected LLM-comparison pages separately: marketing deployment intentionally does not overwrite those two files.
- Rebuild the extended AI guide from a reviewed fact registry. The July snapshot warning added here is a stopgap; obsolete connector specs/counts remain pending verification.

## Corrections to older SEO/GEO recommendations

- There is no official universal AI-search score or guaranteed inclusion. Access, indexing, relevance and answer selection are separate stages.
- OAI-SearchBot enables search discovery; GPTBot controls potential training use. Allowing training is not required for ChatGPT search visibility. No crawler policy change was made here.
- Google's current guidance says it does not use llms.txt for search visibility/ranking. Keep it as a useful optional guide, not the primary optimization investment.
- No special AI schema or artificial tiny “chunks” are required. Semantic HTML, clear content and ordinary SEO remain the foundation. Structured data must represent the visible page.
- Google retired FAQ rich results in May 2026. Keep FAQs because they help visitors, not because of the older audit's claimed FAQ CTR uplift. Do not restore fabricated SearchAction markup for a nonexistent search endpoint; Google retired the sitelinks search box in 2024.
- The older audit's “82% cited within 30 days,” “primary GEO signal” abstract claims and generic uplift percentages are not established by the primary sources reviewed here. Do not treat them as acceptance criteria.

## Sources

- OpenAI crawler documentation: https://developers.openai.com/api/docs/bots/
- Google generative AI search optimization: https://developers.google.com/search/docs/fundamentals/ai-optimization-guide
- Google documentation changelog (FAQ retirement): https://developers.google.com/search/updates
- Sitelinks search box retirement: https://developers.google.com/search/blog/2024/10/sitelinks-search-box
- Earlier internal work: `20260629_SEO_GEO_MARKETING_AUDIT.md`, `20260704_SEO_GEO_COMPARE_BLOG_UPDATE.md`, `20260605_GEO_EXTERNAL_LISTINGS.md`.

## Verification and release status

Static-navigation follow-up published October 9 at approximately 9:24 p.m. America/Chicago. All 98 changed publishable files checked matched local SHA-256 hashes; the live Services menu was verified in the browser. The pre-sync backup is `/var/backups/biomate-marketing/pre-sync-Q2Gsdp4h.tar.gz`. The two protected comparison pages remain excluded. No AI answer-visibility uplift has yet been measured.

Follow-up implementation: 90 public pages now include pre-rendered navigation and footer markup from the same `shell.js` definitions used by the interactive menus. A no-JavaScript primary-link fallback is included. Authentication pages and the two deployment-protected comparison pages are excluded. `scripts/prepare_marketing_shell.cjs --check` detects drift; `--patch` emits a reviewable patch without writing source. Apply that patch after changing shared markup, then rerun tests. No public scientific article content is regenerated by this step.

The marketing deployment now checks shell freshness and runs the regression suite before upload, and exits on sync or nginx validation/reload failure. The expanded suite passes 33 tests, including static links, no-script fallback, preservation of scientific content, idempotent preparation and one interactive header/footer after enhancement. Browser verification confirmed the Services menu still opens and the desktop page has no horizontal overflow. This improves access and consistency; it is not a measured citation-rate improvement.

Local automated suite: 30 tests passed after the final changes. Tests cover restored metadata, exact visible/schema FAQ agreement and canonical public-page sitemap coverage, plus existing editorial/navigation checks. Browser checks cover desktop question/answer columns and mobile stacking; the mobile page width is 390px at a 390px viewport after the summary-table fix. These tests do not establish scientific correctness, actual bot access, indexing, analytics delivery or a higher AI citation rate.

Published October 9 at approximately 9:14 p.m. America/Chicago using `scripts/deploy_marketing.sh`. All 77 changed publishable files checked matched local SHA-256 hashes; the live FAQ was also verified in the browser. Existing deployment exclusions preserved the two LLM comparison pages. Pre-sync backup: `/var/backups/biomate-marketing/pre-sync-GUjl0oJ7.tar.gz`. Only the dedicated marketing root was synchronized; the application was not deployed. The strategy and audit documents remain local repository documentation.
