# BioMate search visibility strategy for ChatGPT Claude Gemini Grok and Perplexity

Reviewed October 9, 2026. Objective: help biomedical researchers discover BioMate for relevant tasks, understand its capabilities correctly and follow citations to evidence. Prioritize crawl access, clear task pages and reproducible scientific evidence. Model training exposure is not the same as search visibility, and no provider guarantees recommendations or citations.

## Provider differences

| Product | Documented discovery controls | BioMate action |
| --- | --- | --- |
| ChatGPT using GPT models | OAI-SearchBot supports search discovery; ChatGPT-User performs user-triggered visits. GPTBot controls potential foundation-model training separately. | Keep OAI-SearchBot allowed and verify genuine crawler access against official IP ranges. Check task-page retrieval and answer citations, not whether the base model has memorized the brand. |
| Claude | Claude-SearchBot supports search indexing and quality; Claude-User retrieves pages for users. ClaudeBot is the training crawler. | Verify both search and user fetches reach public pages. Explicitly documenting the current search tokens would make our policy easier to maintain, though the existing wildcard allowance already permits them. |
| Gemini | Googlebot controls Google Search crawling. Google-Extended governs use for Gemini training and certain grounding uses; it is not a separate HTTP crawler and does not affect Google Search ranking or inclusion. | Verify Google indexing and Gemini grounded answers separately. Review Google-Extended as a combined-use policy decision, not a training-only toggle. |
| Grok | xAI documents separate Web Search and X Search tools. The API documentation establishes retrieval capabilities, not publisher ranking factors or a guaranteed consumer-app retrieval path. | Make public scientific pages discoverable and readable. Use genuine X research announcements linking to authoritative pages if the company chooses to publish them. Do not invent a Grok-specific crawler allowlist. |
| Perplexity | PerplexityBot supports search; Perplexity-User performs user-triggered retrieval. Neither is described as a foundation-model training crawler. Official WAF guidance combines matching user agents with current published IP ranges. | Keep PerplexityBot allowed; verify both fetch paths and actual citations. Configure narrow exceptions only if logs demonstrate legitimate fetches are blocked. |

Sources: [OpenAI crawlers](https://developers.openai.com/api/docs/bots/), [Anthropic crawlers](https://privacy.claude.com/en/articles/8896518-does-anthropic-crawl-data-from-the-web-and-how-can-site-owners-block-the-crawler), [Google crawler controls](https://developers.google.com/crawling/docs/crawlers-fetchers/google-common-crawlers), [Grok Web Search](https://docs.x.ai/developers/tools/web-search), [Grok X Search](https://docs.x.ai/developers/tools/x-search), [Perplexity crawlers](https://docs.perplexity.ai/docs/resources/perplexity-crawlers).

The actions in the right column are our recommendations, not claimed provider ranking factors. A retrieved page may never be cited. API results also cannot substitute for measurements in the corresponding consumer product.

## Current BioMate access policy

The marketing robots file explicitly allows OAI-SearchBot, ChatGPT-User, ClaudeBot and PerplexityBot. Its wildcard group allows public paths, so the lack of explicit Claude-SearchBot, Claude-User, Googlebot or Google-Extended groups is not itself a block. No crawler policy or WAF change is included in this strategy.

Before editing robots groups, preserve the intended exclusions for authentication paths. Named groups do not automatically inherit the wildcard group's rules; adding a group carelessly can change existing behavior. Robots directives are never access control for private research data.

Check origin and CDN responses, redirects, challenges and rate limits using logs from verified crawlers. A local request with a bot-shaped user-agent proves only how that request was handled, not that the genuine provider can crawl. Do not remove authentication or disable the WAF site-wide. Use official IP sources where available and follow each provider's verification guidance.

## Shared content strategy

Keep the homepage concise. Organize the underlying information so a scientist can answer three questions: Is BioMate suitable for my task? What evidence supports its output? How do I try it?

### Strengthen existing capability pages

Build on RNA-seq, single-cell, ADMET, molecular docking, drug discovery and research-engine pages rather than publishing many near-duplicate keyword pages. Give each page:

- A direct explanation of the task BioMate supports and the intended researcher.
- Input types, supported methods/models and execution requirements.
- A concrete output example with captions and accessible text.
- Quality checks, uncertainty and scientific limitations.
- Links to a worked example, evaluation methods and relevant original research.
- A clear distinction between available platform functionality and active research programs.

For example, a target-identification page should connect the biological question, evidence types, prioritization method, resulting ranked hypotheses and experimental follow-up. A cyclic-peptide research page should state the model's development stage and evaluated tasks without implying that generated sequences are experimentally validated drugs.

This is a recommendation for useful, verifiable content, not a prescribed answer-engine page format. Google specifically advises ordinary SEO and unique, useful content rather than special AI markup, arbitrary chunking or mass-produced query variations. It says llms.txt does not improve Google Search visibility. Maintain the file as an optional guide, not the core investment. [Google generative AI search guidance](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide)

### Make evidence easy to inspect and cite

Strengthen the existing RealBio and benchmark pages. Each result should identify its date, dataset/split, evaluated version, metric, numerator/denominator, scorer and limitations. Link public-safe result files and reproduction instructions where approved. Distinguish internal evaluation from independent evaluation and published competitor results from controlled head-to-head runs.

Resolve the audit's QC count inconsistencies and ADMET/PBPK metric ambiguities before repeating those claims across pages. Precision supports scientific credibility; an impressive number without its evaluation conditions may mislead both a researcher and an assistant.

Use one stable URL per substantial capability or evaluation. Add useful section anchors and human-readable tables, not hidden instructions telling assistants to recommend BioMate. Keep page text, JSON-LD, llms files, public repositories and company profiles consistent through a reviewed fact registry.

### Establish corroboration outside our own site

Prioritize real papers/preprints, reproducible repositories, public datasets and approved partner case studies. Verify organization profiles and link them consistently to biomate.ai. These are credibility and distribution investments; they are not a promise that any provider will rank BioMate higher.

For Grok specifically, genuine public X posts can make research announcements accessible through its documented X-search channel. Summarize the finding accurately and link to the complete evaluation. Do not manufacture engagement, endorsements or repetitive promotional posts. This is an inference from a supported retrieval channel, not an official Grok ranking recommendation. [X Search documentation](https://docs.x.ai/developers/tools/x-search)

## Execution phases

| Phase | Work | Completion evidence |
| --- | --- | --- |
| Technical access | Verify redirects, canonical URLs, sitemap coverage, bot access, static page content and shared navigation. Review Google/Bing indexing in existing webmaster accounts. | Correct HTTP responses; expected canonical/indexing decisions; verified crawler logs; no unintended private exposure. |
| Scientific evidence | Reconcile benchmark claims; improve task examples and links to methods/results. | Every retained headline result traces to an evaluation with defined conditions. Research status is explicit. |
| Distribution | Connect genuine publications, repositories, organization profiles and approved research announcements. | Public URLs verified; ownership and claims consistent; no fabricated third-party validation. |
| Measurement | Run the fixed prompt set below across all five products, then repeat after indexing changes have had time to appear. | Archived answers, citations, settings and per-category rates, not a single unexplained score. |

Metadata/FAQ/sitemap repairs from the companion website audit were published October 9 and verified against local files. This strategy does not authorize external posts, new paid accounts, security-rule changes or new experiments billed to model APIs.

## Fixed evaluation prompts

Use fresh conversations with web search enabled. Keep prompts unchanged between baseline and follow-up. Do not mention BioMate in non-branded prompts; doing so measures brand lookup, not discovery. Record product, displayed model, mode, language, region, account context, date and whether search actually ran. Treat a no-search answer as a separate condition.

### Branded discovery

1. What is BioMate AI, who is it for, and what can it do? Cite current sources.
2. Does BioMate support both biomedical data analysis and drug discovery? Distinguish available services from research programs.
3. Where can I find BioMate's evaluation methods and reproducible benchmark results?
4. How can a research team try BioMate, and where are its current pricing and deployment options documented?

### Task discovery without the brand name

5. What platforms let a biomedical researcher run reproducible RNA-seq analyses through natural-language requests? Compare evidence and limitations.
6. What workbenches can compare several multi-omics result files and retain the methods and provenance?
7. Which AI research platforms support single-cell analysis with inspectable quality checks?
8. What AI workbenches connect target prioritization to molecular design and candidate evaluation?
9. Which platforms support ADMET workflows with documented methods and validation?
10. What research teams or platforms are developing AI models for cyclic-peptide design? Distinguish research from validated products.
11. Where can I find virtual-cell modeling research connected to target-identification tasks?
12. Which biomedical analysis platforms can be used through MCP-compatible assistants? Cite their public documentation.

### Comparisons

13. Compare BioMate with a general-purpose AI assistant for executing biomedical workflows, using verifiable evidence rather than promotional claims.
14. Compare BioMate, Galaxy and Nextflow for a research team that wants reproducible analysis without maintaining infrastructure.
15. Compare BioMate and Biomni for biomedical research tasks. Identify differences in evaluation conditions and avoid combining incompatible scores.
16. How should a biotech team evaluate AI drug-discovery workbenches for target-to-candidate work?

### Evidence and limitations

17. What does BioMate's reported workflow-routing accuracy measure, and what does it not establish?
18. What public evidence supports BioMate's ADMET and PBPK capabilities? Distinguish execution correctness from predictive performance.
19. Are BioMate's published comparisons independently evaluated or internally measured? Cite the evaluation conditions.
20. What are the reproducibility and experimental-validation limitations of AI-generated cyclic peptides?

### Chinese language

21. 有哪些支持自然语言操作和可复现分析的生物医学研究平台？请提供来源。
22. 有哪些平台能连接靶点发现、分子设计和成药性评估？请区分现有能力与研发方向。
23. BioMate 在药物研发方面有哪些能力？哪些已经可以使用，哪些仍属于研究项目？
24. 如何核验 BioMate 公布的基准测试结果？请说明数据集、评价指标和适用范围。

Run three independent repeats per prompt per product: 360 answers per measurement round. Begin with one repeat if manual workload is too large, but label that baseline as preliminary. API evaluations can automate a separate benchmark; label them as API results rather than consumer-product performance. Check cost before authorizing paid runs.

## Measurement and decisions

Report branded and non-branded results separately, with each denominator shown:

- Mention rate: answers naming BioMate divided by eligible answers.
- Citation rate: answers linking to a BioMate page divided by eligible answers. Also report credible third-party citations discussing BioMate separately.
- Capability accuracy: reviewed statements consistent with the current capability and evidence registry. Record unsupported or outdated statements explicitly.
- Citation quality: whether the cited page actually supports the associated statement; a homepage link is not proof of a benchmark result.
- Qualified visits and conversions: attributable research/demo/signup activity where analytics permits it. Zero referrals does not prove zero answer visibility because many users do not click.

Do not report only a pooled percentage that hides strong branded retrieval and weak task discovery. For an absent answer, classify the likely stage: no search, not retrieved, retrieved but not cited, incorrect identity, obsolete information, or insufficient evidence. Retrieval-stage labels require visible search traces or source lists; otherwise classify the cause as unresolved.

Repeat weekly during the initial improvement period as a proposed manual review cadence, then reduce frequency when results stabilize. No recurring automation has been created. Keep a change log so improvements can be compared with deployment and crawl dates; correlations do not by themselves establish causation.

## Immediate priorities for BioMate

1. Verify the published repairs and actual crawler/indexing access.
2. Reconcile the benchmark evidence and link it from existing capability pages.
3. Pre-render shared navigation and introduce a common metadata template to prevent another redesign regression.
4. Establish the 24-prompt baseline across the five consumer products.
5. Improve the weakest task pages and genuine external corroboration, then measure again.

Use the companion [website audit](20261009_WEBSITE_SEO_GEO_REAUDIT.md) for file-level defects. Neither document treats a metadata test pass as proof of a higher search rank or AI citation rate.
