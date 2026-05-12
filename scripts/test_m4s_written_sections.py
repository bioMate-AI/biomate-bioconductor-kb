"""
Smoke test for ICH M4S(R2) §2.6.2, §2.6.4, §2.6.6 written-summary builders.

When the v6 adapter is not loaded, builders emit [NO DATA AVAILABLE] for every
subsection — structurally still passes the validator. Verifies that the
required-subsection headings are present and in order regardless of content
availability.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.ind_assembly import (
    section_262_pharmacology_written,
    section_264_pk_written,
    section_266_tox_written,
)
from galaxy.ai.drug_discovery.structural_validator import validate_structure


def main():
    for section_id, builder in [
        ("2.6.2", section_262_pharmacology_written),
        ("2.6.4", section_264_pk_written),
        ("2.6.6", section_266_tox_written),
    ]:
        text = builder("test-compound")
        r = validate_structure(text, section_id)
        print(f"§{section_id}: passed={r.passed} found={len(r.found_headings)} "
              f"missing={r.missing} order_violations={r.out_of_order}")
        if not r.passed:
            print("--- output excerpt ---")
            print(text[:600])
            print("...")
            sys.exit(1)
    print("\nAll three M4S(R2) written-summary builders pass structural validation.")


if __name__ == "__main__":
    main()
