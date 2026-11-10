"""Format compatibility for chain handoffs.

When one workflow's output is wired into the next workflow's input param — in an explicit chain OR an
ad-hoc "run A then B" sequence — the file FORMAT must match what the downstream param expects. The
param-declaration check (``binding_check``) and the from_output-resolution guard
(``workflow_chain._apply_connection_handoffs``) do not look at format, so a ``.smi`` wired into a
param that needs an ``.sdf`` (or ``.pdbqt`` into one that needs ``.sdf``) launches and fails at
runtime. This module lets the executor gate it BEFORE launch.

Conservative by design: it only reports a mismatch when BOTH the resolved file's format and the
downstream param's expected format are known AND incompatible. Unknown expected format -> no gate.

stdlib only; Python 3.9 safe.
"""
from __future__ import annotations

import re
from typing import Optional, Set

# Canonical format -> the file extensions (lowercase) that count as that format.
_FORMATS = {
    "sdf":   {"sdf", "mol", "mdl"},
    "mol2":  {"mol2"},
    "smi":   {"smi", "smiles", "ism"},
    "pdb":   {"pdb", "ent"},
    "pdbqt": {"pdbqt"},
    "cif":   {"cif", "mmcif"},
    "vcf":   {"vcf", "vcf.gz", "bcf"},
    "bam":   {"bam", "cram", "sam"},
    "bai":   {"bai", "crai"},
    "fasta": {"fasta", "fa", "fna", "faa", "fas"},
    "fastq": {"fastq", "fq", "fastq.gz", "fq.gz"},
    "gtf":   {"gtf", "gff", "gff3"},
    "bed":   {"bed", "narrowpeak", "broadpeak"},
    "csv":   {"csv"},
    "tsv":   {"tsv", "txt", "tab"},
    "json":  {"json"},
    "yaml":  {"yaml", "yml"},
    "rds":   {"rds"},
    "h5ad":  {"h5ad", "h5", "hdf5", "loom"},
    "gds":   {"gds"},
    "nc":    {"nc", "netcdf", "cdf"},
    "npz":   {"npz", "npy"},
    "mrc":   {"mrc", "mrcs", "map"},
}
_EXT2FMT = {ext: fmt for fmt, exts in _FORMATS.items() for ext in exts}
_DOUBLE_EXTS = ("vcf.gz", "fastq.gz", "fq.gz")

# A param expecting the KEY format ALSO accepts these ``got`` formats, because the value commonly
# ships in those containers. Keeps the gate conservative: it must never fire on a handoff that
# actually works. SMILES routinely travel as .csv/.txt/.tsv (a column of SMILES), not only .smi;
# csv/tsv are delimited text that tools usually read with a delimiter arg. Asymmetric where it
# should be: a tabular file is accepted INTO an smi-param, but an .smi is not auto-accepted into a
# strict .csv-parsing param. The real incompatibilities this gate exists for (.smi/.csv -> .sdf,
# .pdbqt -> .pdb, .bam -> .vcf) are untouched.
_ACCEPTS = {
    "smi": {"csv", "tsv"},
    "csv": {"tsv"},
    "tsv": {"csv"},
}

# Role suffixes that don't change the declared format (ligand_sdf_file ≡ ligand_sdf).
_ROLE_SUFFIXES = {"file", "files", "path", "paths", "input", "inputs", "output", "outputs", "dir"}


def _ext_of(filename: str) -> str:
    n = (filename or "").lower().rstrip("/")
    n = n.rsplit("/", 1)[-1]
    for two in _DOUBLE_EXTS:
        if n.endswith("." + two):
            return two
    return n.rsplit(".", 1)[-1] if "." in n else ""


def file_format(filename: str) -> Optional[str]:
    """Canonical format of a filename, or None if the extension is unrecognised."""
    return _EXT2FMT.get(_ext_of(filename))


def expected_input_format(param_name: str, nf_text: Optional[str] = None) -> Optional[str]:
    """The format a downstream file-param expects.

    1. the param name's FINAL meaningful segment is a format token, after dropping role suffixes
       (``ligand_sdf`` -> sdf, ``input_vcf`` -> vcf, ``sdf_file`` -> sdf). A format token only as a
       PREFIX of a scalar name does NOT count (``bed_padding``, ``bam_sort_threads``,
       ``tsv_delimiter``, ``smiles_list`` -> unknown, don't gate); else
    2. the extension of the param's default value in the workflow ``.nf`` (``params.ligand = 'x.sdf'``); else
    3. None (unknown -> callers must not gate).
    """
    parts = [p for p in re.split(r"[_\W]+", (param_name or "").lower()) if p]
    while parts and parts[-1] in _ROLE_SUFFIXES:
        parts.pop()
    if parts and (parts[-1] in _EXT2FMT or parts[-1] in _FORMATS):
        tok = parts[-1]
        return _EXT2FMT.get(tok, tok if tok in _FORMATS else None)
    if nf_text:
        dm = re.search(
            r"params\.%s\s*=\s*['\"]([^'\"]+\.[A-Za-z0-9.]+)['\"]" % re.escape(param_name),
            nf_text,
        )
        if dm:
            return file_format(dm.group(1))
    return None


def compatible(got_fmt: Optional[str], expected_fmt: Optional[str]) -> bool:
    """True unless both formats are known and incompatible (unknown -> compatible, don't gate).

    A format is compatible with itself and with any it is an accepted container for (``_ACCEPTS``)."""
    if expected_fmt is None or got_fmt is None:
        return True
    if got_fmt == expected_fmt:
        return True
    return got_fmt in _ACCEPTS.get(expected_fmt, frozenset())


def mismatch_message(resolved_filename: str, to_input: str, nf_text: Optional[str] = None) -> Optional[str]:
    """A one-line gate message if the resolved file's format is incompatible with ``to_input``'s
    expected format, else None. A declared transform is assumed to handle conversion — the caller
    skips this check when a transform is present."""
    got = file_format(resolved_filename)
    exp = expected_input_format(to_input, nf_text)
    if compatible(got, exp):
        return None
    return (
        "format mismatch: '%s' (%s) wired into '%s' which expects %s — add a %s->%s convert step "
        "or a transform" % (resolved_filename, got, to_input, exp, got, exp)
    )
