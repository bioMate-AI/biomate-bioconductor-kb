"""Resource classification: group a workflow's processes and size them per group.

Today ~96% of the ~3,800 subworkflow processes carry a blanket ``process_medium`` label (6 vCPU / 36 GB),
so a FASTQC step and a genome alignment request the same slot. That over-provisions the light/standard
majority (wasting cost and parallel capacity) and under-provisions the genuinely heavy steps.

This module groups a process by what it *does* (from its process name) and maps the group to a resource
tier. The group->tier numbers are a single source of truth that a deployment can override for its own
hardware (env ``BIOMATE_RESOURCE_TIERS_JSON``), which is the seam on-prem needs — we do NOT yet know any
on-prem environment, so nothing here assumes a fixed cluster size.

How it is applied (``nextflow_executor``): per run, only for processes that ACTUALLY EXIST in the
dispatched ``main.nf``, a ``withName:`` selector is emitted. ``withName`` overrides ``withLabel``, so a
process named ``FASTQC`` labelled ``process_medium`` gets the ``light`` tier. Emitting selectors only for
present processes avoids Nextflow 24+ strict-mode exit-1 on a selector that matches nothing. Anything
unmatched keeps its existing label-based tier (``process_medium`` default) — so this is additive and safe.

Gated OFF by default (``BIOMATE_RESOURCE_CLASSIFICATION``); when off the executor injects nothing new and
behaviour is identical to before.

Python 3.9-safe: no PEP 604 unions, no subscripted builtins at runtime.
"""
from __future__ import annotations

import json
import logging
import os
import re
from typing import Dict, List, Optional, Tuple

log = logging.getLogger(__name__)

ENV_FLAG = "BIOMATE_RESOURCE_CLASSIFICATION"        # "1"/"true" to enable per-run withName sizing
ENV_TIERS = "BIOMATE_RESOURCE_TIERS_JSON"           # JSON {group: {cpus, memory_gb}} to override per deployment

# Group -> resource tier. Conservative "start" defaults; a deployment overrides via ENV_TIERS.
# cpus/memory only — queue/time stay with the existing label block.
RESOURCE_GROUPS: Dict[str, Dict[str, int]] = {
    "light":     {"cpus": 2,  "memory_gb": 8},    # QC, plotting, reporting, trimming, filtering, format conversion
    "standard":  {"cpus": 4,  "memory_gb": 16},   # DE, enrichment, annotation, normalisation, single-cell stats
    "heavy":     {"cpus": 12, "memory_gb": 64},   # alignment, assembly, variant calling, taxonomic classification
    "shardable": {"cpus": 4,  "memory_gb": 16},   # ADMET / docking shards — throughput comes from fan-out, each shard is small
    # 'gpu' deliberately omitted: GPU processes already carry process_gpu and are sized + queue-routed
    # by the executor's existing process_gpu block. Reclassifying them here would fight that.
}

# Ordered (first match wins). Each entry: (compiled regex over the UPPER-CASED process name, group).
# Patterns are matched against the Nextflow process name (e.g. "STAR_ALIGN", "BIOC_DESEQ2", "FASTQC").
# Specific/heavy patterns come before generic ones so e.g. VARIANT_ANNOTATION -> heavy (variant), not standard (annot).
_PATTERNS: List[Tuple[str, str]] = [
    # heavy — multi-core and/or big memory
    (r"\b(BWA|BOWTIE2?|STAR|HISAT2?|MINIMAP2?|SALMON|KALLISTO|ALIGN(?!ER_REPORT))", "heavy"),
    (r"(ASSEMBL|SPADES|MEGAHIT|FLYE|CANU|TRINITY)", "heavy"),
    (r"(VARIANT|GATK|HAPLOTYPECALLER|MUTECT|DEEPVARIANT|STRELKA|SAREK|BCFTOOLS_CALL)", "heavy"),
    (r"(KRAKEN|METAPHLAN|CENTRIFUGE|DIAMOND|BLAST)", "heavy"),
    # shardable — many small independent units; fan out rather than one big job
    (r"(ADMET|DOCK|VINA|PHARMACOPHORE_SCREEN)", "shardable"),
    # light — I/O-bound, seconds of compute
    (r"(FASTQC|MULTIQC|\bQC\b|QUALITY)", "light"),
    (r"(PLOT|VIZ|VISUAL|HEATMAP|VOLCANO|UMAP_PLOT)", "light"),
    (r"(REPORT|RENDER|MARKDOWN|SUMMAR)", "light"),
    (r"(TRIM|CUTADAPT|FASTP|FILTER|SUBSET|FORMAT_?CONVER|SORT_?BAM|INDEX_?BAM|SAMTOOLS_(SORT|INDEX|FLAGSTAT))", "light"),
    # standard — single-threaded compute, moderate memory
    (r"(DESEQ|EDGER|LIMMA|DE_?ANALYSIS|DIFFERENTIAL)", "standard"),
    (r"(ENRICH|GSEA|CLUSTERPROFILER|PATHWAY|ORA\b|FGSEA)", "standard"),
    (r"(ANNOT|VEP(?!_LARGE)|SNPEFF|FUNCTIONAL)", "standard"),
    (r"(NORMAL|SCALE|BATCH_?CORRECT|COMBAT)", "standard"),
    (r"(SEURAT|SCANPY|SINGLER|CLUSTER(?!PROFILER)|HARMONY|INTEGRAT)", "standard"),
    (r"(PREDICT|SCORE|RANK|INFER)(?!.*ADMET)", "standard"),
]
_COMPILED: List[Tuple["re.Pattern[str]", str]] = [(re.compile(p), g) for p, g in _PATTERNS]

# Nextflow process declaration: "process NAME {"
_PROCESS_RE = re.compile(r"^\s*process\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{", re.MULTILINE)


def is_enabled() -> bool:
    return os.environ.get(ENV_FLAG, "").strip().lower() in ("1", "true", "yes", "on")


def tiers() -> Dict[str, Dict[str, int]]:
    """Group->tier, with a deployment override from ENV_TIERS merged over the defaults."""
    out = {g: dict(v) for g, v in RESOURCE_GROUPS.items()}
    raw = os.environ.get(ENV_TIERS, "").strip()
    if raw:
        try:
            override = json.loads(raw)
            for g, v in (override or {}).items():
                if g in out and isinstance(v, dict):
                    if "cpus" in v:
                        out[g]["cpus"] = int(v["cpus"])
                    if "memory_gb" in v:
                        out[g]["memory_gb"] = int(v["memory_gb"])
        except (ValueError, TypeError) as exc:
            log.warning("[resource_classification] ignoring malformed %s: %s", ENV_TIERS, exc)
    return out


def classify_process(process_name: str) -> Optional[str]:
    """Return the resource group for a process name, or None if nothing matches (keep its label tier)."""
    if not process_name:
        return None
    name = process_name.upper()
    for rx, group in _COMPILED:
        if rx.search(name):
            return group
    return None


def classify_nf_text(nf_text: str) -> Dict[str, str]:
    """Map each process DECLARED in this .nf to its group (processes with no match are omitted)."""
    out: Dict[str, str] = {}
    for m in _PROCESS_RE.finditer(nf_text or ""):
        name = m.group(1)
        group = classify_process(name)
        if group:
            out[name] = group
    return out


def render_withname_lines(nf_text: str) -> List[str]:
    """Nextflow config lines sizing only the processes present in this .nf by their group.

    Returns [] when disabled, when nothing classifies, or when no tier differs — so the caller can add
    the block unconditionally. withName selectors are emitted ONLY for present processes (strict-mode safe)."""
    if not is_enabled():
        return []
    classified = classify_nf_text(nf_text)
    if not classified:
        return []
    tier = tiers()
    lines: List[str] = ["process {"]
    for name in sorted(classified):
        group = classified[name]
        t = tier.get(group)
        if not t:
            continue
        # Exact process name; withName matches the simple name or a fully-qualified one.
        lines.append(
            "    withName: '%s' { cpus = %d; memory = '%d.GB' }   // group=%s"
            % (name, int(t["cpus"]), int(t["memory_gb"]), group)
        )
    if len(lines) == 1:
        return []
    lines.append("}")
    return lines
