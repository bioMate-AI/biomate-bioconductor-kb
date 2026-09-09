# How targets are selected — channels and how they are combined

*In response to Dr. Mohan's question on which channels are used for target selection.*

Target selection does not rely on a single channel such as pathway analysis. It integrates several complementary
lines of evidence, with **human genetics as the causal anchor**, so that a nominated target is supported by more
than one kind of evidence rather than by expression alone.

**The channels used:**
- **Human genetics** — GWAS, eQTL/pQTL, colocalization, and Mendelian randomization: evidence that the gene is a
  causal driver rather than a bystander (genetically supported targets are roughly twice as likely to succeed
  clinically).
- **Perturbation evidence** — whether removing the gene shifts the disease signature, i.e. direct evidence that it
  drives the phenotype.
- **Pathway and gene-regulatory activity** — whether the gene's pathway, or the programs it regulates, are engaged
  in the disease signature.
- **Protein-interaction context** — the gene's position relative to the disease's protein network.
- **Differential expression** — disease versus control (used as supporting, not decisive, evidence).
- **Cell-type / state specificity** — whether the signal sits in the disease-driving cell state rather than a bulk
  average.
- **Proteomic and autoantibody evidence** — differential proteins and autoantigen targets; the channel the Mohan
  Lab's data speaks to most directly.
- **Prior disease–gene knowledge** — used as a soft prior, never as proof.

**How they are combined:** each channel is scored **against its own matched negative control**, so a "hit" reflects
biology and not an abundance, connectivity, or annotation-depth artifact. Human genetics anchors the ranking; the
remaining channels add or subtract support; and druggability is applied as a final filter for what can actually be
made into a therapeutic.

**What is delivered is not a black-box score.** Each nominated target comes with an **evidence breakdown** — which
channels support it and how strongly — so the basis for every nomination is visible and can be judged directly.

In a feasibility study on the Lab's published data, target selection would run the channels that data supports —
proteomic and autoantibody evidence, human genetics where available, and pathway/network context — and return the
per-target evidence breakdown alongside the ranking.
