"""
galaxy.chain.artifact_contracts
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Helpers for resolving and addressing output files produced by one chain
step so they can be wired as inputs to the next step.

Two public functions:

  pick_artifact_file(files, artifact_name) -> dict | None
    Given a list of output-file dicts and a logical artifact name
    (e.g. "bam", "vcf", "reads", "output_bam"), return the best matching
    file dict, or None if nothing matches.

  artifact_value(file_dict) -> str
    Return the addressable value for a file dict — S3 URI if present,
    otherwise the local path.  Returns "" if neither is available.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

# Logical artifact name → file extensions that satisfy it (priority order)
_PARAM_TO_EXT: Dict[str, List[str]] = {
    "reads":          ["fastq", "fq", "gz"],
    "input":          ["fastq", "fq", "gz", "bam", "vcf", "tsv", "csv", "fa", "fasta"],
    "fastq":          ["fastq", "fq", "gz"],
    "fastq_input":    ["fastq", "fq", "gz"],
    "bam":            ["bam"],
    "input_bam":      ["bam"],
    "alignments":     ["bam"],
    "bai":            ["bai"],
    "bam_index":      ["bai"],
    "vcf":            ["vcf"],
    "variants":       ["vcf"],
    "input_vcf":      ["vcf"],
    "genome":         ["fa", "fasta"],
    "fasta":          ["fa", "fasta"],
    "reference":      ["fa", "fasta"],
    "samplesheet":    ["tsv", "csv"],
    "tsv":            ["tsv"],
    "csv":            ["csv"],
    "params_json":    ["json"],
    "ligand_sdf":     ["sdf"],
    "compounds":      ["sdf"],
    "ligand_file":    ["sdf"],
    "smiles":         ["smi"],
    "ligand_smiles":  ["smi"],
}

# Inverse: extension → param names it can satisfy (for fallback matching)
_EXT_TO_PARAMS: Dict[str, List[str]] = {}
for _param, _exts in _PARAM_TO_EXT.items():
    for _ext in _exts:
        _EXT_TO_PARAMS.setdefault(_ext, []).append(_param)


def pick_artifact_file(
    files: List[Dict[str, Any]],
    artifact_name: str,
) -> Optional[Dict[str, Any]]:
    """
    Return the best file from *files* that satisfies *artifact_name*.

    Resolution order:
      1. Exact filename match (e.g. artifact_name = "results.bam")
      2. Extension match via the _PARAM_TO_EXT table
      3. Filename contains artifact_name as a substring
      4. Artifact_name contains the file's extension as a substring

    Returns None when no file matches.
    """
    if not files or not artifact_name:
        return None

    name = artifact_name.lower().strip()

    # 1. Exact filename match
    for f in files:
        if f.get("filename", "").lower() == name:
            return f

    # 2. Extension-based lookup
    target_exts = _PARAM_TO_EXT.get(name)
    if target_exts:
        for ext in target_exts:
            for f in files:
                if (f.get("extension") or "").lower() == ext:
                    return f

    # 3. Filename contains artifact_name as a substring
    for f in files:
        if name in f.get("filename", "").lower():
            return f

    # 4. Artifact name contains the file extension
    for f in files:
        ext = (f.get("extension") or "").lower()
        if ext and ext in name:
            return f

    return None


def artifact_value(file_dict: Optional[Dict[str, Any]]) -> str:
    """
    Return the addressable path for a file dict.

    Prefers S3 URI (suitable for AWS Batch workers) over a local path.
    Returns "" when *file_dict* is None or neither key is present.
    """
    if not file_dict:
        return ""
    return file_dict.get("s3_uri") or file_dict.get("path") or ""
