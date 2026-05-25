# LinkedIn feed post — Post 18 (In Vivo CAR-T Co-Design)

**Recommended hero image:** the 4-phase pipeline + fratricide-check Venn. See `figures/post_18_invivo_cart_pipeline.drawio.xml`.

**Character count:** ~2,400 / 3,000 limit.

---

Capstan raised $165M. Umoja $210M. Kelonia $50M. The pitch: skip ex vivo CAR-T manufacturing, deliver the CAR straight into T cells via LNP. $5M/dose drops to $500. 14-day manufacturing drops to a single IV.

But the hard part isn't the LNP. It's the co-design.

Three molecules have to agree:
🔵 The CAR target (e.g., CD19)
🔵 The LNP surface targeter (e.g., anti-CD8)
🔵 The CAR construct (scFv + hinge + costim + CD3ζ)

The failure mode that ends programs: fratricide. CD7 CAR + anti-CD7 LNP = CAR T cells kill each other. The product self-destructs.

The 2024 oncology pipeline is full of programs that should have flagged fratricide earlier and didn't.

BioMate runs the 3-molecule co-design as 4 auditable phases:

1️⃣ Atlas safety check — CAR target tissue expression across 26 tissues from Tabula Sapiens + CELLxGENE Census. CD19 → B-cell restricted, VIABLE.

2️⃣ LNP tropism selection — pick anti-CD3/CD5/CD8/CD7, characterize the transfected cell set.

3️⃣ Fratricide check — cross CAR target × transfected set. CD19 (B-cell) + anti-CD8 (T-cell) → no overlap, SAFE.

4️⃣ CAR construct assembly — emit FASTA. CD19 design: FMC63 + CD8α + CD28 + CD3ζ = Kymriah architecture, 1,485 AA.

Run the same workflow with CD7 target → fratricide warning fires, the agent refuses to assemble.

Capstan's CPTX2309 is anti-CD19 mRNA + anti-CD8 LNP for SLE. Run BioMate on that thesis and the pipeline reproduces the architecture from the biology alone. The agent doesn't know about the IND. It infers the design.

You can ask ChatGPT for "an in vivo CAR-T design" and get a fluent paragraph. What it won't do:

❌ Check tissue expression against a real atlas
❌ Flag fratricide if you swap CD19 → CD5
❌ Emit FASTA with correct domain order
❌ Cite precedent (Kymriah architecture, Capstan IND)

In BioMate every file is auditable. When IND prep asks "why anti-CD8 LNP?" — `lnp_tropism.json` has the cell-set analysis. Not the agent's opinion.

Biotechs with $400M of funding run this co-design with spreadsheets and a four-month cycle.

It should be 30 seconds.

👉 biomate.ai

Full essay (with diagrams): [link to Substack post]

#DrugDiscovery #CARTtherapy #InVivoCART #AIinPharma #BiotechInnovation
