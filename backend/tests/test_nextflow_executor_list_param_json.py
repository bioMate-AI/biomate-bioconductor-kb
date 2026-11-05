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
    # Re-implements the helper's predicates (no heavy import) to document intent.
    import re as _re
    ext = _re.compile(r'\.(csv|tsv|txt|json|rds|gmt|list|vcf|h5ad)(\.(gz|bz2|zip))?$', _re.I)
    uri = _re.compile(r'^[a-z][a-z0-9+.-]*://')
    def fref(v):
        s = (v or "").strip()
        if not s or s.startswith("[") or "," in s or "\n" in s:
            return False
        return bool(uri.match(s) or ext.search(s))
    # single file refs → pass-through (NOT wrapped)
    for v in ["s3://b/x/gene_list.txt", "/local/genes.txt", "genes.tsv",
              "https://x/y.gmt", "s3://b/m.rds"]:
        assert fref(v), v
    # value lists / bare values → still wrapped
    for v in ['["CC","OC"]', "CC(=O)OC1=CC=CC=C1C(=O)O", "TP53,BRCA1", "MPNN", ""]:
        assert not fref(v), v
