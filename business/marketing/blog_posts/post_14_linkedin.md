# LinkedIn feed post — Post 14

**Hero image:** `figures/post_14_param_extraction.drawio.xml` exported as 1200×627 PNG.

**Character count:** ~2,600 / 3,000.

---

**Posting note:** retype the `@` in front of each name in LinkedIn's composer to resolve real profiles.

---

Schema mismatch is the unsexy AI failure mode. It eats more drug programs than tool hallucination does — because the failures don't look like failures.

Third in the ChatInvent series. @Jiazhen He @Ola Engkvist @Samuel Genheden and the AstraZeneca team named it in "Democratising real-world drug discovery through agentic AI" (Drug Discovery Today, doi: 10.1016/j.drudis.2026.104605) as one of the five engineering problems agentic AI hits in pharma R&D.

What it looks like in practice:

🔸 User says "simulate for 100 nanoseconds." The workflow takes n_steps, not time_ns. LLM writes n_steps: 100. The right value is 50,000,000.

🔸 User says "single-end reads." Flag is single_end: true. LLM writes paired: false (wrong key).

🔸 User says "human genome." Enum is GRCh38 / GRCh37 / T2T-CHM13. LLM writes "human."

🔸 User says "remove duplicates." Flag is keep_duplicates. LLM writes remove_duplicates: true (wrong key).

Each runs. None errors. Numbers come out. The run is silently wrong.

In a chat app, this is a glitch. In a drug program going into IND, it's a record that fails an audit.

LLMs are bad at this for the same reason they're bad at arithmetic. Unit conversion is exact. Boolean negation is exact. Enum constraints are exact. Models are probabilistic. The mismatch is structural.

What we built at BioMate, three stages:

🔹 STAGE 1 — DETERMINISTIC RULES handle what has a single right answer:
✓ Unit conversions (ns → n_steps via dt)
✓ Boolean negations ("remove duplicates" → keep_duplicates: false)
✓ Canonical aliases (human → GRCh38, dUTP → reverse, cyno → Macaca fascicularis)

🔹 STAGE 2 — LLM FALLBACK handles only what rules can't:
✓ Free-text (SMILES, PDB IDs, gene names)
✓ Ambiguous enum selection
✓ Multi-parameter joint inference from prose

🔹 STAGE 3 — SCHEMA VALIDATION guardrail:
✓ Allowed_values violations dropped or normalized
✓ Type mismatches rejected before executor
✓ Required-but-missing triggers clarification, not default substitution

📊 Benchmark evidence the design works:
✓ PBPK: 71.7% → 98.5% (+26.8pp) purely from the rule-based prereq gate
✓ ADMET: 89.3% with rule-based hERG/DILI/Ames/Ro5 thresholds
✓ BOIN dose escalation: 100%
✓ Routing variant_calling: 0.567 → 0.824 after 4 structural fixes
✓ param_prefill: 61.7% → ≥70% target, including 15-case param_name_disambiguation category

The +26.8 point PBPK lift came from NO model change and NO prompt change — just letting rules do what rules do.

The LLM is asked to do language. Rules are asked to do arithmetic. Schema is the guardrail. Each does what it's good at.

Open trial — describe a study in narrative prose and watch the parameter strip fill in:

👉 biomate.ai

Full essay (with extraction-pipeline diagram + benchmark detail): [Substack link]

@Jiazhen He @Ola Engkvist @Samuel Genheden — the +26.8pp PBPK lift from a rule-based prereq gate was the most surprising result of the quarter. Curious whether you saw similar non-LLM wins inside ChatInvent.

#AIinPharma #DrugDiscovery #LLM #PBPK #ADMET #AstraZeneca
