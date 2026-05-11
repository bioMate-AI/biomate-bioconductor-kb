"""Verify task5 + task6 generated examples meet v2 checklist standards."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.mrsd_verifier import verify_mrsd
from galaxy.ai.drug_discovery.phase_gating import required_studies, verify_phase_gating
from galaxy.ai.drug_discovery.structural_validator import validate_structure
from galaxy.ai.drug_discovery.tabulated_summary import verify_table


def assistant(row): return row["messages"][-1]["content"]


def main():
    task5 = ROOT / "data/regulatory_training/tasks/task5_mrsd_computation.jsonl"
    task6 = ROOT / "data/regulatory_training/tasks/task6_skeleton_completion.jsonl"

    rows5 = [json.loads(l) for l in task5.open()]
    grounded = passed = 0
    for r in rows5:
        f = verify_mrsd(assistant(r))
        if f.grounded:
            grounded += 1
            if f.passed:
                passed += 1
    print(f"task5 (MRSD): grounded {grounded}/{len(rows5)} ({100*grounded/len(rows5):.0f}%), "
          f"passed {passed}/{grounded} ({100*passed/max(grounded,1):.0f}%)")

    rows6 = [json.loads(l) for l in task6.open()]
    pass_count = 0
    for r in rows6:
        sec = r["meta"]["section_id"]
        if validate_structure(assistant(r), sec).passed:
            pass_count += 1
    print(f"task6 (skeleton): passed {pass_count}/{len(rows6)} ({100*pass_count/len(rows6):.0f}%)")

    task8 = ROOT / "data/regulatory_training/tasks/task8_tabulated_summary.jsonl"
    if task8.exists():
        rows8 = [json.loads(l) for l in task8.open()]
        pass_count = 0
        for r in rows8:
            tid = r["meta"]["template_id"]
            if verify_table(assistant(r), tid).passed:
                pass_count += 1
        print(f"task8 (tabulated):    passed {pass_count}/{len(rows8)} "
              f"({100*pass_count/len(rows8):.0f}%)")

    task7 = ROOT / "data/regulatory_training/tasks/task7_phase_gating.jsonl"
    if task7.exists():
        rows7 = [json.loads(l) for l in task7.open()]
        pass_count = 0
        for r in rows7:
            req = required_studies(
                r["meta"]["phase"], r["meta"]["trial_duration_days"],
                r["meta"]["population"],
            )
            if verify_phase_gating(assistant(r), req).passed:
                pass_count += 1
        print(f"task7 (phase-gating): passed {pass_count}/{len(rows7)} "
              f"({100*pass_count/len(rows7):.0f}%)")


if __name__ == "__main__":
    main()
