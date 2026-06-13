"""Thin CLI over regulatory_training_jobs — JSON on stdout, designed for
Node-side `execFile` shellout from regulatory-training-routes.ts.
"""
from __future__ import annotations
import json, sys
from galaxy.ai.drug_discovery import regulatory_training_jobs as rj


def _err(msg: str) -> int:
    print(json.dumps({"error": msg}), file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return _err("verb required: submit|list|get|count_pairs|mark|tick")
    verb = argv[1]
    try:
        if verb == "submit":
            print(json.dumps(rj.submit(user_id=argv[2], org_id=argv[3]).to_dict()))
        elif verb == "list":
            print(json.dumps([j.to_dict() for j in rj.list_for_user(argv[2])]))
        elif verb == "get":
            j = rj.get(argv[2])
            print(json.dumps(j.to_dict() if j else None))
        elif verb == "count_pairs":
            print(json.dumps({"count": rj.count_edit_pairs(argv[2])}))
        elif verb == "mark":
            if len(argv) < 4:
                return _err("usage: mark <job_id> <status> [message] [adapter_path]")
            msg = argv[4] if len(argv) > 4 else ""
            adapter = argv[5] if len(argv) > 5 else ""
            j = rj.mark_status(argv[2], argv[3], message=msg, adapter_path=adapter)
            print(json.dumps(j.to_dict() if j else None))
        elif verb == "tick":
            from galaxy.ai.drug_discovery.regulatory_training_worker import tick
            max_jobs = int(argv[2]) if len(argv) > 2 else 1
            done = tick(max_jobs=max_jobs)
            print(json.dumps([j.to_dict() for j in done]))
        else:
            return _err(f"unknown verb: {verb}")
        return 0
    except ValueError as e:
        return _err(str(e))
    except Exception as e:
        return _err(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
