# BioMate Website Positioning Plan — Platform + Immune-Mediated Flagship

**Date:** 2026-10-07
**Site reviewed:** `reference/claude_design/webpage_design_v2/` (static HTML; the public site per
[[project_website_locations]]). ~90 pages; nav/shell/footer built in `shell.js`.
**Trigger:** the "scope to immune-mediated disorders" commits (`684291ac3`, `e9ff52c21`,
`e93ad3883`, `1adfbd52e`) replaced the platform identity with an immune-only identity. Goal is the
user's actual intent: *not only a platform for biomedical research, **but also** a flagship focus on
AI drug discovery for immune-mediated disorders* — additive, not substitutive.
**Guardrails:** [[feedback_formal_tone]], [[feedback_no_method_disclosure]] (state WHAT we deliver +
light credibility, never HOW or proprietary internal targets), [[feedback_citation_integrity]]
(every claim truthful/verifiable).

---

## 1. North Star — the dual identity (Insilico model)

Successful AI-drug-discovery companies (Insilico Medicine / 英矽智能, Recursion, XtalPi/晶泰) keep
**two identities parallel and separate**, never collapsing one into the other:

- **Platform (universal):** sold to everyone, not scoped to one disease (Insilico's Pharma.AI:
  PandaOmics / Chemistry42 / InClinico).
- **Therapeutic focus (narrow):** lives in a distinct **Pipeline/Programs** track (Insilico's 31
  programs across cancer, fibrosis, immunity, CNS, aging).

**BioMate mapping:**
- **Platform = the global identity** — 4,000+ validated workflows across 36 domains, plain-English
  routing, QC-graded, audit-ready. Serves every researcher.
- **Immune-mediated drug discovery = the flagship program** — the closed-loop target → peptide →
  wet-lab-validated-candidate story, in pilot. Prominent, clearly labelled "flagship," but it does
  **not** overwrite the platform tagline.

---

## 2. Current-state audit

**What is already right (keep):**
- **IA / nav** (`shell.js:42-87`): Company · Services (Drug Discovery, Genomics & Multi-Omics,
  Clinical Research, Structural Biology) · Research (Benchmarks/Tutorials/Publications/Surveys) ·
  Pricing · Developers · Newsroom. Drug Discovery is correctly one of several service tracks.
- **Breadth content:** domain landing pages — `rna-seq`, `single-cell-rna-seq`, `variant-calling`,
  `cryo-em`, `alphafold`, `molecular-docking`, `admet-prediction`; plus `features`, `services`,
  `connectors`, `benchmarks*`, `realbio`.
- **Flagship content:** deep immune/drug blog cluster — `blog-cd40l-indication-expansion`,
  `blog-cidp-macrophage-metabolic-profiling`, `blog-complement-stratification`,
  `blog-mg-immune-profiling-chain`, `blog-ra-gwas-target`, `blog-ra-responder-signature`,
  `blog-scrna-immune-profiling`, `blog-tocilizumab-ind-package`, `blog-tyk2-admet-validation`,
  `blog-glp1-modality`, the `blog-drug-1..6` lifecycle series.
- **Homepage sections** already include both a flagship "Discovery Loop" section and a
  "Platform Architecture" section — the dual story structurally exists.

**What went wrong (the shock) — top-level framing strings swung to immune-only:**
| Surface | File / line | Problem |
|---|---|---|
| Hero H1, pill, benefits, placeholder | index.html hero | identity = immune-only; no platform value for a non-drug researcher **(FIXED 2026-10-07 as the worked example)** |
| Applications lead "…built for immune — **but** the platform…" | index.html:566 | breadth framed as a caveat **(FIXED)** |
| Platform-diagram caption | index.html:554 | "AI drug discovery for immune-mediated disorders" **(FIXED)** |
| Discovery-loop eyebrow | index.html:480 | "Built for immune-mediated disorders" → now "Flagship program" **(FIXED)** |
| head title / meta / og / twitter | index.html head | immune-only titles **(FIXED, platform-first dual)** |
| CTA bar sub-headline | shell.js:104 | "AI drug discovery for immune-mediated disorders — target to validated peptide." (site-wide) |
| Footer tagline | shell.js:125 | "AI drug discovery for immune-mediated disorders." (site-wide) |
| about / services / features openers | about.html, services.html, features.html | re-scoped to immune (commit e9ff52c21) |
| schema.org descriptions | index.html:32,46,80,219 | immune-only org/product/FAQ descriptions |
| llms.txt, terms opener | llms.txt, terms.html | immune-scoped positioning (commits e93ad3883, 1adfbd52e) |

**Diagnosis:** the fix is **reframing a dozen strings + adding one flagship page**, not a rebuild.

---

## 3. What to CHANGE (rebalance to platform-first + immune flagship)

Priority order (Phase 0 = removes the shock fastest):

1. **Homepage hero + sections** — DONE 2026-10-07 (platform-first H1; immune in the pill + as
   flagship bullets; breadth de-caveated; head meta rebalanced). Serves as the pattern for the rest.
2. **`shell.js` site-wide strings** (appear on every page):
   - CTA sub (`:104`) → platform-first + flagship clause, e.g. *"One AI platform for biomedical
     research — with a flagship closed-loop engine for immune-mediated disorders."*
   - Footer tagline (`:125`) → *"The AI platform for biomedical research & drug discovery."*
3. **`about.html` / `services.html` / `features.html` openers** → lead with the platform; add a
   dedicated "Flagship: immune-mediated disorders" paragraph/section (don't delete the immune copy —
   relocate it under a flagship heading).
4. **schema.org blocks** (index.html:32,46,80,219) → platform-first org/product/FAQ descriptions
   with immune named as the flagship program (SEO consistency with the visible page).
5. **`llms.txt` + `terms.html` opener** → platform-level positioning; immune as flagship line.
6. **Per-page titles** on any page whose `<title>`/H1 was immune-scoped → platform/domain-first.

Each change is the same move: **platform is the subject; immune is the flagship clause.** Never a
"but"; never an immune-only sentence standing as the whole identity.

---

## 4. What to ADD

1. **A dedicated flagship page** — `drug-discovery.html` (or `immune-mediated-disorders.html`).
   Today the flagship is only an anchor (`services.html#drug-discovery`). Give it a full page,
   Insilico-pipeline style: the closed-loop narrative (target identification → peptide/macrocycle
   design → wet-lab-validated candidate, improving each cycle), pilot status, light credibility,
   and a CTA. **WHAT we deliver, not HOW** (see §6). Link it from the homepage Discovery-Loop
   section and from nav (Services → Drug Discovery can point here instead of the anchor).
2. **A homepage flagship band CTA** — the existing "Discovery Loop" section links through to the
   new flagship page ("See the immune-mediated program →").
3. **An immune-mediated content collection** — a Newsroom category or tag page gathering the immune
   blog cluster, so depth is visible in one place (reinforces the flagship without hijacking the
   global identity).
4. **(Optional) audience framing** — a light "For researchers · For drug-discovery teams · For
   pharma/CRO" row on the homepage so each visitor sees themselves. Decide in Phase 2.

---

## 5. Page-by-page disposition

| Page(s) | Action |
|---|---|
| index.html | CHANGE — done (hero/sections/meta); add flagship-band link in Phase 1 |
| shell.js (nav/CTA/footer, every page) | CHANGE — rebalance CTA sub + footer tagline |
| about.html, services.html, features.html | CHANGE — platform-first opener + flagship section |
| terms.html, llms.txt | CHANGE — positioning opener only |
| drug-discovery.html (NEW) | ADD — full flagship page |
| domain pages (rna-seq, cryo-em, variant-calling, single-cell, alphafold, docking, admet) | KEEP — already platform/domain-scoped; verify titles |
| benchmarks*, realbio, publications, connectors, compare, pricing, tutorials, glossary | KEEP — platform credibility; spot-check for stray immune-only tagline |
| blog/* | KEEP content; ADD immune collection/tag; verify no post forces the global identity |
| auth pages (login/register/forgot/reset) | KEEP |
| surveys/* | KEEP |

---

## 6. Confidentiality & truthfulness guardrails (decide before building the flagship page)

- **No method disclosure** ([[feedback_no_method_disclosure]]): the flagship page states the
  *capability and outcome*, plus a light credibility tag — never the proprietary method.
- **Do NOT expose internal specifics** without explicit approval: the specific targets
  (αvβ6 / GRPR), the ACT application, and the macrocycle program internals
  ([[project_act_target_simplification]], [[project_macrocycle_closedloop]]) are sensitive. Default:
  describe the flagship generically ("immune targets → validated peptide/macrocycle candidates, in a
  closed loop") unless the user wants named indications/targets public.
- **Truthful claims only** ([[feedback_citation_integrity]]): "in pilot" wet-lab, "4,000+ validated
  workflows / 36 domains" (note the validated-subset nuance — 1,092 with clean execution evidence),
  no customer logos/testimonials unless real and permitted.

---

## 7. Materials I need from you

1. **How much of the immune program is public?** Can we name indications (RA, SLE, MG, CIDP…) and/or
   targets, or keep it generic? (drives the flagship page copy; default = generic.)
2. **Truthful pipeline/pilot claims** we're allowed to state (stage, any validated result we can
   cite, "design-partner"/pilot counts).
3. **Any real pilot customers / design partners / testimonials / logos** usable on the site.
4. **Audience priority** — rank: academic researchers · biotech/pharma discovery teams · CRO/hospital
   core facilities. (sets hero/flagship emphasis.)
5. **Confirm headline metrics** are current/approved (4,000+ workflows, 36 domains, QC tiers, pilot).
6. **Deployment path** — is `reference/claude_design/webpage_design_v2/` the source that actually
   ships to the public site, and how is it deployed? (so changes go live, not just local.)
7. **Brand constraints** — any required wording for the one-line company descriptor.

---

## 8. Phased execution

- **Phase 0 — de-shock (fast, low-risk):** rebalance the ~12 framing strings (hero done → shell CTA
  + footer, about/services/features openers, schema, llms.txt, terms). Platform-first everywhere;
  immune as flagship clause. *No new pages; purely copy/hierarchy.*
- **Phase 1 — flagship page:** build `drug-discovery.html` (WHAT-not-HOW), link from homepage +
  nav. Pending §6/§7 decisions.
- **Phase 2 — depth & audience:** immune content collection; optional audience row; polish.
- **Phase 3 — QA:** render locally, link-check, consistency pass (no page left immune-only), then
  deploy.

---

## 9. Status / log

- **2026-10-07** — Plan created. Homepage hero + sections + head meta rebalanced (worked example,
  committed separately). Awaiting user input on §7 (esp. confidentiality of the immune program and
  deployment path) before Phase 0 completion + Phase 1.
</content>
