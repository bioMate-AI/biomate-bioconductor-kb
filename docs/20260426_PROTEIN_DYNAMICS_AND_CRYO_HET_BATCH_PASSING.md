# Protein Dynamics + Cryo-EM Heterogeneity — AWS Batch End-to-End Pass

Date: 2026-04-26

## What Changed

### Cryo-EM Conformational Heterogeneity (cryoDRGN pipeline)

All four processes pass on AWS Batch (test9, completed in prior session):

| Process | Key Fix |
|---------|---------|
| CRYODRGN_TRAIN | — |
| CRYODRGN_ANALYZE | Removed fatal `umap.png` check (cryoDRGN 4.2 writes only `.ipynb`); replaced with volume-count validation |
| POCKET_SCAN_ENSEMBLE | Removed `volumes` glob output (name collision when kmeans2/ and kmeans20/ both produce vol_001.mrc); pass `analysis_dir` and glob inside Python |
| HETEROGENEITY_REPORT | — |

Additional fixes:
- **Trailing slash in `path("analyze.*/")`**: Java PathMatcher silently fails to match an existing directory when the glob has a trailing slash; removed slash
- **`<<-END_VERSIONS` heredoc**: `<<-` strips leading tabs only; Nextflow script uses spaces so `END_VERSIONS` is never recognized as terminator. Fixed: replaced all three heredocs with `python3 -c "print(...)" > versions.yml`
- **Python f-string vs Nextflow GString inside `<< 'PYEOF'`**: `f"... {analysis_dir}"` is a Python NameError; Nextflow resolves `${analysis_dir}` before bash runs, so use `f"... ${analysis_dir}"` (the `$` triggers Nextflow interpolation)
- **state_id path components**: `os.path.splitext(vol_path)[0]` produced a nested path as state_id (e.g., `analyze.5/kmeans2/vol_001`), making `pdb_path = os.path.join(tmpdir, f"{state_id}.pdb")` fail on mkdir. Fixed with `os.path.basename` on both dir and file

**Test9 final output:**
- 22 conformational states extracted
- 22/22 states have fpocket pockets
- Top state `kmeans2_vol_001` druggability score 1.0
- `heterogeneity_report.json` written to S3

Commits: e9908e9ae, 24f74903c, 40354da70, 9daed5a62

---

### Protein Dynamics Conformational Ensemble (BioEmu pipeline)

All three processes pass on AWS Batch (test8, 2026-04-26, 6m 21s):

| Process | Key Fix |
|---------|---------|
| BIOEMU_SAMPLE | FileNotFoundError fallback + MDAnalysis Gaussian sampling |
| POCKET_MINER | — |
| CONFORMATIONAL_SUMMARY | Remove triple-quoted Python docstrings |

#### Docker container rebuild (`protein-dynamics-nf:v1.0.3`)

- **Root cause of exit 127**: Previous `latest` image had broken AWS CLI install (step was CACHED in Docker BuildKit and skipped on rebuild); used `--no-cache` to force clean install
- **ECR cache on Batch GPU queue**: Even after push with same `latest` tag, GPU-queue nodes used cached old image. Fix: versioned tag `v1.0.3` forces fresh pull
- **BioEmu/PocketMiner**: GitHub access is blocked at build time; both clone with `|| echo WARNING` fallback in Dockerfile; install steps gracefully skip
- **BIOEMU_SAMPLE routed to CPU queue** (`biomate-nextflow-queue`) since MDAnalysis fallback does not need GPU

#### Process-level fixes

**1. `subprocess.run` raises `FileNotFoundError`, not returncode != 0**

When the binary does not exist, Python subprocess raises `FileNotFoundError` at the `Popen` call before ever returning a `CompletedProcess`. The original code had no `try/except` around `subprocess.run(["bioemu-sample", ...])`, so the exception crashed the script before any fallback code ran.

Fix: wrap in `try/except (FileNotFoundError, OSError)`.

**2. Python triple-quoted docstrings inside Nextflow script blocks**

Nextflow processes scripts as Groovy GStrings enclosed in `"""..."""`. A Python docstring like:
```python
def get_ca_coords(pdb_path):
    """Extract Ca coordinates from a PDB file using Biopython."""
```
causes Groovy to see the inner `"""` as the end of the script block, then parse `Extract` as a Groovy variable lookup, producing `No such variable: Extract` at compile time.

Fix: replace all triple-quoted docstrings with `#` comments inside Nextflow `""" ... """` blocks.

**3. `<<-END_VERSIONS` with space-indented scripts**

Same fix as cryo-het: `python3 -c "print(...)" > versions.yml`.

**Test8 final output:**
- 10 conformers generated (MDAnalysis Gaussian fallback, sigma=0.5 A)
- RMSD mean=1.08 A, std=0.37 A, Rg mean=21.8 A
- UMAP projection computed via umap-learn
- `summary_report.json` + `conformational_umap.png` written to S3
- fpocket ran on all 10 frames (0 pockets -- expected for 64-residue synthetic test PDB)

Commits: df223643a, afd2f273a, 9d381ae18, 7ccfc091a

---

## Nextflow + Docker Patterns Learned (Additions to Safety Checklist)

These extend the existing 13-item checklist documented in `feedback_nextflow_ode_patterns.md`:

14. **`subprocess.run` for optional tools**: catch `(FileNotFoundError, OSError)` separately from `returncode != 0`; the exception fires before `returncode` is set when the binary does not exist
15. **Python docstrings inside Nextflow scripts**: never use triple-quoted `"""` docstrings inside a Nextflow `""" ... """` script block; use `#` comments instead
16. **Trailing slash in `path("glob.*/")`**: Java PathMatcher fails to match a directory when the glob has a trailing slash; omit the slash
17. **ECR image cache on Batch**: `latest` tag is cached per-instance; use versioned tags (e.g., `v1.0.3`) to force fresh pull when updating a container
18. **Docker `--no-cache` vs cached layers**: BuildKit caches at layer level; a `CACHED` step in the build log may have stale content from a previous failed build; always use `--no-cache` when fixing a broken layer

---

## Known Open Issues

- **BioEmu not installed**: GitHub clone is blocked at Docker build time; the MDAnalysis Gaussian fallback (sigma=0.5 A) approximates thermal fluctuations but is not a learned generative model
- **PocketMiner not installed**: Same GitHub-access issue; fpocket geometry-based detection used as fallback
- **Pocket detection on synthetic test**: fpocket found 0 pockets on the 10 MDAnalysis-perturbed conformers because the test PDB (64-residue synthetic structure) lacks real hydrophobic cavities
- **GPU queue for BIOEMU_SAMPLE**: Temporarily routed to CPU queue; should revert to `galaxy-cloud-queue-gpu` once real BioEmu sampling is enabled

---

## Files Modified

| File | Purpose |
|------|---------|
| `cryo_heterogeneity/main.nf` | 4 process fixes: volume check, trailing slash, heredoc, state_id |
| `workflows/cryo_em_heterogeneity.nf` | Remove `volumes` emit, wire `analysis_dir` to POCKET_SCAN_ENSEMBLE |
| `test_data/test_cryo_heterogeneity.sh` | Add poses upload and `--poses` arg |
| `protein_dynamics/main.nf` | MDAnalysis fallback, docstring fix, heredoc fix, FileNotFoundError catch |
| `nextflow.config` | Route BIOEMU_SAMPLE to CPU queue |
| `docker/protein-dynamics-nf/Dockerfile` | Rebuilt --no-cache; container v1.0.3 in ECR |

---

## Test Outputs (S3)

| Pipeline | S3 Path |
|----------|---------|
| Cryo-EM het (test9) | `s3://biomate-nextflow-work/test-outputs/cryo-het/` |
| Protein dynamics (test8) | `s3://biomate-nextflow-work/test-outputs/protein-dynamics-test8/` |
