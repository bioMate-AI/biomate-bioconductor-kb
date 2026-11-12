"""
Folder profile — what a project FOLDER holds as a whole, not file by file.

A folder upload is more than a container: ``pairs/`` with ``S1_R1.fastq.gz``,
``S1_R2.fastq.gz`` and ``S2_R1.fastq.gz`` is one paired sample plus an orphan R1, and
``tenx/`` with ``matrix.mtx`` + ``barcodes.tsv`` + ``features.tsv`` is ONE 10x matrix whose
two TSVs are header-less by specification. A per-file profiler cannot see either fact, so
this module profiles the folder from its file names (plus the Matrix Market size line of a
10x matrix, read through a caller-supplied callback):

* **FASTQ pairing** reads the read number from the token right before the extension (or
  before Illumina's ``_001`` chunk): ``WT_1_1``/``WT_1_2`` are read 1/2 of replicate ``WT_1``,
  ``S_R10_R1`` is read 1 of ``S_R10``, lanes (``_L001``/``_L002``) are runs of ONE sample, and
  ``I1``/``I2`` index reads are set aside (they are barcodes, not sample reads). Galaxy's own
  list:paired builder (``galaxy.model.dataset_collections.auto_pairing.auto_pair``) is run as a
  cross-check when importable (it pulls the whole ``galaxy.model`` package, so it is imported
  lazily); its pairs are used when they agree, and ``engine`` / ``engineReason`` in the output
  say which pairing was used and why (Galaxy raised, was unavailable, or paired across replicates).
* **10x Genomics matrices** follow the Cell Ranger output spec: ``matrix.mtx(.gz)`` +
  ``barcodes.tsv(.gz)`` + ``features.tsv(.gz)`` (v3) or ``genes.tsv(.gz)`` (v2), optionally
  with a common sample prefix (GEO: ``GSM123_matrix.mtx.gz``), one set per directory
  (``filtered_feature_bc_matrix/``, ``raw_feature_bc_matrix/``). Cells × genes come from the
  matrix's size line (rows = features, columns = barcodes).
* Everything else is rolled up by format ("12 files: 8 FASTQ (4 pairs), 2 CSV, 2
  unrecognised").

Findings carry a code + params (rendered by the UI through i18n ``perception.msg.<code>``),
exactly like the per-file profiler. Pure: no I/O except the ``read_head`` callback, no
network, no third-party imports — loadable on its own by file path (unit tests).
"""
from __future__ import annotations

import csv
import io
import logging
import posixpath
import re
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Pairing — read-number token at the END of the name, cross-checked with Galaxy's auto_pair
# ---------------------------------------------------------------------------
# Galaxy's filter table (galaxy.model.dataset_collections.auto_pairing.COMMON_FILTERS, the
# client's pairing.ts): filter type → (forward marker, reverse marker). Used for the pattern label.
COMMON_FILTERS: Dict[str, Tuple[str, str]] = {
    "illumina": ("_1", "_2"),
    "Rs": ("_R1", "_R2"),
    "dot12s": (".1.fastq", ".2.fastq"),
}

# The read number is the token immediately before the FASTQ extension, or before Illumina's
# trailing chunk number (``_001``): ``S1_L001_R1_001.fastq.gz``, ``WT_1_2.fq.gz`` (Novogene:
# sample WT, replicate 1, read 2), ``S_R10_R1.fastq`` (sample S_R10), ``x.1.fastq``. A marker
# anywhere else in the name is part of the sample name — Galaxy's auto_pair substitutes the
# marker everywhere (``re.sub("_1", "", "WT_1_1")`` → ``WT``), which paired replicates with each
# other or raised; reads are never paired that way here. ``I1``/``I2`` are index (barcode) reads.
_FASTQ_EXT_RE = re.compile(r"\.(?:fastq|fq|fastqsanger)(?:\.(?:gz|bgz|bz2|zst))?$", re.I)
_READ_TOKEN_RE = re.compile(r"^(?P<base>.+?)(?P<sep>[._])(?P<tok>[RrIi]?[12])(?P<chunk>_\d{3})?$")
_LANE_RE = re.compile(r"^(?P<sample>.+?)_L\d{3}$")


@dataclass
class _Element:
    """What auto_pair expects (a ``.name``) + the project path it stands for."""

    name: str
    path: str


@dataclass
class ReadName:
    """How one FASTQ file name reads: ``base`` (the name without the read token: sample + lane),
    ``sample`` (``base`` without an Illumina lane token), ``style`` (Galaxy filter type: Rs |
    illumina | dot12s, None when the name carries no read token), ``mate`` (1 | 2 | None),
    ``index`` (an I1/I2 index read), ``lane`` (L001 … or None)."""

    base: str
    sample: str
    style: Optional[str]
    mate: Optional[int]
    index: bool
    lane: Optional[str]


def _filename_to_element_identifier(filename: str) -> str:
    """Port of galaxy.model.dataset_collections.auto_identifiers.filename_to_element_identifier."""
    basename = posixpath.basename(filename.split("?", 1)[0])
    for zip_extension in [".zip", ".tar.gz", ".tar", ".tgz", ".gz", "bz2", ".bz"]:
        if basename.endswith(zip_extension):
            basename = basename[: -len(zip_extension)]
    if "." in basename:
        basename = basename.split(".")[0]
    return basename


def read_name(name: str) -> ReadName:
    """Parse a FASTQ file name (see _READ_TOKEN_RE)."""
    base_name = posixpath.basename(name)
    stem = _FASTQ_EXT_RE.sub("", base_name)
    if stem == base_name:  # not a FASTQ extension: strip one compression + one extension
        stem = _filename_to_element_identifier(base_name)
    m = _READ_TOKEN_RE.match(stem)
    style: Optional[str] = None
    mate: Optional[int] = None
    index = False
    base = stem
    if m:
        tok = m.group("tok").upper()
        base = m.group("base")
        mate = int(tok[-1])
        if tok[0] == "I":
            index, style = True, "Rs"
        elif tok[0] == "R":
            style = "Rs"
        else:
            style = "dot12s" if m.group("sep") == "." else "illumina"
    lane_m = _LANE_RE.match(base)
    lane = base[len(lane_m.group("sample")) + 1:] if lane_m else None
    sample = lane_m.group("sample") if lane_m else base
    return ReadName(base=base, sample=sample, style=style, mate=mate, index=index, lane=lane)


def _dominant_style(parsed: Sequence[ReadName]) -> Optional[str]:
    """The read-token style of a directory (Galaxy's guess_initial_filter_type rule, on the
    end-anchored tokens): the most common; a tie goes to ``illumina`` like Galaxy's."""
    counts: Dict[str, int] = {}
    for r in parsed:
        if r.style and not r.index:
            counts[r.style] = counts.get(r.style, 0) + 1
    if not counts:
        return None
    best = max(counts.values())
    winners = [s for s, c in counts.items() if c == best]
    return winners[0] if len(winners) == 1 else "illumina"


def pair_reads(elements: Sequence[Any]) -> Tuple[List[Tuple[str, Any, Any]], List[Any], Optional[str]]:
    """Pair ``elements`` (objects with ``.name``) by the end-anchored read token.

    Returns (pairs [(base, forward, reverse)], unpaired, filter type). Index reads must be removed
    by the caller. A second file claiming the same (base, mate) stays unpaired.
    """
    parsed = [(e, read_name(e.name)) for e in elements]
    style = _dominant_style([r for _e, r in parsed])
    slots: Dict[str, List[Any]] = {}
    order: List[str] = []
    unpaired: List[Any] = []
    for e, r in parsed:
        if style is None or r.style != style or r.mate is None:
            unpaired.append(e)
            continue
        slot = slots.get(r.base)
        if slot is None:
            slot = slots[r.base] = [None, None]
            order.append(r.base)
        i = r.mate - 1
        if slot[i] is None:
            slot[i] = e
        else:
            unpaired.append(e)
    pairs: List[Tuple[str, Any, Any]] = []
    for base in order:
        f, rv = slots[base]
        if f is not None and rv is not None:
            pairs.append((base, f, rv))
        else:
            unpaired.append(f if f is not None else rv)
    return pairs, unpaired, style


_GALAXY_PAIRING: List[Any] = []


def _galaxy_pairing() -> Any:
    """Galaxy's auto_pairing module, or None when galaxy.model cannot import (laptop, tests)."""
    if not _GALAXY_PAIRING:
        try:
            from galaxy.model.dataset_collections import auto_pairing  # heavy: galaxy.model

            _GALAXY_PAIRING.append(auto_pairing)
        except Exception as exc:  # noqa: BLE001 — the end-anchored pairing does not need it
            log.info("[folder_profile] Galaxy auto_pairing unavailable (%s)", exc)
            _GALAXY_PAIRING.append(None)
    return _GALAXY_PAIRING[0]


def _pair_set(pairs: Sequence[Tuple[str, Any, Any]]) -> set:
    return {(id(f), id(r)) for _n, f, r in pairs}


def auto_pair(
    elements: Sequence[Any], engine: str = "auto", galaxy: Any = None
) -> Tuple[List[Tuple[str, Any, Any]], List[Any], Optional[str], str, Optional[str]]:
    """Pair ``elements`` (objects with ``.name``; index reads already removed).

    Galaxy's list:paired builder (``auto_pairing.auto_pair``) runs when importable and its pairs
    are kept when every one of them pairs the same two files as the end-anchored rule
    (:func:`pair_reads`). When Galaxy raises (a name holding both markers, e.g. ``WT_1_2``), is
    unavailable, or pairs files across replicates, the end-anchored pairing is used and the reason
    recorded. Returns (pairs, unpaired, filter_type, engine, engine_reason): engine is "galaxy" or
    "fallback"; ``engine="fallback"`` skips Galaxy (tests). ``galaxy`` injects the module (tests).
    """
    pairs, unpaired, style = pair_reads(elements)
    if engine == "fallback":
        return pairs, unpaired, style, "fallback", "forced"
    mod = galaxy if galaxy is not None else _galaxy_pairing()
    if mod is None:
        return pairs, unpaired, style, "fallback", "galaxy_unavailable"
    try:
        res = mod.auto_pair(list(elements))
        gpairs = [(p.name, p.forward, p.reverse) for p in res.paired]
    except Exception as exc:  # noqa: BLE001 — e.g. a name matching BOTH markers (list.remove twice)
        reason = f"galaxy_error:{type(exc).__name__}"
        log.info("[folder_profile] Galaxy auto_pair failed (%s: %s); using the end-anchored pairing",
                 type(exc).__name__, exc)
        return pairs, unpaired, style, "fallback", reason
    if _pair_set(gpairs) != _pair_set(pairs):
        log.info("[folder_profile] Galaxy auto_pair disagrees with the end-anchored read tokens; using the latter")
        return pairs, unpaired, style, "fallback", "galaxy_disagrees"
    return pairs, unpaired, style, "galaxy", None


# ---------------------------------------------------------------------------
# Name-level format classification
# ---------------------------------------------------------------------------
_COMPRESSION = (".gz", ".bgz", ".bz2", ".zst")
_FASTQ_EXTS = (".fastq", ".fq", ".fastqsanger")


def _strip_compression(name: str) -> str:
    low = name.lower()
    for suf in _COMPRESSION:
        if low.endswith(suf):
            return name[: -len(suf)]
    return name


def is_fastq_name(name: str) -> bool:
    return _strip_compression(posixpath.basename(name)).lower().endswith(_FASTQ_EXTS)


# Default (Galaxy-free) name → (format key, label). The API layer passes a classifier backed by
# Galaxy's datatype labels (galaxy_formats.filename_exts / label_for) instead.
_DEFAULT_FORMATS: Dict[str, str] = {
    "fastq": "FASTQ", "fq": "FASTQ", "fasta": "FASTA", "fa": "FASTA", "fna": "FASTA", "faa": "FASTA",
    "vcf": "VCF", "bcf": "BCF", "bam": "BAM", "cram": "CRAM", "sam": "SAM", "bai": "BAI", "crai": "CRAI",
    "bed": "BED", "narrowpeak": "narrowPeak", "broadpeak": "broadPeak", "bedgraph": "bedGraph",
    "gtf": "GTF", "gff": "GFF", "gff3": "GFF3", "csv": "CSV", "tsv": "TSV", "tabular": "Tabular",
    "txt": "Text", "json": "JSON", "jsonl": "JSON Lines", "yaml": "YAML", "yml": "YAML", "mtx": "Matrix Market",
    "h5ad": "AnnData (h5ad)", "loom": "Loom", "h5": "HDF5", "rds": "RDS", "xlsx": "Excel (xlsx)",
    "pdb": "PDB", "cif": "mmCIF", "sdf": "SDF", "smi": "SMILES", "mrc": "MRC", "tif": "TIFF", "tiff": "TIFF",
    "png": "PNG", "jpg": "JPEG", "jpeg": "JPEG", "pdf": "PDF", "html": "HTML", "pod5": "POD5",
    "bigwig": "bigWig", "bw": "bigWig", "md5": "Checksum",
}
_FORMAT_ALIASES = {"fq": "fastq", "fastqsanger": "fastq", "fa": "fasta", "fna": "fasta", "faa": "fasta",
                   "yml": "yaml", "tif": "tiff", "bw": "bigwig", "jpeg": "jpg"}


def default_classify(name: str) -> Tuple[str, str]:
    """(format key, label) from the file name; ("unrecognised", "") when the name claims none."""
    base = _strip_compression(posixpath.basename(name)).lower()
    if "." not in base:
        return "unrecognised", ""
    ext = base.rsplit(".", 1)[1]
    if ext not in _DEFAULT_FORMATS:
        return "unrecognised", ""
    return _FORMAT_ALIASES.get(ext, ext), _DEFAULT_FORMATS[ext]


# ---------------------------------------------------------------------------
# 10x Genomics matrix sets (Cell Ranger output spec)
# ---------------------------------------------------------------------------
# <prefix>matrix.mtx(.gz) | <prefix>barcodes.tsv(.gz) | <prefix>features.tsv(.gz) | <prefix>genes.tsv(.gz)
_TENX_PART = re.compile(r"^(?P<prefix>.*?)(?P<part>matrix\.mtx|barcodes\.tsv|features\.tsv|genes\.tsv)(?:\.gz)?$", re.I)
_TENX_ROLE = {"matrix.mtx": "matrix", "barcodes.tsv": "barcodes", "features.tsv": "features", "genes.tsv": "features"}


def _tenx_key(path: str) -> Optional[Tuple[str, str, str, str]]:
    """(directory, prefix, role, part) when the name is a 10x matrix part, else None.
    A prefix must end at a separator ("GSM1_", "S1-", "S1.") so "mygenes.tsv" is not a part."""
    d, base = posixpath.split(path)
    m = _TENX_PART.match(base)
    if not m:
        return None
    prefix = m.group("prefix")
    if prefix and prefix[-1] not in "_-.":
        return None
    part = m.group("part").lower()
    return d, prefix, _TENX_ROLE[part], part


def tenx_sets(paths: Sequence[str]) -> List[Dict[str, Any]]:
    """Group 10x parts by (directory, prefix). A group is a 10x set when it has a matrix plus at
    least one of barcodes / features (a lone ``matrix.mtx`` is just a Matrix Market file)."""
    groups: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for p in paths:
        k = _tenx_key(p)
        if not k:
            continue
        d, prefix, role, part = k
        g = groups.setdefault((d, prefix), {"dir": d, "prefix": prefix})
        if role in g:  # e.g. both features.tsv and genes.tsv — keep the first, it is still a set
            continue
        g[role] = p
        if role == "features":
            g["version"] = "v2" if part == "genes.tsv" else "v3"
    out = []
    for (_d, _p), g in sorted(groups.items()):
        if "matrix" in g and ("barcodes" in g or "features" in g):
            g["complete"] = "barcodes" in g and "features" in g
            g["missing"] = [r for r in ("barcodes", "features") if r not in g]
            out.append(g)
    return out


def parse_mtx_header(text: Optional[str]) -> Optional[Dict[str, Any]]:
    """{rows, cols, nnz, field} from a Matrix Market head (banner + size line), else None."""
    if not text:
        return None
    lines = text.splitlines()
    if not lines or not lines[0].lower().startswith("%%matrixmarket"):
        return None
    banner = lines[0].split()
    for line in lines[1:]:
        s = line.strip()
        if not s or s.startswith("%"):
            continue
        try:
            dims = [int(x) for x in s.split()]
        except ValueError:
            return None
        if len(dims) < 2:
            return None
        return {"rows": dims[0], "cols": dims[1], "nnz": dims[2] if len(dims) > 2 else None,
                "field": banner[3].lower() if len(banner) > 3 else ""}
    return None


# ---------------------------------------------------------------------------
# Folder profile
# ---------------------------------------------------------------------------
def _finding(out: Dict[str, Any], code: str, level: str = "info", **params: Any) -> None:
    out["findings"].append({"code": code, "level": level, "params": params})


def _rel(path: str, folder: str) -> str:
    return path[len(folder) + 1:] if folder and path.startswith(folder + "/") else path


def _fastq_section(fastq_paths: Sequence[str], engine: str = "auto") -> Dict[str, Any]:
    """Pair FASTQs per directory (two runs' S1_R1 never pair across directories)."""
    by_dir: Dict[str, List[_Element]] = {}
    for p in fastq_paths:
        by_dir.setdefault(posixpath.dirname(p), []).append(_Element(name=posixpath.basename(p), path=p))
    samples: List[Dict[str, Any]] = []
    index_reads: List[Dict[str, Any]] = []
    patterns: List[str] = []
    engines: List[str] = []
    reasons: List[str] = []
    for d in sorted(by_dir):
        elements: List[_Element] = []
        for e in by_dir[d]:
            r = read_name(e.name)
            if r.index:
                index_reads.append({"path": e.path, "sample": r.sample, "read": f"I{r.mate}", "dir": d})
            else:
                elements.append(e)
        if not elements:
            continue
        pairs, unpaired, filter_type, used, reason = auto_pair(elements, engine)
        engines.append(used)
        if reason and reason not in reasons:
            reasons.append(reason)
        if filter_type and filter_type not in patterns:
            patterns.append(filter_type)
        for _base, f, rv in pairs:
            r = read_name(f.name)
            samples.append({"sample": r.sample, "forward": f.path, "reverse": rv.path, "status": "paired",
                            "dir": d, "lane": r.lane})
        for e in unpaired:
            r = read_name(e.name)
            role = None
            if filter_type and r.style == filter_type and r.mate is not None:
                role = "forward" if r.mate == 1 else "reverse"
            sample = r.sample if role else _filename_to_element_identifier(e.name)
            samples.append({
                "sample": sample, "forward": e.path if role != "reverse" else None,
                "reverse": e.path if role == "reverse" else None,
                "status": "orphan" if role else "single", "role": role, "dir": d, "lane": r.lane if role else None,
            })
    samples.sort(key=lambda s: (s["sample"], s["dir"], s.get("lane") or "", s["forward"] or s["reverse"] or ""))
    n_pairs = sum(1 for s in samples if s["status"] == "paired")
    orphans = [s for s in samples if s["status"] == "orphan"]
    singles = [s for s in samples if s["status"] == "single"]
    if n_pairs and not orphans and not singles:
        verdict = "paired"
    elif n_pairs:
        verdict = "mixed"
    else:
        verdict = "single_end"
    if engine == "fallback":
        used_engine = "fallback"
    else:
        used_engine = "galaxy" if engines and all(e == "galaxy" for e in engines) else "fallback"
    return {
        "verdict": verdict,
        "pattern": (patterns or [None])[0],
        # Every read-token style in use (per directory): S1_R1/_R2 beside WT_1_1/_2 is BOTH.
        "patterns": patterns,
        "engine": used_engine,
        "engineReason": "; ".join(reasons) if used_engine == "fallback" and reasons else None,
        "pairs": n_pairs,
        "samples": samples,
        "orphans": [s["forward"] or s["reverse"] for s in orphans],
        "singles": [s["forward"] for s in singles],
        "indexReads": [x["path"] for x in sorted(index_reads, key=lambda x: x["path"])],
    }


# Where samplesheet paths are relative to: the project's input files (the paths the project file
# tree shows). A pipeline run resolves them against the staged inputs.
SAMPLESHEET_PATH_BASE = "project inputs"


def _sheet(samples: Sequence[Dict[str, Any]], filename: str, layout: str) -> Dict[str, Any]:
    rows = []
    for s in samples:
        fq1 = s.get("forward") or s.get("reverse") or ""
        fq2 = s.get("reverse") if s.get("forward") else ""
        rows.append([re.sub(r"\s+", "_", str(s["sample"])), fq1, fq2 or ""])
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(["sample", "fastq_1", "fastq_2"])
    w.writerows(rows)
    return {"columns": ["sample", "fastq_1", "fastq_2"], "rows": rows, "csv": buf.getvalue(),
            "filename": filename, "layout": layout, "pathBase": SAMPLESHEET_PATH_BASE}


def samplesheet(samples: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    """nf-core style samplesheet(s) (sample,fastq_1,fastq_2), one row per sample/run, paths
    relative to the project's inputs (``pathBase``). Spaces in sample names become "_" (nf-core
    rejects them).

    A run takes ONE layout, so paired and unpaired files are never mixed in one sheet: with at
    least one pair, the sheet holds the paired samples only (``layout`` "paired") and the
    orphans / single files go to a separate single-end sheet in ``single`` (``layout``
    "single_end", fastq_2 empty, a lone R2 as that row's fastq_1) with ``excluded`` naming them;
    without any pair the sheet IS the single-end sheet."""
    paired = [s for s in samples if s.get("status") == "paired"]
    unpaired = [s for s in samples if s.get("status") != "paired"]
    if not paired:
        return _sheet(unpaired, "samplesheet.csv", "single_end")
    out = _sheet(paired, "samplesheet.csv", "paired")
    if unpaired:
        out["single"] = _sheet(unpaired, "samplesheet_single_end.csv", "single_end")
        out["excluded"] = [s.get("forward") or s.get("reverse") for s in unpaired]
    return out


_PATTERN_LABEL = {"Rs": "_R1/_R2", "illumina": "_1/_2", "dot12s": ".1.fastq/.2.fastq"}


def profile_folder(
    folder: str,
    names: Sequence[str],
    *,
    read_head: Optional[Callable[[str], Optional[str]]] = None,
    classify: Callable[[str], Tuple[str, str]] = default_classify,
    engine: str = "auto",
    decisions: Optional[Dict[str, Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Profile the folder ``folder`` ("" = the project's input root) holding ``names`` (project
    file paths, every file below the folder, any depth).

    ``read_head(path)`` returns the first few KB of a file as text (decompressed) or None; it is
    only called for the matrix of each 10x set. ``decisions`` maps a path to the per-file profiler's
    content decision for it (``{"ext", "label", "viewKind"}`` — data_perception.decide, the SAME
    decision the file's own profile shows); the roll-up uses it, and ``classify`` (from the name)
    only for files without one. A ``dir`` param of None in a 10x finding means the profiled
    folder itself (the client says "this folder"). Returns the JSON shape the UI consumes.
    """
    folder = folder.strip("/")
    paths = sorted({n for n in names if n})
    out: Dict[str, Any] = {"path": folder, "fileCount": len(paths), "kind": "empty", "rollup": [], "findings": []}
    if not paths:
        _finding(out, "folder_empty")
        return out

    fastqs = [p for p in paths if is_fastq_name(p)]
    sets = tenx_sets(paths)
    in_set = {s[r] for s in sets for r in ("matrix", "barcodes", "features") if r in s}

    # Format roll-up (FASTQ carries its pair count), grouped by (format, label) so a TSV and a
    # featureCounts table — both "tsv" — are listed as the file panel labels them.
    counts: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for p in paths:
        view: Optional[str] = None
        dec = (decisions or {}).get(p)
        if p in fastqs:
            key, label, view = "fastq", "FASTQ", "reads"
        elif dec and dec.get("ext") and dec.get("label"):
            key, label, view = str(dec["ext"]), str(dec["label"]), dec.get("viewKind")
        else:
            key, label = classify(p)
        c = counts.setdefault((key, label), {"format": key, "label": label, "count": 0})
        if view and "viewKind" not in c:
            c["viewKind"] = view
        c["count"] += 1

    if fastqs:
        fq = _fastq_section(fastqs, engine)
        out["fastq"] = fq
        out["samplesheet"] = samplesheet(fq["samples"])
        counts[("fastq", "FASTQ")]["pairs"] = fq["pairs"]
        labels = [_PATTERN_LABEL[x] for x in fq["patterns"] if x in _PATTERN_LABEL]
        if fq["pairs"]:
            # ``pattern``: every naming style in use, joined in English ("_R1/_R2 and _1/_2");
            # ``patterns``: the same as a list, for a localized join.
            _finding(out, "folder_fastq_pairs", pairs=fq["pairs"], pattern=" and ".join(labels), patterns=labels)
        for s in fq["samples"]:
            if s["status"] == "orphan":
                name = posixpath.basename(s["forward"] or s["reverse"])
                style = read_name(name).style
                missing = "R2" if s["role"] == "forward" else "R1"
                if style == "illumina":
                    missing = "_2" if s["role"] == "forward" else "_1"
                elif style == "dot12s":
                    missing = ".2.fastq" if s["role"] == "forward" else ".1.fastq"
                _finding(out, "folder_fastq_orphan", "watch", name=name, sample=s["sample"], missing=missing)
        if fq["indexReads"]:
            _finding(out, "folder_fastq_index_reads", n=len(fq["indexReads"]),
                     names=[posixpath.basename(p) for p in fq["indexReads"][:8]])
        if fq["singles"] and not fq["pairs"] and not fq["orphans"]:
            _finding(out, "folder_fastq_single_end", n=len(fq["singles"]))
        if fq["verdict"] == "mixed":
            _finding(out, "folder_fastq_mixed_layout", "watch", pairs=fq["pairs"],
                     unpaired=len(fq["orphans"]) + len(fq["singles"]))
        runs: Dict[str, int] = {}
        for s in fq["samples"]:
            runs[s["sample"]] = runs.get(s["sample"], 0) + 1
        for sample, n in sorted(runs.items()):
            if n > 1:
                _finding(out, "folder_fastq_sample_runs", sample=sample, n=n)
        sheet = out["samplesheet"]
        _finding(out, "folder_samplesheet", rows=len(sheet["rows"]), layout=sheet["layout"],
                 path_base=SAMPLESHEET_PATH_BASE)
        if sheet.get("single"):
            _finding(out, "folder_samplesheet_single_end", rows=len(sheet["single"]["rows"]),
                     filename=sheet["single"]["filename"], names=[posixpath.basename(x) for x in sheet["excluded"][:8]])

    if sets:
        tenx = []
        for s in sets:
            rec = {k: s.get(k) for k in ("dir", "prefix", "matrix", "barcodes", "features", "version", "complete", "missing")}
            rec["dir"] = _rel(rec["dir"], folder) if rec["dir"] != folder else ""
            head = None
            if read_head is not None:
                try:
                    head = read_head(s["matrix"])
                except Exception as exc:  # noqa: BLE001 — an unreadable head is a finding, not a crash
                    log.info("[folder_profile] mtx head read failed for %s: %s", s["matrix"], exc)
            dims = parse_mtx_header(head)
            if dims:
                rec.update(genes=dims["rows"], cells=dims["cols"], nnz=dims["nnz"])
                _finding(out, "folder_tenx_recognised", cells=dims["cols"], genes=dims["rows"],
                         nnz=dims["nnz"] if dims["nnz"] is not None else "—", version=rec.get("version") or "",
                         dir=rec["dir"] or None)
            else:
                _finding(out, "folder_tenx_recognised_nodims", version=rec.get("version") or "", dir=rec["dir"] or None)
                if read_head is not None:
                    _finding(out, "folder_tenx_mtx_unreadable", "watch", name=posixpath.basename(s["matrix"]))
            if not s["complete"]:
                _finding(out, "folder_tenx_incomplete", "watch", dir=rec["dir"] or None,
                         missing=", ".join(s["missing"]))
            tenx.append(rec)
        out["tenx"] = {"sets": tenx}
        _finding(out, "folder_tenx_headerless")

    if sets and not fastqs:
        out["kind"] = "tenx_matrix"
    elif fastqs and len(fastqs) == len(paths):
        out["kind"] = "fastq_set"
    else:
        out["kind"] = "mixed"
    out["rollup"] = sorted(counts.values(), key=lambda c: (c["format"] == "unrecognised", -c["count"], c["label"]))
    out["tenxFiles"] = sorted(in_set)
    return out


# ---------------------------------------------------------------------------
# Per-file context: what the folder says about ONE file (used by the per-file profiler)
# ---------------------------------------------------------------------------
def fastq_layout(name: str, siblings: Sequence[str]) -> Optional[Dict[str, Any]]:
    """For a FASTQ ``name`` and the other files of its directory: {status, sample, role, mate,
    pattern} — status "paired" | "orphan" | "single" | "index" (an I1/I2 index read, role
    "index"). None when ``name`` is not a FASTQ."""
    if not is_fastq_name(name):
        return None
    r = read_name(name)
    if r.index:
        return {"status": "index", "sample": r.sample, "role": "index", "mate": None,
                "pattern": "", "read": f"I{r.mate}"}
    d = posixpath.dirname(name)
    same_dir = [s for s in siblings if s != name and posixpath.dirname(s) == d and is_fastq_name(s)]
    fq = _fastq_section([name] + same_dir)
    for s in fq["samples"]:
        if name in (s["forward"], s["reverse"]):
            if s["status"] == "paired":
                role = "forward" if s["forward"] == name else "reverse"
            else:
                role = s.get("role")
            mate = None
            if s["status"] == "paired":
                mate = s["reverse"] if s["forward"] == name else s["forward"]
            return {"status": s["status"], "sample": s["sample"], "role": role,
                    "mate": posixpath.basename(mate) if mate else None,
                    "pattern": _PATTERN_LABEL.get(fq["pattern"] or "", "")}
    return None


def tenx_member(name: str, siblings: Sequence[str]) -> Optional[Dict[str, Any]]:
    """{role, version, matrix} when ``name`` belongs to a 10x matrix set together with
    ``siblings`` (files of the same directory), else None."""
    for s in tenx_sets([name] + [x for x in siblings if x != name]):
        for role in ("matrix", "barcodes", "features"):
            if s.get(role) == name:
                part = lambda r: posixpath.basename(s[r]) if s.get(r) else None  # noqa: E731
                return {"role": role, "version": s.get("version"), "matrix": part("matrix"),
                        "barcodes": part("barcodes"), "features": part("features")}
    return None


# 10x spec column names for the header-less TSVs (Cell Ranger ≥3: features.tsv has 3 columns;
# v2 genes.tsv has 2).
TENX_COLUMNS = {
    "features": ["feature_id", "feature_name", "feature_type"],
    "barcodes": ["barcode"],
}
