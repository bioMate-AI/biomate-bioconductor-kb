"""Shared helpers for the paper figure/table scripts.

Rules enforced here:
  * every number plotted is read from a COMMITTED artifact (src() records the last commit hash of the
    file and flags files with uncommitted changes);
  * every plotted value that has a counterpart in the artifact is passed through check(), which writes
    an assertion log (out/assertion_log.txt);
  * outputs are deterministic (fixed seeds, no creation dates in PDF metadata);
  * missing results render a PENDING watermark, never invented numbers.
"""
from __future__ import annotations

import hashlib
import json
import math
import subprocess
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]                      # repo root (…/biomate-review)
GA = HERE.parent                            # research/guangzhou_all_atom
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)
LOG = OUT / "assertion_log.txt"
MANIFEST = OUT / "figure_sources.jsonl"

# Okabe-Ito colour-blind-safe palette
C = dict(black="#000000", orange="#E69F00", sky="#56B4E9", green="#009E73", yellow="#F0E442",
         blue="#0072B2", vermilion="#D55E00", purple="#CC79A7", grey="#8c8c8c")
# consistent model colours across figures (plan: same colours/ordering everywhere)
MODEL_COLORS = {
    "baseline GBM": C["blue"],
    "ChemBERTa": C["sky"],
    "small cyclic-peptide LM (atom LM / IH-LM)": C["orange"],
    "v4 (mapped subset)": C["purple"],
    "larger pretrained peptide/chemistry LMs": C["vermilion"],
    "rule / prior only": C["green"],
    "random": C["grey"],
}

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 8, "axes.titlesize": 9, "axes.labelsize": 8,
    "xtick.labelsize": 7, "ytick.labelsize": 7, "legend.fontsize": 7, "axes.spines.top": False,
    "axes.spines.right": False, "axes.linewidth": 0.7, "lines.linewidth": 1.2, "figure.dpi": 100,
    "savefig.dpi": 300, "pdf.fonttype": 42, "ps.fonttype": 42,
})

_src_cache: dict[str, dict] = {}


def _git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True).stdout.strip()


def src(rel: str) -> Path:
    """Return the path of a COMMITTED artifact. If the working-tree copy differs from HEAD (someone is editing it), the HEAD blob is
    materialised under out/_committed/ and used instead, so figures never depend on uncommitted data."""
    p = (ROOT / rel) if (ROOT / rel).exists() else (GA / rel)
    if not p.exists():
        raise FileNotFoundError(f"artifact not found: {rel}")
    relp = str(p.relative_to(ROOT))
    if relp not in _src_cache:
        commit = _git("log", "-1", "--format=%h", "--", relp)
        if not commit:
            raise RuntimeError(f"{relp} is not committed — figures may use committed artifacts only")
        dirty = bool(_git("status", "--porcelain", "--", relp))
        use = p
        if dirty:
            blob = subprocess.run(["git", "-C", str(ROOT), "show", f"HEAD:{relp}"], capture_output=True).stdout
            use = OUT / "_committed" / relp
            use.parent.mkdir(parents=True, exist_ok=True)
            use.write_bytes(blob)
            log(f"NOTE {relp}: working tree differs from HEAD; using the committed version {commit}")
        _src_cache[relp] = dict(path=relp, commit=commit, dirty=dirty, sha256=hashlib.sha256(use.read_bytes()).hexdigest()[:16], _use=str(use))
    return Path(_src_cache[relp]["_use"])


def log(msg: str) -> None:
    with open(LOG, "a") as f:
        f.write(msg + "\n")
    print(msg)


def check(name: str, plotted, artifact, tol: float = 1e-9) -> None:
    """Assert that a plotted value equals the artifact value; log the result."""
    ok = (plotted == artifact) if not isinstance(artifact, float) else math.isclose(float(plotted), float(artifact), abs_tol=tol)
    log(f"{'OK  ' if ok else 'FAIL'} {name}: plotted={plotted!r} artifact={artifact!r}")
    if not ok:
        raise AssertionError(f"{name}: plotted {plotted!r} != artifact {artifact!r}")


def reread(rel: str, *keys):
    """Fresh read of one value from a committed JSON artifact by key path (independent of the plotting dicts)."""
    obj = json.load(open(src(rel)))
    for k in keys:
        obj = obj[k]
    return obj


def hbar_check(cont, name: str, rel: str, keys, kmean="point", klo="lo", khi="hi") -> None:
    """After ax.errorbar(..., xerr=...) check the DRAWN marker and interval against a fresh read of the artifact."""
    x = float(cont.lines[0].get_xdata()[0])
    seg = cont.lines[2][0].get_segments()[0]
    check(name + " | point", x, float(reread(rel, *keys, kmean)))
    check(name + " | lo", float(seg[0][0]), float(reread(rel, *keys, klo)))
    check(name + " | hi", float(seg[1][0]), float(reread(rel, *keys, khi)))


def vbar_check(cont, name: str, rel: str, keys, kmean="point", klo="lo", khi="hi") -> None:
    """Same for vertical error bars (yerr)."""
    y = float(cont.lines[0].get_ydata()[0])
    seg = cont.lines[2][0].get_segments()[0]
    check(name + " | point", y, float(reread(rel, *keys, kmean)))
    check(name + " | lo", float(seg[0][1]), float(reread(rel, *keys, klo)))
    check(name + " | hi", float(seg[1][1]), float(reread(rel, *keys, khi)))


def check_many(name: str, pairs, tol: float = 1e-9) -> None:
    """Compare many (plotted, artifact) pairs; log one summary line; raise on the first mismatch."""
    bad = [(a, b) for a, b in pairs if not math.isclose(float(a), float(b), abs_tol=tol)]
    log(f"{'OK  ' if not bad else 'FAIL'} {name}: {len(pairs) - len(bad)}/{len(pairs)} values match the artifact")
    if bad:
        raise AssertionError(f"{name}: mismatches {bad[:3]}")


def _relp(rel: str) -> str:
    p = (ROOT / rel) if (ROOT / rel).exists() else (GA / rel)
    return str(p.relative_to(ROOT))


def sources_of(*rels: str) -> list[dict]:
    out = []
    for r in rels:
        src(r)
        d = dict(_src_cache[_relp(r)])
        d.pop("_use", None)
        out.append(d)
    return out


def savefig(fig, name: str, title: str, caption: str, sources: list[dict]) -> None:
    """Write PDF + PNG with provenance metadata (title, caption, source paths + commit hashes)."""
    kw = "; ".join(f"{s['path']}@{s['commit']}{' (HEAD version; working tree differs)' if s['dirty'] else ''}" for s in sources)
    pdf_meta = {"Title": title, "Subject": caption[:500], "Keywords": kw, "Creator": "figures_paper", "CreationDate": None}
    fig.savefig(OUT / f"{name}.pdf", metadata=pdf_meta, bbox_inches="tight")
    fig.savefig(OUT / f"{name}.png", metadata={"Title": title, "Description": caption[:500], "Source": kw}, bbox_inches="tight")
    plt.close(fig)
    with open(MANIFEST, "a") as f:
        f.write(json.dumps(dict(figure=name, title=title, caption=caption, sources=sources, status="rendered")) + "\n")
    log(f"WROTE {name}.pdf/.png  sources: {kw}")


def watermark(fig_or_ax, text: str = "PENDING", alpha: float = 0.18, size: int = 46) -> None:
    target = fig_or_ax
    target.text(0.5, 0.5, text, transform=target.transAxes if hasattr(target, "transAxes") else target.transFigure,
                ha="center", va="center", rotation=30, fontsize=size, color=C["grey"], alpha=alpha, fontweight="bold",
                zorder=100)


def pending_figure(name: str, title: str, waits_for: str, spec: str, sources: list[dict] | None = None) -> None:
    """A placeholder canvas: states what the figure will show and which artifact it waits for."""
    fig, ax = plt.subplots(figsize=(6.2, 3.4))
    ax.axis("off")
    ax.text(0.0, 0.92, title, fontsize=10, fontweight="bold", va="top", transform=ax.transAxes)
    ax.text(0.0, 0.78, "Not drawn: results are not yet available.\n\nWaits for: " + waits_for + "\n\nPlanned content: " + spec,
            fontsize=8, va="top", wrap=True, transform=ax.transAxes)
    watermark(ax)
    with open(MANIFEST, "a") as f:
        f.write(json.dumps(dict(figure=name, title=title, caption=f"PENDING: waits for {waits_for}", sources=sources or [],
                                status="pending")) + "\n")
    fig.savefig(OUT / f"{name}_PENDING.pdf", metadata={"Title": title + " (PENDING)", "CreationDate": None}, bbox_inches="tight")
    fig.savefig(OUT / f"{name}_PENDING.png", bbox_inches="tight")
    plt.close(fig)
    log(f"PENDING {name}: waits for {waits_for}")


def fmt_ci(mean, lo, hi, nd: int = 2) -> str:
    return f"{mean:.{nd}f} [{lo:.{nd}f}, {hi:.{nd}f}]"
