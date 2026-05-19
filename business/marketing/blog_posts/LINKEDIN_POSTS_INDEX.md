# LinkedIn posts — title index

One row per `post_N_linkedin.md` in this folder, sorted by post number.
Each row shows the LinkedIn hook (the first line of the post, which
functions as the headline because LinkedIn posts have no formal title
field) alongside the matching long-form Substack title.

| # | Author | LinkedIn hook | Matching Substack title |
|---|---|---|---|
| 1  | Yaoyun  | Pick any modern biotech program. Trace it end-to-end. | Life science has been split for forty years. Agents are how we finally stitch it back together. |
| 5  | Yaoyun  | Most "AI for drug discovery" pitches sell you prediction. | Drug development needs three things, not one: prediction, simulation, and real-world validation |
| 8  | Yaoyun  | LLMs hallucinate science at rates between 14% and 95% depending on the model and domain. | Evidence-grounded AI in biology: what we ground against, and what general-purpose LLMs get wrong |
| 9  | Yaoyun  | About once a month, someone asks me if BioMate is training its own LLM. | Domain-specific LLMs for biology: post-train, fine-tune, or train from scratch? Where we did, and where we didn't. |
| 10 | Teammate | Most "AI drug discovery" demos fail quietly. | ANDV inhibitor — two-agent A/B framing (pocket → pharmacophore → ADMET → Vina) |
| 11 | Teammate | "Run nf-core for MHC epitopes" is not one workflow. | Plan A epitope routing — samplesheet → epitopeprediction → MHCnuggets, not mhcquant |
| 12 | Yaoyun  | @Jiazhen He @Ola Engkvist @Samuel Genheden and the AstraZeneca Molecular AI team just published "Democratising real-world drug discovery through agentic AI"… | Context explosion is the first wall agentic AI hits in pharma. Here's how we get past it. |
| 13 | Yaoyun  | Tool hallucination is the most dangerous AI failure mode in regulated R&D. | Tool hallucination is the second wall — and the most dangerous one in regulated R&D |
| 14 | Yaoyun  | Schema mismatch is the unsexy AI failure mode. It eats more drug programs than tool hallucination does. | Schema mismatch — why we don't trust the LLM with arithmetic, and the hybrid pipeline that fixes it |
| 15 | Yaoyun  | The workflow ran. It didn't crash. The output files exist. The science is still wrong. | Workflow instability — when the run fails its QC, the agent fixes it |
| 16 | Yaoyun  | A drug program runs for months. The agent that helps it should know… | Memory corruption + traceability + governance — what a long-running pharma agent actually needs |
| 17 | Teammate | October 2024: Ivonescimab — a PD-1 × VEGF CrossMab — beat pembrolizumab head-to-head in HARMONi-2 NSCLC. | Bispecific format triage — how BioMate recovers Ivonescimab's CrossMab choice from two protein names |
| 18 | Teammate | Capstan raised $165M. Umoja $210M. Kelonia $50M. The pitch: skip ex vivo CAR-T manufacturing… | In vivo CAR-T co-design — three molecules, one workflow, no fratricide |
| 19 | Teammate | Q4 2024: Verve Therapeutics dosed the first patient with VERVE-102. | In vivo base editing — how BioMate reconstructs VERVE-102 from "knock out PCSK9 in the liver" |
| 20 | Teammate | Semaglutide hit $42B in 2024. Tirzepatide hit $36B. Every pharma is asking: what's the next GLP-1? | GLP-1 modality bakeoff — why "the next GLP-1" is an indication question, not a chemistry question |
| 21 | Teammate | Q4 2024 alone, the FDA approved 7 new oncology biologics. Each program made a modality choice early. | Modality triage from atlas — recover 7-of-7 Q4 2024 FDA approvals from target expression alone |
| 22 | Yaoyun  | The benchmarks every "AI for biology" company quotes are measuring the wrong thing. | The benchmarks every "AI for biology" company quotes are measuring the wrong thing |

---

## Notes

- **Gaps in numbering (2, 3, 4, 6, 7):** intentionally left for future
  filler posts in the launch sequence.
- **Yaoyun-authored ChatInvent series (12–16):** maps 1:1 to the five
  engineering problems named in the AstraZeneca *Drug Discovery Today*
  paper "Democratising real-world drug discovery through agentic AI"
  (doi: 10.1016/j.drudis.2026.104605). Post 22 is the opinion-piece
  capstone on evaluation metrics.
- **Teammate-authored case-study series (10–11, 17–21):** drug-program
  worked examples — ANDV inhibitor, Plan A epitope, Ivonescimab,
  in-vivo CAR-T, VERVE-102, GLP-1, oncology modality triage.
- **Trial CTA:** all posts use `biomate.ai` (no `/try` suffix).
- **Author @-tags:** posts 12–16 + 22 include `@Jiazhen He`,
  `@Ola Engkvist`, `@Samuel Genheden` for the AstraZeneca paper. Retype
  the `@` in LinkedIn's composer so the tags resolve to real profiles.
- **Companion files:** each `post_N_linkedin.md` has a matching
  `post_N_substack.md` for the long-form essay and (most have)
  a `figures/post_N_*.drawio.xml` for the hero image.

## Regenerating this index

Run:

```bash
cd business/marketing/blog_posts && for f in $(ls post_*_linkedin.md | sort -V); do
  num=$(echo "$f" | grep -oP 'post_\K\d+')
  hook=$(awk '/^[^# *_<\-`\[].{15,}/{print; exit}' "$f" | head -c 130)
  echo "$num | $hook"
done
```

…and update the "Matching Substack title" column manually from each
`post_N_substack.md` `# H1`.
