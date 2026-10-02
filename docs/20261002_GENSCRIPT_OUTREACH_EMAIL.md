# GenScript — Round-1 Outreach (business email + clean order attachments)

**Use this, not the detailed internal spec.** The CRO receives: a short business email + two clean sequence lists (`research/guangzhou_all_atom/results/CRO_SEND_pdl1_panelA.csv`, `CRO_SEND_avb6_panelB.csv`). **Our design scores (ΔG, iPTM, interface metrics, rankings) stay internal — they are never sent.** Send sequences only **after** confidentiality is in place (see note at the end).

---

## Email

**To:** peptide@genscript.com (cc protein@genscript.com)
**Subject:** Quote request — custom cyclic peptide synthesis + binding (22 peptides, 2 panels)

Hello GenScript team,

We're a drug-discovery group running cyclic-peptide binder programs and would like a quote for a first round of **synthesis plus affinity measurement**.

**Scope:** 22 macrocyclic peptides in two target panels (10 + 12). All are **head-to-tail backbone-amide cyclics**, 8–16 residues, all natural L-amino acids (no non-natural residues this round). Per peptide: **≥95% purity, 5 mg, acetate (TFA-free) salt**, standard QC (RP-HPLC, ESI-MS, net peptide content, CoA).

**Binding:** for each peptide, **SPR/BLI KD** against the panel's target protein (Biacore 8K+ preferred), with full kinetics and sensorgrams returned for **all** peptides. One panel's target is an integrin and needs a **Mn²⁺/Ca²⁺ running buffer**. We can supply the target proteins or you can quote supplying research-grade protein.

**Please quote:**
1. Synthesis alone, and synthesis + binding bundled — per panel and for the full set.
2. An **expedited** tier for 12 of the peptides.
3. Any **batch discount** for ordering all 22 together.
4. Typical **turnaround** for each.

We expect this to be the first of a recurring series of rounds, so we'd also welcome a conversation about **framework/preferred-volume pricing** once this round is underway.

Before we share the sequences, **please send your mutual NDA** (or confirm the confidentiality and customer-IP-ownership terms that apply to custom synthesis) — we'll return the sequence lists and the two target proteins' details immediately after.

Happy to jump on a short call. Thank you,

[Name / title / company]

---

## Attachment 1 — Panel A (PD-L1), 10 peptides
Clean list sent to CRO (sequences + spec only): `results/CRO_SEND_pdl1_panelA.csv`
Columns: Item · Sequence (N→C) · Length · Cyclization · Purity · Quantity · Salt · QC · Priority. **No scores.**

## Attachment 2 — Panel B (αvβ6), 12 peptides
Clean list: `results/CRO_SEND_avb6_panelB.csv`. Same columns. **No scores.**

(Target identities — PD-L1 / integrin αvβ6 — are disclosed; the per-peptide design scores and selection rationale are not.)

---

## Internal note — confidentiality / sequencing (do NOT send this section)
- The sequences are **unpatented IP**. Disclosing them to a CRO **under confidentiality** (NDA or the CRO's standard customer-confidentiality terms) is **not** a public disclosure and does not create prior art; sending them with **no** confidentiality could be argued to be a disclosure. So: **NDA/confidentiality first, then sequences.**
- Order sequence: **(1) mutual NDA** → (2) RFQ/quote → (3) PO/MSA at order with explicit **IP assignment to us + confidentiality** (custom synthesis is normally work-for-hire = we own the sequence + product; confirm it in writing).
- If any of these are candidates we intend to patent, consider a **provisional filing before wider disclosure**; disclosure to the CRO under NDA is fine in the meantime.
- Never send our internal ΔG / iPTM / interface scores or selection logic — they are the design IP and are not needed to synthesize or assay.
