# Figures workflow

Source files are **draw.io / diagrams.net XML** (`.drawio.xml`) — edit them in:

- [app.diagrams.net](https://app.diagrams.net) (browser, free, no install)
- VS Code extension: **Draw.io Integration** by Henning Dieterichs
- Desktop app: [diagrams.net/download](https://www.diagrams.net/#download)

## Export for publication

| Surface       | Format   | Size         | Notes                                    |
|---------------|----------|--------------|------------------------------------------|
| Substack hero | PNG/JPG  | 1200×600     | Substack auto-crops; keep key content centered |
| Substack body | PNG/SVG  | 1200×native  | SVG keeps crisp on retina; PNG is safer  |
| LinkedIn feed | PNG/JPG  | 1200×627     | 1.91:1 ratio; first 1080×1080 visible on mobile |
| Twitter / X   | PNG      | 1600×900     | 16:9                                     |

In diagrams.net: **File → Export as → PNG** → set width, transparent background off (white plays better on LinkedIn/Substack), 2× zoom for retina.

## Alternative tools if you want to redesign

- **Excalidraw** ([excalidraw.com](https://excalidraw.com)) — sketchy/hand-drawn aesthetic, exports `.excalidraw` JSON + PNG/SVG. Good for casual founder-voice posts.
- **Figma** — pixel-perfect, slow to iterate, best for hero images that need brand polish.
- **Mermaid** ([mermaid.live](https://mermaid.live)) — Markdown-style text → diagrams. Render and export PNG. Good for flowcharts you'll change often.
- **Penpot** ([penpot.app](https://penpot.app)) — open-source Figma alternative if you want self-hosting.
- **D2** ([d2lang.com](https://d2lang.com)) — text-based, very nice automatic layouts; CLI exports SVG/PNG.

For BioMate marketing we standardize on **draw.io XML** because it's plain text (diff-friendly in git), editable in browser without an account, and round-trips losslessly with PNG/SVG export.

## Current figures

| File                                | Used in              | Purpose                            |
|-------------------------------------|----------------------|------------------------------------|
| `post_1_fragmentation_map.drawio.xml`| Substack + LinkedIn  | 8 specialty silos → BioMate orchestration layer |
| `post_5_triangle.drawio.xml`        | Substack + LinkedIn  | Prediction → Simulation → Validation closed loop |
| `post_5_benefits_stack.drawio.xml`  | Substack             | Single program → Portfolio → Business outcomes |
| `post_8_rag_stack.drawio.xml`       | Substack + LinkedIn  | Four-layer evidence-grounded RAG architecture |
| `post_9_options_matrix.drawio.xml`  | Substack + LinkedIn  | 4 LLM build options + where BioMate sits (default + exception) |
| `post_12_context_stack.drawio.xml`  | Substack + LinkedIn  | Context-management 4-layer stack (vs ChatInvent context-explosion) |
| `post_13_tool_grounding.drawio.xml` | Substack + LinkedIn  | Registry-bounded tool selection vs free-text hallucination |
| `post_14_param_extraction.drawio.xml` | Substack + LinkedIn | Rule-first / LLM-fallback / schema-guardrail 3-stage pipeline |
| `post_15_auto_loop.drawio.xml`      | Substack + LinkedIn  | Auto-loop QC remediation cycle with HITL approval |
| `post_16_memory_governance.drawio.xml` | Substack + LinkedIn | Episode + correction memory + prediction registry + governance |
| `post_22_eval_matrix.drawio.xml`    | Substack + LinkedIn  | Public benchmarks vs ChatInvent problems vs BioMate eval matrix (opinion piece) |
| *(TBD)* `post_10_inhibitor_two_agent.drawio.xml` | Substack + LinkedIn | ANDV inhibitor: pocket → pharmacophore → ADMET → Vina + Agent A/B split |
| *(TBD)* `post_11_plan_a_epitope.drawio.xml` | Substack + LinkedIn | Plan A: samplesheet → epitopeprediction → MHCnuggets; NOT mhcquant routing |

