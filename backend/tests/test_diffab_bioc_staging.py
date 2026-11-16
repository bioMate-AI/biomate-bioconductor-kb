"""Stream-6 root-cause fix: the differentialabundance stub must route through the
executor's declared-input bioc wrapper (local file staging) instead of raw
`Channel.fromPath(s3://)` (which throws 'Exception thrown downloading S3 object').

This execs the REAL helper block from nextflow_executor.py (the full module can't
import locally — missing a2wsgi web deps) and runs `_build_bioc_entry_wrapper`
against the edited stub with local CSV inputs.

Run:  cd backend && python3 -m pytest tests/test_diffab_bioc_staging.py -q
"""
import os, re, shutil, tempfile
from pathlib import Path
from typing import Optional

import pytest

EXEC_SRC = Path(__file__).resolve().parents[1] / "lib/galaxy/webapps/galaxy/api/nextflow_executor.py"
STUB_NF = Path(__file__).resolve().parents[1] / "biomni_workflows/nfcore/differentialabundance/main.nf"

# MERGE NOTE (merge/demos-onto-mainline): the mainline snapshot (8f0374ff)
# independently rewrote this exact stub to fix the SAME S3-download root cause via
# a competing design — Channel.fromPath(..., checkIfExists: true) + a vendored
# demo-data fallback inside an anonymous `workflow {}` — and also added a whole
# limma/microarray branch and GEO-safe `condition_grp` DESeq2 design. Those edits
# are mutually exclusive with this feature's take:-bound declared-input shape
# (header `// Input:` + `take:` + no anonymous `workflow {}`). To honor "zero loss
# of the other session's work", the merge resolved differentialabundance/main.nf to
# mainline, so this contract is NOT satisfied in the merged tree. Marked xfail
# (non-strict) pending a human decision on whether to adopt the take:-bound entry
# (dropping mainline's redundant demo-fallback entry) — see
# three_demos_merge_status.md. The design-QC gate itself is still covered by
# tests/test_deseq2_design_qc_gate.py (config + reader, no .nf dependency).
pytestmark = pytest.mark.xfail(
    reason="diffab stub resolved to mainline's competing S3-fix/limma rewrite; "
           "take:-bound declared-input shape deferred (see three_demos_merge_status.md)",
    strict=False,
)


def _load_helpers():
    """Exec lines 1663.._extract_documented_images from the executor in isolation."""
    src = EXEC_SRC.read_text().splitlines()
    # from `_BIOC_INPUT_DECL_RE = ` up to (not incl.) `def _extract_documented_images`
    start = next(i for i, l in enumerate(src) if l.startswith("_BIOC_INPUT_DECL_RE"))
    end = next(i for i, l in enumerate(src) if l.startswith("def _extract_documented_images"))
    block = "\n".join(src[start:end])

    class _Log:
        def info(self, *a, **k): pass
        def warning(self, *a, **k): pass
        def error(self, *a, **k): pass

    ns = {"re": re, "os": os, "shutil": shutil, "Path": Path, "Optional": Optional,
          "log": _Log(), "__name__": "executor_helpers"}
    exec(compile(block, str(EXEC_SRC), "exec"), ns)
    return ns


def test_diffab_routes_through_bioc_wrapper():
    ns = _load_helpers()
    text = STUB_NF.read_text()

    # Contract the executor requires for the bioc wrapper:
    assert ns["_BIOC_INPUT_DECL_RE"].search(text), "missing `// Input:` header"
    names_raw = ns["_BIOC_INPUT_DECL_RE"].search(text).group(1)
    names = [n.strip() for n in re.split(r"[,\s]+", names_raw) if n.strip()]
    assert names == ["samplesheet.csv", "matrix.csv", "contrasts.csv"], names
    assert re.search(r"(?m)^\s*take:\s*$", text), "no take: block -> wrapper won't engage"
    assert not re.search(r"(?m)^\s*workflow\s*\{", text), "anonymous workflow{} would bypass the wrapper"
    assert re.search(r"path\(input_files,\s*stageAs", text), "process must use path(stageAs)"

    # Run the REAL wrapper builder with LOCAL inputs (no S3, no Channel.fromPath).
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        src_dir = td / "src"; src_dir.mkdir()
        (src_dir / "ss.csv").write_text("sample,cell,dex\nSRR1,N61311,untrt\nSRR2,N61311,trt\n")
        (src_dir / "mx.csv").write_text("gene_id,SRR1,SRR2\nENSG1,10,200\nENSG2,300,5\n")
        (src_dir / "ct.csv").write_text("id,variable,reference,target\nd,dex,untrt,trt\n")
        run_dir = td / "run"; run_dir.mkdir()
        params = {
            "samplesheet": str(src_dir / "ss.csv"),
            "matrix": str(src_dir / "mx.csv"),
            "contrasts": str(src_dir / "ct.csv"),
            "differential_max_qval": 0.05,
        }
        wrapper = ns["_build_bioc_entry_wrapper"](STUB_NF, params, run_dir, "t1")
        assert wrapper is not None, "wrapper not generated -> would fall back to the failing path"
        wtext = Path(wrapper).read_text()

        # The wrapper binds the PROCESS with staged LOCAL files, not Channel.fromPath(s3).
        assert "DESEQ2_DIFFERENTIAL_ANALYSIS( Channel.of(" in wtext
        assert "Channel.fromPath" not in wtext
        for fn in ("samplesheet.csv", "matrix.csv", "contrasts.csv"):
            assert (run_dir / fn).exists(), f"{fn} not staged locally"
            assert f"file('{(run_dir / fn).resolve().as_posix()}')" in wtext
        # declared-input keys are consumed (popped) so they aren't passed as --flags
        for k in ("samplesheet", "matrix", "contrasts"):
            assert k not in params, f"{k} should be popped after staging"


if __name__ == "__main__":
    import pytest, sys
    sys.exit(pytest.main([__file__, "-q"]))
