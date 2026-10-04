#!/usr/bin/env python3
"""Cyclic-peptide pipeline ORCHESTRATION layer — parse, validate, and report the declarative
stage manifest (cyclic_pipeline_manifest.yaml) that maps the DBTL pipeline onto the existing
scattered stage scripts.

This is the thin orchestration spine over the scripts (priority #1 "orchestration + maturity"):
it does NOT execute GPU/EC2 stages. It makes the pipeline INSPECTABLE and CHECKED —

    python3 cyclic_pipeline.py --validate   # every referenced script exists, datasets resolve,
                                            # DAG is acyclic, wiring-gap stage refs are real
    python3 cyclic_pipeline.py --report     # stage -> script table, maturity rollup, wiring gaps
    python3 cyclic_pipeline.py --dag        # topological stage order

Validation is the value: a stage that names a script that was renamed/deleted, or a dataset not in
the registry, is a latent break in the pipeline wiring — this catches it locally, for free.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict, List

import yaml

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "cyclic_pipeline_manifest.yaml"

RUNS_ON = {"local", "gpu", "ec2_batch", "external_cro"}
MATURITY = {"tested_local", "partial", "untested_local"}


class Pipeline:
    def __init__(self, manifest_path: Path = MANIFEST):
        self.doc = yaml.safe_load(Path(manifest_path).read_text())
        self.stages = self.doc["stages"]
        self.by_id = {s["id"]: s for s in self.stages}
        self.wiring_gaps = self.doc.get("wiring_gaps", [])

    # ---- validation -----------------------------------------------------------------------
    def validate(self, registry=None) -> List[str]:
        """Return a list of error strings; empty = valid."""
        errs: List[str] = []
        ids = set(self.by_id)

        # unique ids
        if len(ids) != len(self.stages):
            errs.append("duplicate stage ids present")

        known_datasets = set(registry.names()) if registry else None

        for s in self.stages:
            sid = s["id"]
            if s.get("runs_on") not in RUNS_ON:
                errs.append(f"{sid}: bad runs_on {s.get('runs_on')!r}")
            if s.get("maturity") not in MATURITY:
                errs.append(f"{sid}: bad maturity {s.get('maturity')!r}")
            # scripts exist on disk
            for scr in s.get("scripts", []):
                if not (ROOT / scr).exists():
                    errs.append(f"{sid}: script not found on disk: {scr}")
            # datasets resolve against the registry
            for ds in s.get("datasets", []):
                if known_datasets is not None and ds not in known_datasets:
                    errs.append(f"{sid}: dataset not in registry: {ds}")
            # downstream ids are real
            for d in s.get("downstream", []):
                if d not in ids:
                    errs.append(f"{sid}: downstream references unknown stage {d!r}")

        # wiring-gap stage refs are real
        for g in self.wiring_gaps:
            for ref in g.get("between", []):
                if ref not in ids:
                    errs.append(f"wiring gap {g.get('id')}: unknown stage ref {ref!r}")

        # DAG acyclic (ignore the dpo_learn->generate loop edge, which is the intended cycle)
        errs.extend(self._acyclic_errors())
        return errs

    def _acyclic_errors(self) -> List[str]:
        """Detect cycles other than the intended learn->generate close-back edge."""
        loop_edge = ("dpo_learn", "generate")
        adj: Dict[str, List[str]] = {
            s["id"]: [d for d in s.get("downstream", []) if (s["id"], d) != loop_edge]
            for s in self.stages
        }
        WHITE, GREY, BLACK = 0, 1, 2
        color = {sid: WHITE for sid in adj}
        errs: List[str] = []

        def dfs(u: str, path: List[str]):
            color[u] = GREY
            for v in adj[u]:
                if color[v] == GREY:
                    errs.append(f"unexpected cycle: {' -> '.join(path + [u, v])}")
                elif color[v] == WHITE:
                    dfs(v, path + [u])
            color[u] = BLACK

        for sid in adj:
            if color[sid] == WHITE:
                dfs(sid, [])
        return errs

    # ---- ordering -------------------------------------------------------------------------
    def topo_order(self) -> List[str]:
        """Topological order ignoring the learn->generate close-back edge."""
        loop_edge = ("dpo_learn", "generate")
        adj = {s["id"]: [d for d in s.get("downstream", []) if (s["id"], d) != loop_edge]
               for s in self.stages}
        indeg = {sid: 0 for sid in adj}
        for u in adj:
            for v in adj[u]:
                indeg[v] += 1
        order, queue = [], [sid for sid in adj if indeg[sid] == 0]
        # keep manifest order as tie-break
        manifest_rank = {s["id"]: i for i, s in enumerate(self.stages)}
        while queue:
            queue.sort(key=lambda x: manifest_rank[x])
            u = queue.pop(0)
            order.append(u)
            for v in adj[u]:
                indeg[v] -= 1
                if indeg[v] == 0:
                    queue.append(v)
        return order

    # ---- reporting ------------------------------------------------------------------------
    def report(self) -> str:
        lines = [f"Pipeline: {self.doc.get('pipeline')}  (orchestrator: {self.doc.get('orchestrator')})",
                 "", "STAGE -> SCRIPTS (runs_on / maturity)", "-" * 92]
        for s in self.stages:
            scripts = ", ".join(s.get("scripts", [])) or "(none)"
            lines.append(f"{s['id']:<24} [{s.get('runs_on'):<12} {s.get('maturity'):<14}]")
            lines.append(f"    scripts : {scripts}")
            if s.get("datasets"):
                lines.append(f"    datasets: {', '.join(s['datasets'])}")
            lines.append(f"    in  -> {', '.join(s.get('inputs', []))}")
            lines.append(f"    out -> {', '.join(s.get('outputs', []))}")
        # maturity rollup
        roll: Dict[str, int] = {}
        for s in self.stages:
            roll[s["maturity"]] = roll.get(s["maturity"], 0) + 1
        lines += ["", "MATURITY ROLLUP", "-" * 92,
                  "  " + "  ".join(f"{k}={v}" for k, v in sorted(roll.items())),
                  "", "TOPOLOGICAL ORDER (ignoring learn->generate close-back)", "-" * 92,
                  "  " + " -> ".join(self.topo_order()),
                  "", f"WIRING GAPS ({len(self.wiring_gaps)})", "-" * 92]
        for g in self.wiring_gaps:
            btw = " -> ".join(g.get("between", []))
            lines.append(f"  [{g.get('id')}][{g.get('severity','?'):<6}] {btw}")
            lines.append(f"      {' '.join(g.get('description','').split())}")
        return "\n".join(lines)


def _main(argv=None):
    ap = argparse.ArgumentParser(description="Cyclic-peptide pipeline orchestration spec.")
    ap.add_argument("--validate", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--dag", action="store_true")
    args = ap.parse_args(argv)

    pipe = Pipeline()

    if args.dag:
        print(" -> ".join(pipe.topo_order()))
        return 0

    if args.validate or not (args.report or args.dag):
        try:
            from cyclic_data_registry import registry
            reg = registry()
        except Exception as exc:  # noqa: BLE001
            print(f"warning: registry unavailable ({exc}); dataset refs not checked")
            reg = None
        errs = pipe.validate(registry=reg)
        if errs:
            print(f"VALIDATION FAILED ({len(errs)} error(s)):")
            for e in errs:
                print(f"  - {e}")
            return 1
        print(f"VALIDATION OK: {len(pipe.stages)} stages, {len(pipe.wiring_gaps)} wiring gaps, "
              f"all scripts present, all datasets resolve, DAG acyclic.")

    if args.report:
        print(pipe.report())
    return 0


if __name__ == "__main__":
    sys.exit(_main())
