# Real SRA Execution + E2E Hardening (2026-04-07)

## Summary

Two parallel threads of work completed this session:

1. **Germline E2E suite confirmed 7/7 passing** — fixes from the previous context window
   verified on a clean run with the frontend server up.
2. **Real SRA execution wired end-to-end** — `fasterq-dump` packaged into ECR, the
   `wgs_germline_gatk` pipeline extended with an SRA download step, and GC-2 updated
   to run a real pipeline (not mock) with actual output-file assertions.

---

## Part 1 — Germline E2E 7/7 PASS

### Root cause of prior failures

| Test | Failure mode | Fix |
|------|-------------|-----|
| GC-7 Turn 1 | `classifyWithLLM` returned false for short workflow-card title | DOM check: `waitForWorkflowCard(preTurn1Count)` + `hasAssistantResponse` (>40 chars) |
| GC-7 Turn 3 | Haiku returned false for "references germline?" when text said "Sarek uses GRCh38" | Keyword regex `/sarek\|germline\|GATK\|hg38.../i` |
| GC-2 run button | `reference`/`known_sites` had `null` defaults → `hasUnfilledRequired=true` | `_inject_genome_into_params()` fills igenomes S3 paths when genome build detected |
| GC-5 `askedForDataAgain` | LLM saw only card title (short text) → returned `true` | If workflow card present → `askedForDataAgain = false` directly |

### Infrastructure note

The frontend server (`USE_POLLING=true npx tsx server/index.ts`) must be running before
the suite starts. GC-7 fails with `ERR_CONNECTION_REFUSED` when the server is down.

### Final result

```
7 passed (7.5m)
```

Session doc: `docs/nextPhase/20260407_GERMLINE_E2E_GC7_FIX_REPORT.md`

---

## Part 2 — Real SRA Execution

### Problem

GC-2 used `SRR1518169` as the reads input, but the pipeline had no SRA download step.
`Channel.fromFilePairs("SRR1518169")` immediately fails — it's not a file glob, it's an
NCBI accession. `fasterq-dump` was not installed on the host or in any Docker image.
Result: pipeline always `failed`, `output_files` returned 0 files, test passed only
because the API itself returned HTTP 200 (not because any real work happened.

### Solution

#### 1. ECR image: `biomate/sra-tools:3.1.1`

Built `sratoolkit.3.1.1-ubuntu64` (AMD64, for AWS Batch) on the ARM host using
`docker buildx --platform linux/amd64`. Pushed two tags:

```
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/sra-tools:3.1.1
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/sra-tools:latest
```

Verified: `docker run --platform linux/amd64 biomate/sra-tools:3.1.1 --version`
→ `fasterq-dump : 3.1.1`

Dockerfile at `/tmp/sra-tools-docker/Dockerfile`.

#### 2. Pipeline: `wgs_germline_gatk/main.nf`

Added `FASTERQ_DUMP` process and SRA-vs-glob branching in the workflow entry point.

**New process** (before `FASTQC`):

```nextflow
process FASTERQ_DUMP {
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/sra-tools:3.1.1'
    cpus   { [4, params.max_cpus as int].min() }
    memory '8 GB'
    time   '6 h'

    input:  val accession
    output: tuple val(accession), path("${accession}_1.fastq.gz"),
                                  path("${accession}_2.fastq.gz"), emit: reads

    script:
    def spotLimit = (params.max_spots as int) > 0 ? "-X ${params.max_spots}" : ""
    """
    fasterq-dump ${accession} --threads ${task.cpus} --split-files --outdir . --temp . ${spotLimit}
    pigz -p ${task.cpus} ${accession}_1.fastq ${accession}_2.fastq
    """
}
```

**Workflow branching**:

```nextflow
def isSRA = (params.reads ==~ /^[SED]RR\d+$/)
if (isSRA) {
    sra_out  = FASTERQ_DUMP(Channel.of(params.reads))
    reads_ch = sra_out.reads.map { acc, r1, r2 -> tuple(acc, [r1, r2]) }
} else {
    reads_ch = Channel.fromFilePairs(params.reads, checkIfExists: true)
        .ifEmpty { error "No reads found matching pattern: ${params.reads}" }
}
```

**New param**:

```nextflow
params.max_spots = 0   // 0 = unlimited; set e.g. 500000 for quicker test runs
```

#### 3. AI backend: `ai_assistant.py`

Added two helpers called from `_return_nextflow_match` (and both composed-workflow paths):

```python
_MAX_SPOTS_RE = re.compile(r'\bmax_spots\s*[=:]\s*(\d+)', re.IGNORECASE)

def _extract_max_spots(self, user_intent: str) -> Optional[int]:
    m = self._MAX_SPOTS_RE.search(user_intent)
    return int(m.group(1)) if m else None

def _inject_max_spots_into_params(self, opt_params: list, max_spots: int) -> list:
    for p in opt_params:
        if p['name'] == 'max_spots':
            return [{**p, 'default': max_spots} if p['name'] == 'max_spots' else p
                    for p in opt_params]
    return list(opt_params) + [{
        'name': 'max_spots', 'default': max_spots, 'required': False,
        'description': 'Limit SRA spots downloaded (0 = unlimited)',
    }]
```

When the user message contains `max_spots=N` (e.g. `max_spots=500000`), the value is
injected into optional params and passed through to Nextflow as `--max_spots N`.

#### 4. E2E test: GC-2 updated

| Change | Before | After |
|--------|--------|-------|
| Test description | "mock query" | "real SRA download (SRR1518169, 500k spots)" |
| `test.setTimeout` | 600 000 ms (10 min) | 9 000 000 ms (2.5 hr) |
| `pollToTerminal` timeout | 540 000 ms (9 min) | 7 200 000 ms (2 hr) |
| Query | plain germline request | + `Use max_spots=500000 to limit the SRA download` |
| Output assertion | soft warn if 0 files | `expect(files.length).toBeGreaterThan(0)` + VCF present |

With `max_spots=500000` (~500k paired reads, ~1 GB of WGS data), expected runtime:
- fasterq-dump: ~5 min
- BWA-MEM2 alignment: ~20 min
- GATK BQSR + HaplotypeCaller: ~30 min
- **Total: ~1 hour on AWS Batch**

For a full-resolution clinical run (SRR1518169, all 30 GB): remove `max_spots` from the
query; the pipeline runs unlimited but takes 6–8 hours.

---

## Files Changed

| File | Change |
|------|--------|
| `/tmp/sra-tools-docker/Dockerfile` | New — SRA toolkit 3.1.1 AMD64 image |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/main.nf` | Added `FASTERQ_DUMP` process, SRA detection, `max_spots` param |
| `backend/lib/galaxy/ai/ai_assistant.py` | `_extract_max_spots`, `_inject_max_spots_into_params`, call site in `_return_nextflow_match` |
| `frontend/e2e/germline-complete-e2e.e2e.ts` | GC-2: timeouts, query, output-file assertions |
| `frontend/e2e/germline-complete-e2e.e2e.ts` | GC-5, GC-7: DOM-based checks replacing LLM classifier |

---

## ECR Image Registry

| Repository | Tag | Digest |
|-----------|-----|--------|
| `biomate/sra-tools` | `3.1.1` | `sha256:10544705f5436bd5d38e29198215fcf48fc1e5333be112795c3d22bb3ecc0318` |
| `biomate/sra-tools` | `latest` | same |

---

## Open Items

- GC-2 has not yet been run with the real SRA pipeline (requires AWS Batch resources and
  ~1 hour). Run when a Batch environment is available.
- The `wgs_germline_gatk` processes (BWA, GATK, etc.) have no `container` directives —
  they depend on the default Batch container (`biomate-nextflow-base`) having the tools
  installed. Verify that `biomate-nextflow-base` contains `bwa-mem2`, `gatk4`, `samtools`,
  `mosdepth`, `fastp`, `multiqc`. If not, add per-process container directives.
