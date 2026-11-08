# Design brief — polish the BioMate‑Pharma Guangzhou product‑introduction deck

**To:** Claude Design (deck polish) · **From:** product/strategy · **Date:** 2026‑09‑21
**Goal:** turn the current strategy‑style markdown deck into a **client‑facing product‑introduction deck**
we can send to the Guangzhou pharma company evaluating our response to their RMB 70M tender.

## 1. Source material (do not re‑research — use these)
- **Current deck (content source of truth):** `docs/20260921_BIOMATE_PHARMA_GUANGDONG_DECK.md` (+ rendered `.pptx`).
- **The requirement (must map to it):** `docs/20260911_GUANGZHOU_AI_DRUG_DESIGN_PROJECT_EN.md`,
  `docs/20260911_GUANGZHOU_CLIENT_QUESTIONNAIRE_EN.md` (the 4 layers + 20 questions),
  `docs/20260911_GUANGZHOU_AI_DRUG_DESIGN_BIOMATE_BRIEF.md` (positioning + claims‑to‑avoid).
- **Supporting facts (already verified):** `docs/20260921_COMPETITIVE_INTEL_AI_DRUG_DISCOVERY.md`.

## 2. Audience, purpose, tone
- **Audience:** a Guangzhou (广州) innovative‑drug company's decision‑makers — mixed **executive + computational/medicinal‑chemistry** technical reviewers evaluating a **RMB 70M**, deadline **2026‑12‑31** engagement.
- **Purpose:** a **product introduction** — "here is what BioMate is, how it meets and exceeds your molecular‑generation+optimization need, how we'd engage, and why us." NOT an internal market‑strategy or investor deck.
- **Tone:** confident, concrete, credible, honest. Client‑centric ("for your programs"), not field‑commentary.

## 3. The reframe — from strategy deck → product intro (the biggest change)
Restructure the narrative to **lead with the client's need and the product**, not the market thesis. Target arc (~14–18 slides for the main deck; push depth to an appendix):
1. **Cover** — product name/tagline, "for [Guangzhou pharma] — AI molecular generation & optimization platform."
2. **Your goal, in one slide** — restate their need (generate → optimize on synthetic accessibility · target affinity · safety → rank; a reusable platform; discovery‑scoped).
3. **What BioMate is** — the product in one picture (the generate → **verify** → learn engine on cloud compute) + a **real product UI screenshot**.
4. **The 4 layers → BioMate** — Knowledge / Reasoning / Generation / Optimisation, mapped to concrete capabilities (this is the heart; keep the table but make it a clean visual).
5. **How it works** — the platform architecture as a **designed diagram** (replace the ASCII 5‑plane + dataflow slides) and a 1‑program walkthrough.
6. **Beyond the requirement** — full drug‑dev platform + search (you're not boxed in).
7. **Proof / credibility** — the verify‑changed‑the‑answer example, kept honest and short.
8. **How we'd engage** — the jointly‑scoped, validated pilot (5 stages) mapped to their 2026‑12‑31 milestone.
9. **Deployment, IP, on‑prem, data residency** — their Q5–Q18, as reassurance.
10. **Why us** — a tight differentiator slide (verified execution + governance + breadth).
11. **The ask / next step.**
12. **Appendix** — competitive landscape (condense the current ANew/Vilya/Virtual‑Biotech/AstraZeneca/Biomni slides to **1–2 "how we compare / what we integrate" slides**), sources, honest‑scope notes.

**Content changes (keep / cut / reframe):**
- **CUT from the main flow → appendix:** the per‑competitor deep dives (ANew, Vilya, Virtual‑Biotech, AstraZeneca, Biomni). Keep ONE synthesized "landscape & where we fit / what we integrate" slide up front if needed; the rest is appendix.
- **REFRAME "Honest risks"** → a positive "**Scope & what we're transparent about**" slide (discovery‑scoped; jointly validated; no over‑claims) — keep the honesty, lose the risk‑dump tone.
- **KEEP & elevate:** requirement‑fit (4 layers), platform‑with‑search, pilot shape, deployment/IP, the generate→verify→learn differentiator.
- **PRESERVE the claims‑to‑avoid discipline** (from the BIOMATE_BRIEF): do NOT claim autonomous drug discovery, candidate nomination, or that generated molecules are synthesizable/active/safe/novel without prospective evidence; computational ADMET/docking ≠ regulatory‑grade. No fabricated metrics.

## 4. Visual design requirements
- **Brand:** BioMate identity — logo, a professional **navy + teal** palette (current deck uses `#0b2545` / `#12808a`), consistent accent, generous whitespace.
- **Replace ALL ASCII diagrams** (the 3‑layer stack, 5‑plane architecture, program‑flow) with **designed vector diagrams** (boxes, arrows, iconography). The architecture and the generate→verify→learn loop are the two hero diagrams — make them clean and memorable.
- **Add a real product UI screenshot** (the platform / workflow panel) so the client sees a real product, not just concepts.
- **Tables → designed comparison graphics** where possible (esp. the 4‑layer fit and any coverage table kept in the main flow); if kept as tables, style them cleanly (navy header, zebra, generous padding) — never let a table overflow a slide.
- **Typography:** one clean sans‑serif family that supports **CJK** (e.g., Source Han Sans / Noto Sans SC + a Latin pairing); clear hierarchy; ≤ ~6 bullets/slide.
- **Iconography** for the 4 layers, the pillars, and pilot stages.
- **One idea per slide;** move dense detail to speaker notes or appendix.

## 5. Bilingual requirement
- Produce a **中文 (Simplified) version** (primary for the client) **and** an English version — ideally a bilingual master or two synced decks. Chinese must be **idiomatic, not literal** (have a native reviewer / careful pass). Keep technical terms (ADMET, DockQ, docking, FEP) in English where that's the field norm, with 中文 gloss.

## 6. Deliverables & format
- **Editable source** (the design tool's native format) + exported **PPTX** and **PDF**, 16:9.
- A **short (≤14‑slide) client deck** for the meeting + the **full deck** (with appendix) as leave‑behind.
- Keep the markdown content file as the single source of truth for facts; design layer sits on top.

## 7. Non‑negotiables (accuracy)
- Every competitor/number stays consistent with `20260921_COMPETITIVE_INTEL_AI_DRUG_DISCOVERY.md` (confidence‑flagged; the Vilya/"Molo‑1" mapping is unverified; ByteDance "APM/AnewDPSA" are unverified — do not show).
- No capability we can't stand behind; honor the claims‑to‑avoid list.
- The requirement mapping (their 4 layers, SA·affinity·safety, discovery‑scope, on‑prem) must remain faithful to the tender docs.

## Change log
- 2026‑09‑21 — initial brief: reframe strategy deck → client product intro (client‑centric arc, competitors→appendix,
  risks→scope‑transparency), designed diagrams replacing ASCII, product screenshot, bilingual EN+中文, honesty preserved.
