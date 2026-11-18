"""
RunContext — the standardized substrate a Critic reads.

Built from the Phase-0 run contract that every workflow now publishes to its outdir:
  * ``design.json``            — inputs, scalar parameters, best-effort design fields
                                 (formula, covariates, group_sizes)
  * ``results_manifest.json``  — every produced output file with a coarse ``role``
                                 (table / figure / model / qc / metadata / …)

plus LAZY access to the run's published output artifacts (e.g. ``survival_qc.json``,
``cox_coefficients.csv``) through an injected ``artifact_loader``. The loader is the
ONLY I/O seam: on the AWS Batch / cloud completion path it reads from S3; in a unit
test it reads from a dict or a local directory. A critic therefore never knows (or
cares) whether a run executed locally or on Batch — it only sees the contract.

This module imports nothing from the rest of the framework, so it is safe to import
from ``base.py`` and cheap to construct on the hot completion path.
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

log = logging.getLogger(__name__)

# An artifact loader resolves an output file (by name OR s3_uri) to bytes/str, or None.
ArtifactLoader = Callable[[str], Optional[bytes]]


@dataclass
class OutputFile:
    """One entry from results_manifest.json's ``files`` list."""
    name: str
    s3_uri: str = ""
    role: str = "data"
    extension: str = ""
    size: Optional[int] = None

    @classmethod
    def from_manifest(cls, d: Dict[str, Any]) -> "OutputFile":
        return cls(
            name=str(d.get("name", "")),
            s3_uri=str(d.get("s3_uri", "")),
            role=str(d.get("role", "data")),
            extension=str(d.get("extension", "")),
            size=d.get("size"),
        )


@dataclass
class RunContext:
    """Everything a critic is allowed to see about a completed run.

    Construct via :meth:`from_contract` (production: from the executor's run_meta) or
    directly (tests). All output access goes through :meth:`load_artifact` /
    :meth:`load_json`, which use the injected ``artifact_loader``; the context itself
    does no network I/O at construction time.
    """
    run_id: str
    workflow: str = ""
    nextflow_path: str = ""
    workflow_domain: str = ""
    inputs: Dict[str, Any] = field(default_factory=dict)        # from design.json
    parameters: Dict[str, Any] = field(default_factory=dict)    # scalar knobs
    design: Dict[str, Any] = field(default_factory=dict)        # {formula,covariates,group_sizes}
    outputs: List[OutputFile] = field(default_factory=list)     # from results_manifest.json
    # Injected I/O seam. Given an artifact name or s3_uri, return its bytes (or None).
    artifact_loader: Optional[ArtifactLoader] = None
    # Optional inline artifacts (tests, or already-downloaded qc json). name -> bytes/str/dict.
    inline_artifacts: Dict[str, Any] = field(default_factory=dict)
    # Carry the raw manifests for transparency / downstream re-use.
    raw_design: Dict[str, Any] = field(default_factory=dict)
    raw_manifest: Dict[str, Any] = field(default_factory=dict)

    # ── construction ────────────────────────────────────────────────────────
    @classmethod
    def from_contract(
        cls,
        design: Optional[Dict[str, Any]],
        manifest: Optional[Dict[str, Any]],
        *,
        run_id: str = "",
        artifact_loader: Optional[ArtifactLoader] = None,
        inline_artifacts: Optional[Dict[str, Any]] = None,
    ) -> "RunContext":
        """Build a RunContext from the two contract documents.

        Both are the dicts the executor already computes
        (``_build_design_json`` / ``_build_results_manifest``). Either may be None;
        the context degrades gracefully (a critic's ``applies_to`` then fails closed).
        """
        design = design or {}
        manifest = manifest or {}
        design_block = design.get("design") or {}
        outputs = [OutputFile.from_manifest(f) for f in (manifest.get("files") or [])]
        return cls(
            run_id=run_id or str(manifest.get("run_id") or design.get("run_id") or ""),
            workflow=str(manifest.get("workflow") or design.get("workflow") or ""),
            nextflow_path=str(manifest.get("nextflow_path") or design.get("nextflow_path") or ""),
            workflow_domain=str(manifest.get("workflow_domain") or design.get("workflow_domain") or ""),
            inputs=dict(design.get("inputs") or {}),
            parameters=dict(design.get("parameters") or {}),
            design=dict(design_block),
            outputs=outputs,
            artifact_loader=artifact_loader,
            inline_artifacts=dict(inline_artifacts or {}),
            raw_design=design,
            raw_manifest=manifest,
        )

    # ── output discovery ──────────────────────────────────────────────────────
    def find_artifact(self, name: str) -> Optional[OutputFile]:
        """Return the manifest entry whose basename matches ``name`` (case-insensitive),
        or an inline artifact synthesized as an OutputFile. None if absent."""
        low = name.lower()
        for f in self.outputs:
            if f.name.lower() == low or f.name.lower().endswith("/" + low):
                return f
        if name in self.inline_artifacts:
            return OutputFile(name=name, role="qc" if name.endswith(".json") else "data")
        return None

    def outputs_by_role(self, role: str) -> List[OutputFile]:
        return [f for f in self.outputs if f.role == role]

    # ── artifact access (lazy I/O through the injected loader) ────────────────
    def load_artifact(self, name: str) -> Optional[bytes]:
        """Return the raw bytes of a published output by name, or None.

        Resolution order: inline_artifacts (tests / pre-downloaded) → artifact_loader
        keyed by s3_uri (from the manifest) → artifact_loader keyed by name.
        """
        if name in self.inline_artifacts:
            val = self.inline_artifacts[name]
            if isinstance(val, bytes):
                return val
            if isinstance(val, str):
                return val.encode("utf-8")
            # dict/list → serialize so load_json round-trips
            return json.dumps(val).encode("utf-8")
        entry = self.find_artifact(name)
        if self.artifact_loader is None:
            return None
        try:
            if entry is not None and entry.s3_uri:
                data = self.artifact_loader(entry.s3_uri)
                if data is not None:
                    return data
            return self.artifact_loader(name)
        except Exception as exc:  # loader must never crash a critic
            log.warning("[critics] artifact load failed for %s: %s", name, exc)
            return None

    def load_json(self, name: str) -> Optional[Any]:
        """Load a published JSON artifact and parse it; None on any failure."""
        if name in self.inline_artifacts and isinstance(self.inline_artifacts[name], (dict, list)):
            return self.inline_artifacts[name]
        raw = self.load_artifact(name)
        if raw is None:
            return None
        try:
            return json.loads(raw.decode("utf-8") if isinstance(raw, bytes) else raw)
        except Exception as exc:
            log.warning("[critics] JSON parse failed for %s: %s", name, exc)
            return None
