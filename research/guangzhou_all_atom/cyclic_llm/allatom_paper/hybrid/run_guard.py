"""Persist one run identity and an absolute deadline across process restarts."""
import json
import math
from pathlib import Path
import time


def bind_run(root, identity, max_seconds, now=None):
    now = time.time() if now is None else now
    if not math.isfinite(max_seconds) or max_seconds <= 0 or not math.isfinite(now):
        raise ValueError('finite positive deadline required')
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    path = root / 'run_identity.json'
    if not path.exists():
        if (root / 'checkpoint' / 'ckpt.json').exists():
            raise ValueError('legacy checkpoint has no frozen run identity/deadline')
        record = dict(identity=identity, started_unix=now, deadline_unix=now + max_seconds)
        # Exclusive creation: concurrent first writers cannot overwrite identity.
        with path.open('x') as stream:
            json.dump(record, stream, indent=2, allow_nan=False)
    else:
        record = json.loads(path.read_text())
    if record['identity'] != identity:
        raise ValueError('run identity differs; refuse checkpoint reuse')
    start, deadline = record['started_unix'], record['deadline_unix']
    if not all(isinstance(x, (int, float)) and math.isfinite(x) for x in (start, deadline)):
        raise ValueError('invalid persisted deadline')
    if deadline - start != max_seconds:
        raise ValueError('persisted duration differs')
    if now < start or now >= deadline:
        raise ValueError('run deadline exhausted or wall clock moved backwards')
    return record


def remaining_seconds(record, now=None):
    now = time.time() if now is None else now
    remaining = record['deadline_unix'] - now
    if not math.isfinite(now) or now < record['started_unix'] or remaining <= 0:
        raise ValueError('run deadline exhausted or wall clock moved backwards')
    return remaining
