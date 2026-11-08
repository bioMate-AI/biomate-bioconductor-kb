# Website reorganization — 9 October 2026

## Positioning

BioMate offers a general biomedical research platform and a drug-discovery
workbench as two service offerings. Virtual Cell LLM and cyclic-peptide generation are
research programs that deepen the workbench's scientific capabilities.

## Implementation

1. Replace the crowded homepage with five sections: positioning, three entry
   points, AI efficiency, drug-discovery depth, and evidence/trust.
2. Keep the cream/navy brand, introduce larger visual areas and more whitespace,
   and use short descriptions with links to detailed pages.
3. Add dedicated Drug Discovery and Research Engines pages. Explain the link
   between biological understanding, target prioritization, molecular design,
   evaluation, and experimental feedback. Identify ongoing model research.
4. Order shared navigation as Company, Services, Research Engines, and Evidence.
   Put basic company information in Company, and Biomedical Research Platform
   and Drug Discovery as the two primary offerings under Services.
   Preserve access to tutorials, pricing, connectors,
   scientific articles, and existing application pages through submenus.
5. Show efficiency through automated planning, execution, interpretation and
   reuse. Remove the platform-wide “<30 min average” and generic minutes/days
   comparisons. Use measured, task-specific runtimes only when evidence exists.
6. Retain HIPAA-compliant messaging. Keep validation and benchmark details on
   evidence pages rather than repeating numerical claims on the homepage.
7. Verify desktop/mobile layout, local navigation, image loading, and page
   behavior in a browser. Review the local prototype before publication.

## Editorial rules

- One purpose per homepage section; concise headlines and one short supporting paragraph.
- Concision at the entry point must not remove scientific depth. Use linked layers:
  homepage orientation → service/research overview → research perspective or
  worked example → methods, comparison tables, limitations and primary sources.
- Demonstrate research outcomes and decisions, rather than listing infrastructure.
- Keep general research visible alongside the deeper drug-discovery offering.
- Do not imply that model research already provides experimentally validated
  therapies. Distinguish computational predictions from assay observations.
- Preserve existing technical articles and tutorials as deeper reading.

## Scientific publishing revision

Research perspectives and application articles serve different purposes. A
perspective explains a field, compares methods and evaluates evidence. An
application article explains how a research question can be approached with
BioMate. Link the two, without replacing the perspective with product promotion.

The five perspectives now follow a shared hierarchy:

1. Title, short explanation, author and clearly dated research snapshot.
2. Three topic-specific takeaways for readers scanning the page.
3. A labeled conceptual diagram explaining relationships between approaches.
   These diagrams are explanatory, not measured scientific results.
4. Navigable chapters with detailed methods, tools, comparisons and limitations.
5. Linked scientific sources and relevant application reading.

Editorial cleanup removes private Markdown references, session/verification
logs and instructions to future writers. It retains substantive uncertainty
and distinguishes company-reported programs, predictions, experimental findings
and clinical evidence. Existing section IDs remain intact for incoming links.
The original August research snapshot is not relabeled as newly validated in
October; the presentation revision has its own date.

The blog template now adds section navigation and horizontally scrollable tables
while retaining the existing article content and illustrations. Five companion
articles received targeted wording cleanup. A separate multi-omics worked example
had impossible arithmetic and inconsistent percentage descriptions corrected,
and now explicitly distinguishes example outputs from independently verified runs.
This is not a claim that all blog findings or citations were scientifically
revalidated. Future substantive revisions should link run evidence for measured
results, identify illustrative outputs at the point of use, and recheck dated
clinical/program claims against primary sources.

Publication requirements: no internal file paths or drafting notes; meaningful
headings rather than report scaffolding; figures with an explanatory caption;
readable references; accessible tables; explicit evidence dates and status.

## Navigation refinement

The current Moderna navigation was inspected directly: opening a primary
category reveals a wide horizontal submenu below the header. BioMate adopts
that spatial pattern, with three aligned columns for its larger content set:

- Company: About BioMate, Newsroom, Contact.
- Services: Biomedical Research Platform, Drug Discovery, Getting Started.
- Research Engines: research overview, Virtual Cell LLM, cyclic-peptide generation.
- Evidence: benchmarks, research perspectives, scientific publishing.

All previous submenu destinations remain available. The two service offerings
have equal prominence; tutorials, connectors and pricing remain supporting links.
Below 900px, categories stack into a scrollable disclosure navigation.
Native buttons expose expansion state, closed panels are inert, and keyboard
users can enter a panel with ArrowDown and dismiss it with Escape. Overview
links navigate explicitly rather than assigning different meanings to a second
click on the category label. Only one panel opens at a time.

Verified all four panels align horizontally on desktop; checked 390px mobile,
800px tablet and the 901px desktop breakpoint without horizontal overflow.
Fixed a mobile focus-transfer issue that could collapse the current category
before a tap reached the next trigger. Added a regression test for that sequence.
The combined editorial/navigation suite passes 25 tests:
`node --test reference/claude_design/webpage_design_v2/tests/*.test.cjs`.

## Reference sites

Moderna's homepage and platform pages inform the hierarchy: a clear platform
identity, restrained proof points, large images, and deeper pages for science.
The design retains BioMate's own identity and product needs.
https://www.modernatx.com/
https://www.modernatx.com/power-of-mrna/modernas-mrna-platform

## Follow-up content

Add measured case studies with task, inputs, elapsed time, automated steps,
review requirements, and linked outputs. Select these from verified runs; do
not substitute a universal turnaround promise.

## Implemented and verified

- Rebuilt the homepage with five sections and added Drug Discovery and Research
  Engines pages; updated shared navigation, footer links, sitemap and LLM index.
- Removed the inaccurate average from both the homepage and Services page.
- Preserved the existing homepage analytics tag and HIPAA-compliant statement.
- Rendered all three new pages at 1440px and 390px widths: no horizontal
  overflow, image failures, or JavaScript errors. Visually inspected the
  desktop and mobile homepage captures.
- Published to https://biomate.ai/ on 9 October 2026 (Chicago time) using
  `scripts/deploy_marketing.sh`. The marketing docroot alone was synced;
  application files were not deployed. nginx configuration test and reload passed.
- Rollback archive: `/var/backups/biomate-marketing/pre-sync-4I52QGoO.tar.gz`.
  Internal Markdown and regression tests were excluded from the public archive;
  the editorial plan URL returns HTTP 404.
- All 75 changed/new web files selected for verification matched the live
  response byte-for-byte. The script intentionally preserves the two existing
  LLM comparison pages. Verified the public desktop menu, 390px mobile menu,
  and Virtual Cell perspective (diagram, chapters, contents links, no overflow).
- Editorial browser QA: homepage, perspective library, all five perspectives,
  five companion/application articles and the LLM comparison article were
  checked at 1440px and 390px (26 page/viewport combinations). After fixing
  two older blog layouts, no page overflow, broken images, duplicate IDs,
  broken contents links or JavaScript errors remained in these checks.
- Visually inspected perspective desktop/mobile views, the desktop library,
  the desktop reading layout and a mobile companion article.
- All original external article links in the five perspectives remain present;
  additional bare DOI identifiers now link to their resolver. This verifies
  preservation and usability, not the scientific validity of every citation.
- Regression tests: `node --test reference/claude_design/webpage_design_v2/tests/editorial.test.cjs`
  passes 18 tests covering hierarchy, public prose, dates, contents links,
  responsive table containers and preservation of blog content by enhancement.
