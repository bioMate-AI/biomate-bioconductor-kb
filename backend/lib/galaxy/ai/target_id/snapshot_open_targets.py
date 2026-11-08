"""Build offline Open Targets snapshots for deployments without internet access.

Run once on a machine that can reach the internet, then copy the folder to the deployment and point
TARGET_ID_SNAPSHOT_DIR at it (with TARGET_ID_OFFLINE=1). Each snapshot records its date, and every result served
from one is labelled "snapshot" with that date.

  PYTHONPATH=backend/lib python3 -m galaxy.ai.target_id.snapshot_open_targets --out ./ot_snapshots MONDO_0005105 EFO_0000685
"""
import argparse
import sys

from .data_channels import write_ot_snapshot


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("disease_ids", nargs="+", help="EFO / MONDO disease identifiers")
    ap.add_argument("--out", required=True, help="output folder")
    ap.add_argument("--size", type=int, default=500, help="top associated targets to keep per disease (default 500)")
    a = ap.parse_args(argv)
    failed = 0
    for efo in a.disease_ids:
        try:
            print("%s -> %s" % (efo, write_ot_snapshot(efo, a.out, size=a.size)))
        except Exception as e:
            failed += 1
            sys.stderr.write("ERROR %s: %s: %s\n" % (efo, type(e).__name__, e))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
