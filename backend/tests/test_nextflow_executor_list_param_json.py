"""Guard: the Nextflow executor MUST serialize list/dict params as JSON, not str().

Regression for the 272-workflow root-cause bug (2026-07, commit cb8ba2e08):
`str(["CC(=O)..."])` emits a single-quoted Python repr `"['CC(=O)...']"`. The
workflows' embedded `auto_convert()` parses params with `json.loads`, which cannot
read single-quoted reprs — so the ENTIRE list-as-a-string was handed to the tool as
ONE value (for ADMET: RDKit parsed `['CC(=O)...']` as a single SMILES → 0 valid
molecules → admet-ai `preds[:, i]` on a 1-D array → crash; showed as "cat(NoneType)"
on old chemprop and "too many indices" on chemprop 1.6.1, which is why pinning versions
never fixed it). Both executor param paths (`--params-file` and `--flag`) must
`json.dumps()` lists/dicts so `json.loads` round-trips them.

No heavy imports — reads the executor source + stdlib only, so it runs in plain CI.
"""
import json
import re
from pathlib import Path

import pytest

EXECUTOR = (
    Path(__file__).resolve().parents[1]
    / "lib/galaxy/webapps/galaxy/api/nextflow_executor.py"
)

_SMILES = ["CC(=O)OC1=CC=CC=C1C(=O)O"]


def test_str_of_list_is_NOT_json_parseable():
    # Documents WHY json is required: str([...]) is a Python repr, not JSON.
    with pytest.raises(json.JSONDecodeError):
        json.loads(str(_SMILES))


def test_json_dumps_round_trips_the_smiles_list():
    assert json.loads(json.dumps(_SMILES)) == _SMILES


def test_executor_serializes_list_dict_params_as_json_not_str():
    src = EXECUTOR.read_text()
    # window large enough to clear the explanatory comments and reach the call
    branches = re.findall(r"isinstance\(value, \(list, dict\)\):(.{0,600})", src, re.S)
    assert branches, (
        "no `isinstance(value, (list, dict))` serialization branch in the executor — "
        "list/dict params must be json.dumps'd (both --params-file and --flag paths)"
    )
    # Both param paths must serialize collections via a json .dumps(), never bare str().
    assert len(branches) >= 2, (
        f"expected list/dict json-serialization in BOTH param paths, found {len(branches)}"
    )
    for b in branches:
        assert "dumps(value)" in b, (
            f"a list/dict param branch does not json.dumps the value (regression to "
            f"str()?): {b[:140]!r}"
        )


# ── File-ref guard (2026-11-05): a *_list param that is a single FILE REFERENCE
#    (e.g. gene_list=s3://…/gene_list.txt, read via Channel.fromPath) must NOT be
#    JSON-array-wrapped — wrapping it → Nextflow "Illegal character in scheme name"
#    (clusterProfiler enrichGO UC-4). Value-lists (smiles_list) still wrap. ──
def test_both_list_branches_guarded_by_file_ref_check():
    src = EXECUTOR.read_text()
    assert "def _looks_like_single_file_ref" in src, "helper missing"
    # each `elif ... endswith("_list") or key.endswith("List")` wrapping branch must
    # include the file-ref guard within the same elif condition (allow a line-continuation).
    import re as _re
    idxs = [m.start() for m in _re.finditer(r'key\.endswith\("_list"\)', src)]
    assert len(idxs) >= 2, f"expected >=2 *_list wrapping branches, found {len(idxs)}"
    for i in idxs:
        window = src[i:i + 160]  # the elif condition + continuation line
        assert "_looks_like_single_file_ref" in window, \
            f"a *_list branch near offset {i} is not file-ref-guarded"


def test_file_ref_regex_behaviour():
    # Behavioral test of the SHIPPED guard — WITHOUT the heavy `import galaxy...`
    # (pulsar/boltons absent in plain CI). We EXTRACT the two shipped regex literals
    # from the executor source and run the exact helper logic against them, so a drift
    # in the real `_FILE_REF_EXT_RE` / `_URI_SCHEME_RE` (e.g. dropping `txt`) fails here
    # rather than passing a stale re-implementation (committee R3 #5).
    import re as _re
    src = EXECUTOR.read_text()
    ext_m = _re.search(r"_FILE_REF_EXT_RE\s*=\s*re\.compile\(\s*\n?\s*r?'([^']+)'\s*\n?\s*(?:r?'([^']*)')?", src)
    # the pattern may span two adjacent string literals (line-continued); join them
    ext_src = "".join(g for g in (ext_m.group(1), ext_m.group(2)) if g) if ext_m else None
    uri_m = _re.search(r"_URI_SCHEME_RE\s*=\s*re\.compile\(\s*r?'([^']+)'", src)
    assert ext_src and uri_m, "could not extract shipped _FILE_REF_EXT_RE / _URI_SCHEME_RE"
    ext = _re.compile(ext_src, _re.IGNORECASE)
    uri = _re.compile(uri_m.group(1))

    def fref(v):  # mirrors _looks_like_single_file_ref's control flow, using SHIPPED regexes
        s = (v or "").strip()
        if not s or s.startswith("[") or "," in s or "\n" in s:
            return False
        return bool(uri.match(s) or ext.search(s))

    # single file refs → pass-through (NOT wrapped)
    for v in ["s3://b/x/gene_list.txt", "/local/genes.txt", "genes.tsv",
              "https://x/y.gmt", "s3://b/m.rds", "/d/counts.h5ad"]:
        assert fref(v), v
    # value lists / bare values → still wrapped
    for v in ['["CC","OC"]', "CC(=O)OC1=CC=CC=C1C(=O)O", "TP53,BRCA1", "MPNN", ""]:
        assert not fref(v), v
    # the shipped ext set must still cover the core data types (guards drift/removal)
    for e in ("csv", "tsv", "txt", "json", "rds", "h5ad"):
        assert ext.search(f"x.{e}"), f"shipped _FILE_REF_EXT_RE dropped .{e}"


def test_nfcore_pipelines_get_native_collections_via_params_file():
    # Real nf-core pipelines read list params as Groovy lists (proteomicslfq 1.0.0 `input`); a
    # JSON-encoded string reached them as one non-file value. Collections for /nf-core-workflows/
    # paths must go through `-params-file` as native JSON instead of a JSON-string CLI flag.
    src = EXECUTOR.read_text()
    assert "_native_collections = (" in src
    assert '"/nf-core-workflows/" in str(nf_path)' in src
    assert 'cmd += ["-params-file", str(_native_path)]' in src
    assert "elif isinstance(value, (list, dict)) and _native_collections:" in src


def test_nfcore_param_filter_runs_before_input_path_check():
    # Pipeline-default relative globs (cageseq input='data/*R1.fastq.gz') must be dropped before
    # _validate_input_paths rejects them as missing local paths.
    src = EXECUTOR.read_text()
    assert src.index("_as_default = [k for k, v in params.items()") < src.index("    _validate_input_paths(params)")
