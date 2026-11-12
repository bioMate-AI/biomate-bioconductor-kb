"""
Failure diagnosis for AWS Batch runs (nextflow_executor._classify_failure +
_collect_failed_task_errors_s3).

Regression for dev run c0d27792 (2026-11-10): a 1-row contrasts.csv was given to
ml_training. The task raised `ValueError: cannot make 5 folds from 1 rows`, but the
work dir is on S3, so .command.err was never read; the verdict fell through to
"unknown — you can resume", and the snippet was the last 20 log lines (executor
shutdown noise), so the panel said "No error log captured".

The functions are lifted from the module source by AST so the test does not need
the full Galaxy stack (beaker, sqlalchemy, …).
"""
import ast
import json
import logging
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

_HERE = os.path.dirname(__file__)
_SRC = os.path.join(_HERE, "..", "..", "..", "..", "lib", "galaxy", "webapps", "galaxy", "api", "nextflow_executor.py")
_NEEDED = {
    "_INTERNAL_LINE_RE", "_REDACT_PATTERNS", "_redact_internal", "_S3_TASK_ERR_CACHE", "_collect_failed_task_errors_s3",
    "_TOOL_EXC_RE", "_tool_exception", "_classify_failure",
}


def _load() -> Dict[str, Any]:
    tree = ast.parse(open(_SRC).read())
    body = []
    for node in tree.body:
        name = getattr(node, "name", None)
        if name is None and isinstance(node, (ast.Assign, ast.AnnAssign)):
            tgt = node.targets[0] if isinstance(node, ast.Assign) else node.target
            name = getattr(tgt, "id", None)
        if name in _NEEDED:
            body.append(node)
    ns: Dict[str, Any] = {"re": re, "os": os, "Path": Path, "log": logging.getLogger("t"),
                          "Any": Any, "Dict": Dict, "List": List, "Optional": Optional, "Tuple": Tuple, "Union": Union}
    exec(compile(ast.Module(body=body, type_ignores=[]), _SRC, "exec"), ns)
    missing = _NEEDED - set(ns)
    assert not missing, missing
    return ns


NS = _load()
LOG_TAIL = json.load(open(os.path.join(_HERE, "fixtures", "batch_train_failed_log_tail.json")))
COMMAND_ERR = open(os.path.join(_HERE, "fixtures", "batch_train_failed_command.err")).read()


def test_orchestrator_log_only_is_tool_error_not_resume():
    v = NS["_classify_failure"]("failed", LOG_TAIL, 1)
    assert v["category"] == "tool_error"
    assert v["suggested_action"] == "check_input"
    assert v["error_detail"] == "cannot make 5 folds from 1 rows"
    # The excerpt ends at the exception, not in executor shutdown noise.
    assert v["task_error_snippet"].rstrip().endswith("ValueError: cannot make 5 folds from 1 rows")
    assert "Goodbye" not in v["task_error_snippet"]


def test_task_stderr_is_preferred_for_the_snippet():
    v = NS["_classify_failure"]("failed", LOG_TAIL, 1, task_stderr=COMMAND_ERR)
    assert v["category"] == "tool_error"
    assert "kfold_split" in v["task_error_snippet"]


def test_nextflow_wrapper_exception_is_not_a_tool_exception():
    exc = NS["_tool_exception"]("nextflow.exception.ProcessFailedException: Process `X` terminated with an error exit status (1)")
    assert exc is None


class _Body:
    def __init__(self, data: bytes):
        self._d = data

    def read(self):
        return self._d


class _FakeS3:
    """Two task dirs: one succeeded (exit 0, noisy stderr), one failed."""
    PREFIX = "nextflow/work/inv/run"

    def __init__(self):
        self.objects = {
            f"{self.PREFIX}/aa/111/.command.err": b"INFO progress line\n",
            f"{self.PREFIX}/aa/111/.exitcode": b"0",
            f"{self.PREFIX}/bd/222/.command.err": COMMAND_ERR.encode(),
            f"{self.PREFIX}/bd/222/.exitcode": b"1",
        }
        self.calls = 0

    def get_bucket_location(self, Bucket):
        return {"LocationConstraint": "us-west-2"}

    def get_paginator(self, _name):
        fake = self

        class _P:
            def paginate(self, Bucket, Prefix):
                fake.calls += 1
                yield {"Contents": [{"Key": k, "Size": len(v), "LastModified": i}
                                    for i, (k, v) in enumerate(fake.objects.items()) if k.startswith(Prefix)]}
        return _P()

    def get_object(self, Bucket, Key, Range=None):
        data = self.objects[Key]
        if Range:
            data = data[-int(Range.split("-")[-1]):]
        return {"Body": _Body(data)}


def test_s3_collector_reads_the_failed_task_and_caches(monkeypatch):
    import sys
    import types
    fake = _FakeS3()
    monkeypatch.setitem(sys.modules, "boto3", types.SimpleNamespace(client=lambda *a, **k: fake))
    NS["_S3_TASK_ERR_CACHE"].clear()
    uri = f"s3://bucket/{_FakeS3.PREFIX}"
    out = NS["_collect_failed_task_errors_s3"](uri)
    assert "ValueError: cannot make 5 folds from 1 rows" in out
    assert "INFO progress line" not in out  # the exit-0 task is not the failure
    assert NS["_collect_failed_task_errors_s3"](uri) == out
    assert fake.calls == 1  # terminal run → listed once


def test_s3_collector_rejects_non_s3():
    assert NS["_collect_failed_task_errors_s3"]("/tmp/x") == ""


def test_tool_exception_after_executor_prefix_is_found():
    line = ("Process FOLD_COMPLEX (fmc63) failed: Essential container in task exited — "
            "RuntimeError: DataLoader worker (pid(s) 2349) exited unexpectedly")
    exc = NS["_tool_exception"](line)
    assert exc and exc["type"] == "RuntimeError"
    assert exc["message"].startswith("DataLoader worker")
