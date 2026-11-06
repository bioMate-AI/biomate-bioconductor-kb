"""A failed run records WHY it failed (_nextflow_error_summary), not the last log line.

Cases are the console-log shapes of real dev failures on 2026-11-06: a task error
(nf-core/pgdb: Ensembl API 503), a launch-time script error (nf-core/moleculardynamics),
and missing test inputs (nf-core/cageseq, test data removed upstream).
"""
import ast
import os
import re
from pathlib import Path

EXECUTOR = (Path(__file__).resolve().parents[2] / "backend" / "lib" / "galaxy" / "webapps"
            / "galaxy" / "api" / "nextflow_executor.py")


def _load():
    # Pure function: compile it alone instead of importing the Galaxy app.
    tree = ast.parse(EXECUTOR.read_text())
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "_nextflow_error_summary")
    ns = {"re": re, "Path": Path, "os": os}
    exec(compile(ast.Module(body=[fn], type_ignores=[]), str(EXECUTOR), "exec"), ns)
    return ns["_nextflow_error_summary"]


summary = _load()

TASK_FAIL = """[80/ef0a78] process > output_documentation       [100%] 1 of 1 ✔
Error executing process > 'ensembl_fasta_download'

Caused by:
  Essential container in task exited

Command executed:

  pypgatk_cli.py ensembl-downloader --ensembl_name meleagris_gallopavo

Command exit status:
  1

Command output:
  (empty)

Command error:
  Traceback (most recent call last):
    File "/opt/conda/bin/pypgatk_cli.py", line 49, in <module>
      raise Exception('API response: {}'.format(response.status_code))
  Exception: API response: 503

Work dir:
  s3://bucket/work/aa/bb

-[nf-core/pgdb] Pipeline completed with errors-
"""

LAUNCH_FAIL = """ N E X T F L O W   ~  version 25.10.5

Launching `/app/nf-core-workflows/moleculardynamics/main.nf` [goofy_bhabha] DSL2 - revision: 6f7efa4ff7

ERROR ~ Cannot invoke method into() on null object

 -- Check script '/app/nf-core-workflows/moleculardynamics/modules/local/pre_pos_clean_pdb.nf' at line: 27 or see '.nextflow.log' file for more details
"""

MISSING = """Uploading local `bin` scripts folder to s3://x/bin
No such file: https://github.com/nf-core/test-datasets/raw/cageseq/reference/chr_sub.gtf


No such file: https://github.com/nf-core/test-datasets/raw/cageseq/reference/chr_sub.fasta
No such file: https://github.com/nf-core/test-datasets/raw/cageseq/reference/chr_sub.fasta
-[nf-core/cageseq] Pipeline completed with errors-
"""


def test_task_failure_names_process_cause_and_exception():
    s = summary(TASK_FAIL)
    assert s.startswith("Process ensembl_fasta_download failed: Essential container in task exited")
    assert s.endswith("Exception: API response: 503")
    assert "Work dir" not in s and "s3://" not in s


def test_launch_error_names_script_and_line():
    assert summary(LAUNCH_FAIL) == (
        "Cannot invoke method into() on null object (script pre_pos_clean_pdb.nf, line 27)")


def test_missing_inputs_listed_once():
    s = summary(MISSING)
    assert s.startswith("Input not found: ")
    assert s.count("chr_sub.fasta") == 1 and "chr_sub.gtf" in s


def test_nextflow_26_prefix_and_qualified_name():
    log = ("ERROR ~ Error executing process > 'NFCORE_DMD:DMD:NETWORKEXPANSION:GRAPHTOOLPARSER (entrez_ppi)'\n\n"
           "Caused by:\n  Task failed to start - CannotPullContainerError: no space left on device\n\n"
           "Command executed:\n\n  graph_tool_parser.py x\n")
    assert summary(log) == ("Process GRAPHTOOLPARSER (entrez_ppi) failed: "
                            "Task failed to start - CannotPullContainerError: no space left on device")


def test_no_error_is_empty():
    assert summary("") == ""
    assert summary("Completed at: today\nSucceeded   : 12\n") == ""
