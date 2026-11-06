#!/usr/bin/env python3
"""Run a real CPU FastQC process. This does not prove Galaxy workflow execution."""
import argparse
import json
import subprocess
import tempfile
import time
from pathlib import Path
from verify_fastqc import verify


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    report = {'passed': False, 'scope': 'Real FastQC CPU process, not Galaxy or LLM orchestration'}
    try:
        # A new directory prevents stale artifacts from satisfying a failed rerun.
        run = Path(tempfile.mkdtemp(prefix='run-', dir=args.output))
        reads = run / 'synthetic.fastq'
        reads.write_text(''.join(f'@trial_{i}\n' + 'ACGT'*25 + '\n+\n' + 'I'*100 + '\n' for i in range(100)))
        report['version'] = subprocess.check_output(['fastqc', '--version'], text=True, timeout=30).strip()
        completed = subprocess.run(['fastqc', '--format', 'fastq', '--threads', '1', '--outdir', str(run), str(reads)], capture_output=True, text=True, timeout=300)
        (run / 'process.log').write_text(completed.stdout + completed.stderr)
        report['exit_code'] = completed.returncode
        completed.check_returncode()
        report['artifacts'] = verify(run / 'synthetic_fastqc.html', run / 'synthetic_fastqc.zip')
        report['artifact_directory'] = str(run)
        report['passed'] = True
    except Exception as exc:
        report['error'] = str(exc)
    report['seconds'] = round(time.monotonic() - start, 3)
    tmp = args.output / 'result.tmp'
    tmp.write_text(json.dumps(report, indent=2))
    tmp.replace(args.output / 'result.json')
    print(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
