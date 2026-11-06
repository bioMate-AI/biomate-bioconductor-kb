# Design Requirement → claude-design: BD + Marketing-Oriented Product Deck

**Date:** 2026-09-22
**Requester:** BD team (via product)
**For:** claude-design (produce a marketing-grade visual design system + slide prototypes, HTML in the `reference/claude_design/` convention, which we render to the client PPTX)
**Baseline content:** `BioMate-Market-Overview-CN-EN-v1.pptx` (10 slides, on Drive `BioMate-Decks/`) — the *content* is settled; this brief is about **restyling it to BD/marketing grade**, not rewriting the message.
**Companion (do not restyle):** the technical deck `…-v10-final.pptx` stays as-is for technical evaluators.

---

## 1. Objective

Turn the settled 10-slide market narrative into a **visually persuasive, marketing-grade** deck a pharma **business-development / executive** audience can be sold on in 5 minutes. Today's style is clean but *technical/minimalist* — it reads as an engineering artifact. BD needs it to read as a **product/market story**: confident, benefit-led, visually alive, one clear message per slide.

The strategic message is fixed and must survive the restyle:
- BioMate is a **leading end-to-end AI drug-discovery platform** — outstanding today, improving every cycle.
- It has **proprietary depth** in three areas: the **closed loop**, **speed engineering**, and the **in-house generative model**.
- It **meets the full requirement baseline** (incl. multi-objective optimization across affinity · safety · synthesizability) and covers the **whole R&D chain**.

## 2. Audience

Pharma BD leads, business heads, and executives (Guangzhou/Guangdong client). Bilingual **中文 + English**, Chinese-primary. Assume **low patience for jargon**, high interest in **value, differentiation, and proof**.

## 3. What "BD + marketing oriented" means here (the shift)

| From (current technical style) | To (BD/marketing style) |
|---|---|
| Dense multi-column text cards | **One headline idea per slide**, supported by a strong visual |
| Flat white slides, thin rules | **Depth**: brand color blocks, subtle gradients, generous whitespace, hero moments |
| Feature lists | **Benefit + outcome** language, with 1–3 **big numbers / stat callouts** per section |
| Diagram-as-documentation | **Signature visuals**: the generate→verify→learn **flywheel** as a hero graphic; product shots in **browser/device frames** |
| Uniform slide rhythm | **Section dividers**, a clear narrative arc, a strong cover and a strong closing/CTA |
| Neutral tone | **Confident market tone** — still honest, never hype |

## 4. Narrative arc (keep this order; restyle each beat)

1. **Cover** — brand hero. Tagline, not a spec.
2. **Why BioMate** — the value promise: *outstanding today · optimizing every cycle*.
3. **The AI inside** — four AI engines (generative · predictive · multi-objective · closed-loop) as an at-a-glance visual.
4. **Differentiation** — the three proprietary-depth pillars (loop · speed · generative model). This is the confidence slide.
5. **The closed loop** — the flywheel as the signature hero visual.
6–7. **Product proof** — Chinese UI + workflow-panel screenshots in polished frames.
8. **Deliverables** — the decision-ready candidate package (what the client receives).
9. **Whole-R&D-chain breadth** — a clean capability map, target-ID → clinic.
10. **Engagement path** — the how-we-start / CTA close.

## 5. Visual design language

- **Color:** brand teal (`#12808A` / `#29A2AB`) as the marketing accent on a deep navy (`#0B2545`) foundation; introduce **1 warm/energy accent** for stat highlights and the flywheel. Use **color blocks and soft gradients** for depth (current deck is nearly monochrome).
- **Type:** keep **Source Sans 3** (Latin) + **Microsoft YaHei** as the CJK East-Asian face (`<a:ea>` MUST be a CJK font or PowerPoint shows tofu — this is a hard, already-learned constraint). Bigger, bolder headline scale for marketing impact.
- **Layout:** 20″×11.25″ (16:9). One dominant element per slide. Strong left-aligned headline system, consistent footer/pagination.
- **Iconography:** one consistent line-icon set, one icon per capability — replace text-heavy bullets with icon + short benefit.
- **Signature graphic:** a polished **generate → verify → learn flywheel** (circular, motion-implied) as the deck's memorable visual; reuse its motif on the differentiation + AI slides.
- **Data-viz / stat callouts:** big-number treatments for the value story (e.g., faster cycles, more of the chemical space screened, higher makeable-hit rate). **Any number shown must be real or clearly labeled illustrative** — no invented metrics.
- **Product shots:** frame the Chinese UI screenshots in clean browser mockups; never raw/cropped-off screenshots. Screenshots must be **Chinese UI** (client-facing).
- **If delivered as HTML prototype:** follow the `reference/claude_design/` handoff convention (see `data_centroid_design_v2`, `biomate-intro-v3` for structure); tasteful motion allowed in HTML, but it must degrade to a static PPTX.

## 6. Content & tone rules (HARD — these caused rework already)

- **No first-person possessive** — do **not** use "我们的 / our". Use objective phrasing ("差异化优势", "核心差异化"), not "我们的独特之处".
- **No second-person "你的 / your"** addressing the client — reads as rude/presumptuous. Use **"自有 / in-house / on-premises / the…"** ("在自有数据上训练", "on in-house data"), never "your data / your bench".
- **No literal tailoring / reach** — do **not** write out the client's ask or how we stretch to it ("客户此次聚焦… / Your ask is…", "满足…要求 / meets the requirement"). State the capability confidently; let the fit be self-evident.
- **No named-competitor jabs** — do not name or disparage other companies (no "X 仅覆盖 4 个领域 / X covers only 4 areas"). Position on our strengths, objectively.
- **No method / tool-stack disclosure** — state **what** is delivered + a light credibility tag, never the **how**: no model class/architecture, no diffusion/RL/DPO, no tool names (nf-core, sarek, REINVENT4, OpenFE, AWS/Nextflow, etc.). Differentiation is described at the **feature/benefit level only**.
- **Idiomatic Chinese** — natural marketing Chinese, not literal calques (rejected example: "越用越强" → prefer "模型持续优化"). Have a native reviewer pass.
- **Honesty** — confident but never over-claim; no "first/only/no-competitor" absolutes; illustrative numbers labeled as such.
- **Bilingual pairing** — every slide carries 中文 (primary) + concise English; keep them consistent in meaning.

## 7. Differentiation framing (get this exactly right)

Lead the moat on the two **genuinely defensible** axes; present multi-objective as strong **delivered capability**, not as an invention:
- **Unique (moat):** (1) generative model **purpose-built for hard-to-drug chemistry** (macrocycles/peptides), **valid-by-construction**; (2) **proprietary-data closed loop** (learns from wet-lab feedback, self-correcting, verification-gated).
- **Table-stakes we fully deliver:** multi-objective optimization across **affinity · safety · synthesizability**; speed engineering (tiered cascade + massive parallel cloud). Present confidently, but **do not claim as our invention**.

## 8. Production constraints (carry over — already validated)

- Output: **PPTX 20″×11.25″**; optional HTML prototype first.
- Fonts: Source Sans 3 + **Microsoft YaHei for CJK (`<a:ea>`)** — non-negotiable to avoid tofu.
- Verify CJK rendering with macOS **QuickLook** (`qlmanage -t`), **not** LibreOffice (can't render CJK on our Mac — false-tofu).
- Keep the package clean (no orphan slide parts).

## 9. Reference assets

- Baseline content deck: Drive `BioMate-Decks/BioMate-Market-Overview-CN-EN-v1.pptx`.
- Chinese UI screenshots + completed-run panels: `docs/20260922_good_run_screens/` (recapture in Chinese once the i18n UI is live on dev).
- claude_design structure precedents: `reference/claude_design/{biomate-intro-v3, data_centroid_design_v2}`.
- Brand mark: `/tmp/deck_assets/image-1-1.png` (logo).

## 10. Acceptance criteria

- One clear message per slide; a BD reader gets the value in ≤5 min.
- Marketing-grade visual depth (color, hero flywheel, framed product shots, stat callouts) — visibly beyond the current minimalist style.
- **Zero** occurrences of 我们的 / 你的 / your / literal tailoring / competitor names / method-stack terms.
- CJK renders correctly (QuickLook-verified); no tofu; clean package.
- Strategic message + differentiation framing (§7) intact.
