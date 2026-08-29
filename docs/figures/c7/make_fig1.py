#!/usr/bin/env python3
"""C7 (paper -> workflow retrieval-grounded synthesis) Figure 1.

Box-and-arrow schematic of the FIVE-stage retrieval->synthesis pipeline,
faithful to research_repos/biomate_paper2workflow_paper/manuscript/MANUSCRIPT_DRAFT.md.

Faithful stage names (quoted verbatim from the paper):
  - Abstract (line 11): "five stages (paper-fetcher -> methods-extractor ->
    tool-locator -> wrapper-generator -> chain-composer)".
  - Contributions #1 (line 31) and Pipeline overview (line 58) repeat the
    same five stages, with the status tags:
      paper-fetcher (exists) | methods-extractor (partial) |
      tool-locator (exists) | wrapper-generator (exists) |
      chain-composer (prototype) -> QC auto-loop (production).
  - Per-stage substrates (Section 3.2, lines 66-76):
      paper-fetcher: research_agent fetch primitives (Semantic Scholar, PMC
        BioC-JSON, Europe PMC, PyMuPDF).
      methods-extractor: typed methods.json IR (assay, genome build, tools+
        versions, key params, QC gates).
      tool-locator: hybrid BM25/FTS + BGE dense + entity-boost over the
        2,455-workflow catalog, type-flow graph.
      wrapper-generator: prefill / adapt / synthesize via NextflowComposer
        (confidence tiers >0.8 reuse, 0.5-0.8 adapt, <0.5 synthesize).
      chain-composer: NER -> pattern retrieval -> exemplar retrieval ->
        candidate retrieval + type-flow -> LLM compose -> verifier
        (shadow-deployed).
      QC auto-loop: try -> measure -> remediate -> retry.
  - Design invariant "Retrieval before synthesis" (line 80): rendered as the
    retrieval->synthesis divider.

Metrics omitted by design: the tool-locator numbers (Hit@5 = 1.00 etc.,
Section 5) are results, not architecture, so the schematic carries none.
Only the paper's own status tags and stage names are shown.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
# House palette (from docs/figures/c8/make_figs.py)
TEAL = "#2a9d8f"; AMBER = "#e9a23b"; RED = "#c1121f"; NAVY = "#22445f"; GREY = "#9aa5ad"


def fig1():
    fig, ax = plt.subplots(figsize=(13.0, 4.8))
    w = 2.05; h = 1.7; gap = 0.42; x = 0.25; y = 1.9

    # (name, substrate, status-tag, colour) -- colour by retrieval vs synthesis role
    stages = [
        ("paper-fetcher",
         "Semantic Scholar, PMC\nBioC-JSON, Europe PMC,\nPyMuPDF; CORE/arXiv/\nbioRxiv sources", "exists", NAVY),
        ("methods-extractor",
         "distill to typed\nmethods.json IR:\nassay, genome build,\ntools+versions, params,\nQC gates", "partial", AMBER),
        ("tool-locator",
         "hybrid BM25/FTS +\nBGE dense + entity-boost\nover 2,455-wf catalog;\ntype-flow graph", "exists", TEAL),
        ("wrapper-generator",
         "prefill / adapt /\nsynthesize (NextflowComposer);\nconfidence tiers\nreuse / adapt / synth", "exists", TEAL),
        ("chain-composer",
         "NER -> pattern & exemplar\nretrieval -> type-flow\ncompose -> verifier\n(shadow-deployed)", "prototype", NAVY),
    ]

    centers = []
    for name, sub, tag, col in stages:
        b = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.10",
                           linewidth=2, edgecolor=col, facecolor=col + "20")
        ax.add_patch(b)
        ax.text(x + w / 2, y + h - 0.28, name, ha="center", va="center",
                fontsize=10, fontweight="bold", color=col)
        ax.text(x + w / 2, y + (h - 0.85) / 2, sub, ha="center", va="center",
                fontsize=7.1, color="#333")
        ax.text(x + w / 2, y - 0.24, tag, ha="center", va="center",
                fontsize=8, style="italic", color=col)
        centers.append(x + w / 2)
        x += w + gap

    # sequential arrows
    xx = 0.25 + w
    for _ in range(len(stages) - 1):
        ax.add_patch(FancyArrowPatch((xx, y + h / 2), (xx + gap, y + h / 2),
                                     arrowstyle="-|>", mutation_scale=14, lw=1.7, color=NAVY))
        xx += w + gap

    # input paper (feeding stage 1)
    ax.text(centers[0], y + h + 0.55, "Published paper\n(Methods section prose)",
            ha="center", va="center", fontsize=8.2, color="#333",
            bbox=dict(boxstyle="round,pad=0.3", fc=GREY + "22", ec=GREY, lw=1.2))
    ax.add_patch(FancyArrowPatch((centers[0], y + h + 0.22), (centers[0], y + h + 0.02),
                                 arrowstyle="-|>", mutation_scale=12, lw=1.5, color=GREY))

    # output: executable Nextflow/nf-core pipeline
    ax.text(centers[-1], y + h + 0.55, "Executable Nextflow /\nnf-core pipeline run",
            ha="center", va="center", fontsize=8.2, color=TEAL, fontweight="bold",
            bbox=dict(boxstyle="round,pad=0.3", fc=TEAL + "18", ec=TEAL, lw=1.4))

    # QC auto-loop below the chain
    qy = y - 1.25
    qb = FancyBboxPatch((centers[2] - 2.6, qy), 5.2, 0.7,
                        boxstyle="round,pad=0.02,rounding_size=0.10",
                        linewidth=1.8, edgecolor=TEAL, facecolor=TEAL + "12")
    ax.add_patch(qb)
    ax.text(centers[2], qy + 0.35,
            "QC auto-loop (production):  try -> measure -> remediate -> retry",
            ha="center", va="center", fontsize=8.2, color=TEAL, fontweight="bold")
    ax.add_patch(FancyArrowPatch((centers[-1], y - 0.02), (centers[-1], qy + 0.72),
                                 arrowstyle="-|>", mutation_scale=12, lw=1.5,
                                 color=TEAL, linestyle="--"))

    # retrieval-before-synthesis divider (design invariant, line 80)
    # falls between methods-extractor (extract) and tool-locator (retrieval core)
    wall_x = 0.25 + 2 * (w + gap) - gap / 2
    ax.axvline(wall_x, ymin=0.24, ymax=0.80, color=RED, lw=1.4, ls="--", alpha=0.55)
    ax.text(wall_x, y + h + 0.16, "fetch + extract  ", ha="right", fontsize=8.5,
            color=NAVY, fontweight="bold")
    ax.text(wall_x, y + h + 0.16, "  retrieve -> compose (synthesis last resort)",
            ha="left", fontsize=8.5, color=RED, fontweight="bold")

    ax.text(0.25, 0.15,
            "Retrieval-first over a curated executable catalog; free synthesis is gated behind a confidence threshold and fails safe ('no pipeline found').",
            fontsize=7.6, color="#666", style="italic")

    ax.set_xlim(0, x + 0.1); ax.set_ylim(0.0, 4.7); ax.axis("off")
    ax.set_title("Figure 1. The five-stage paper-to-workflow pipeline: retrieval-grounded synthesis of an executable Nextflow/nf-core run from a paper's Methods",
                 fontsize=10.5, fontweight="bold")
    plt.tight_layout()
    out = os.path.join(HERE, "fig1_paper2workflow_pipeline.png")
    plt.savefig(out, dpi=185, bbox_inches="tight"); print("wrote", out)
    plt.close()


fig1()
