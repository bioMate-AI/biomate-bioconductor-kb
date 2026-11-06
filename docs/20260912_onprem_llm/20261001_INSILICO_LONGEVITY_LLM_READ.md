# Careful read: Insilico "LongevityBench + Longevity-LLMs + Longevity Claw" (Cell 2026) — lessons for our on-prem LLM

Zhavoronkov et al., Cell cover (2026). Insilico + Liquid AI + Buck Institute + Harvard/BWH.
Open: HF insilicomedicine/longebench + longevity-llm collection; GitHub Insilico-org/longeclaw (MIT); longevitybenchmarks.org.

## Design (LongevityBench)
- 17 tasks x 5 domains (clinical, genetics, epigenetics, transcriptomics, proteomics). 25.5k bench rows (+65.4k extra), text/parquet.
- REAL biodata as prompt: nhanes_age_pairwise (classification), Olink-NPX age regression (MAE years), GEO methylation age (concordance).
- Anti-memorization BY CONSTRUCTION: measure performance shift under rephrasing; perturb feature set/order in regression; omics-age hardest regardless of scale.

## Training (Longevity-LLMs, 0.6-9B; best L-Qwen3.5-9B)
- Bases: Qwen3/Qwen3.5 + Liquid AI LFM2. ~1M prompts / several B tokens.
- Data: knowledge priors (UniProt/GO/PPI/pathways/CLOCK FORMULAS/CpG coefficients) + NHANES + GEO methylation + GTEx/TCGA + Olink + OpenGenes/SynergyAge/CellAge + reasoning (frontier CoT traces).
- 3-stage LoRA (r32): (1) CPT on knowledge priors (4096 blk, LR2e-5, 3ep); (2) SFT on prediction tasks conversational (LR1e-4, 3ep); (3) reasoning continuation (LR3e-5, ~1ep, 32k ctx). CPT+SFT -> concat rank-64 LoRA -> merge.

## Eval
- 18 frontier models, 6 labs. L-Qwen3.5-9B best overall rank 4.4 > Gemini-3.1-Pro; top-3 all small; 0.6B beat most frontier.
- Olink age MAE 5.7y (L-Qwen3-0.6B) vs 10.1y frontier; methylation concordance 0.868 vs 0.685.

## Agent (Longevity Claw)
- L-Qwen3.5-9B + tools: 233 clocks/6 modalities, PhenoAge, CpG annot, MyGene, pathway enrichment (12 hallmarks+MSigDB Fisher), GSEA, PubMed, DrugAge. Workflow ingest->clocks->SHAP attribution->enrichment->evidence->control-theory intervention on 12D hallmark space.
- 328 targets: 14 hallmarks x 30 cand -> dedup -> 328; 6D score (Novelty/Druggability/Confidence/Safety/Commercial/Mechanism 0-100), 5-run consensus; 5.6x enrichment; KDM1A validated C. elegans.

## KEY LESSON vs our on-prem work (reconciles our mid-train negative)
- Their CPT/mid-train HELPED because the tasks (predict age from omics) REQUIRE parametric knowledge the CPT injects (clock formulas/CpG coefficients).
- Our mid-train HURT because routing/QA is RETRIEVAL-grounded (needs catalog names at inference, not parametric biology) -> CPT only shifted distribution.
- RULE: mid-train helps iff the downstream task consumes parametric domain knowledge; hurts for retrieval-grounded skills. Our negative is CORRECT for our task mix; a quantitative omics-prediction task would likely benefit from CPT (matching them).
- Validated our choices: small-domain-LLM>frontier, Qwen3+LoRA, multitask SFT, anti-memorization/paraphrase eval, small-model+tools agent (=BioMate).
- They do what we DEFERRED: a dedicated frontier-CoT-distillation reasoning stage; and quantitative-from-raw-features tasks (a task class we lack).
