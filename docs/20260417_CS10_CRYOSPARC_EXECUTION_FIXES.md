# CS-10 CryoSPARC SPA Execution Fixes

**Date**: 2026-04-17  
**Branch**: integration/next-phase  
**Goal**: Make CS-10 E2E test pass — real CryoSPARC SPA workflow on GPU, polls to terminal, verifies .star/.mrc outputs, downloads, findings, methods report.

---

## Issues Found and How They Were Fixed

### Issue 1: `containerPath values aren't unique across mountPoints`

**Root cause**: `nextflow_executor.py` generated `biomate_executor_override.config` with both `cliPath = '/opt/aws-cli/bin/aws'` AND `volumes = ['/opt/aws-cli']` in the `aws.batch` block. Nextflow auto-mounts the parent directory of `cliPath` into the container, so the explicit `volumes` entry was a duplicate — AWS Batch rejected it.

**Fix** (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`):  
Removed the `volumes = ['/opt/aws-cli']` line from the override config generator. The `cliPath` auto-mount is sufficient.

---

### Issue 2: `INIT_CRYOSPARC_PROJECT` exits 0 but never writes `cs_init.json`

**Root cause**: `${CS_HELPER}` in `main.nf` expanded to a multiline Python string with 0-indent content. Nextflow's common-prefix stripping algorithm found a 0-space minimum (from the CS_HELPER lines), so none of the lines got stripped. This left the main script body at 4-space indent — appearing as dead code inside `submit_and_wait` (after `raise TimeoutError()`). The script ran to completion with exit 0 but never executed the actual logic.

**Fix** (`biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf`):  
Added 4-space indent to every line in `CS_HELPER`. After Nextflow strips the 4-space common prefix, all code lands at 0-indent in the generated `.command.sh`.

---

### Issue 3: `'CryoSPARC' object has no attribute 'create_project'`

**Root cause**: `cryosparc-tools` version in the container is v5.0.2, which removed the `create_project` top-level method. The API was restructured — projects are created via the REST API at port 30002 (uvicorn FastAPI), not via the Python library method.

Additionally, the base port 30000 (Node.js frontend) does NOT serve the OpenAPI spec that cryosparc-tools v5 requires for initialization.

**Port layout** (discovered by inspecting the EC2 directly):
| Port | Service |
|------|---------|
| 30000 | Node.js webapp (frontend) |
| 30001 | MongoDB |
| 30002 | uvicorn REST API (OpenAPI at `/openapi.json`) |
| 30003 | Python command server |
| 30004 | Redis |

**Fix**: Rewrote `CS_HELPER` entirely to use `httpx` directly (bundled with cryosparc-tools). Key behaviors:
- **Port auto-discovery**: tries `base_port` then `base_port + 2` — finds whichever port serves `/openapi.json`
- **Auth**: OAuth2 password flow via `POST /token` (password sha256-hashed)
- **Project creation**: `POST /projects/?title=...&parent_dir=...`
- **Workspace creation**: `POST /projects/{uid}/workspaces?title=...`
- **Job creation + enqueue**: `POST /projects/{p}/workspaces/{w}/jobs?type=...` (params as JSON body), then `POST /projects/{p}/jobs/{j}:enqueue`
- **Status polling**: `GET /projects/{p}/jobs/{j}/status`

This is version-independent — works regardless of cryosparc-tools version installed.

---

### Issue 4: S3 `movies_path` not usable by CryoSPARC

**Root cause**: CryoSPARC's `import_movies` job requires a local filesystem path on the CryoSPARC EC2 instance. The test query passes `s3://biomate-cryo-data/empiar-10028/...` which CryoSPARC cannot access.

**Fix** (`backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py`):  
Added `_stage_s3_movies_on_cryosparc()` — SSHes to CryoSPARC EC2, runs `aws s3 sync` with the glob pattern, returns the local path. Called automatically in `execute_cryosparc()` before building `nf_params`.

---

### Issue 5: CryoSPARC EC2 had no IAM/S3 access

**Root cause**: The CryoSPARC EC2 instance had no IAM instance profile → `aws s3 sync` failed with credentials error.

**Fix** (`backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py`):
- Added `_ensure_iam_profile(ec2, instance_id)` — idempotently attaches `CryoEMBenchmarkProfile` (which has `AmazonS3FullAccess`)
- Called in `start_instance()` after instance is running
- New AMI-launched instances also get `IamInstanceProfile={"Name": "CryoEMBenchmarkProfile"}` in the `run_instances()` call

---

## File Changes Summary

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Removed duplicate `volumes = ['/opt/aws-cli']`; added `_stage_s3_movies_on_cryosparc()`; modified `execute_cryosparc()` to stage S3 movies |
| `backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py` | Added `_ensure_iam_profile()`; modified `start_instance()` and `run_instances()` for IAM |
| `biomni_workflows/.../cryosparc_standard_spa/main.nf` | Fixed CS_HELPER indentation; rewrote CS_HELPER to use httpx directly (port auto-discovery, version-independent); updated INIT process body to use new API |
| `biomni_workflows/.../cryosparc_standard_spa/nextflow.config` | Fixed `cliPath` from `/usr/local/bin/aws` → `/opt/aws-cli/bin/aws` |

---

## Systemic Concerns for Other Workflows

The user raised that these issues are not unique to CS-10 — all BioMate workflows may have similar problems:

1. **Data locality**: Workflows that submit to GPU/specialized compute (CryoSPARC, Amber, GROMACS) may receive S3 paths but need local filesystem paths. The `_stage_s3_movies_on_cryosparc()` pattern should be generalized where needed.

2. **IAM access**: Any workflow that reads from S3 in a Batch container needs the correct IAM role. The `CryoEMBenchmarkProfile` pattern addresses this for CryoEM.

3. **Library API versions**: Containers may use newer library versions that break script logic (like cryosparc-tools v5). The httpx-direct approach bypasses this for CryoSPARC. Other workflows using Python library APIs should be audited similarly.

4. **cliPath**: All non-base containers need `/opt/aws-cli/bin/aws` to exist. The AMI bakes this in; `cliPath` in override config points to it correctly (after the volumes dedup fix).

**Next action**: After CS-10 passes, audit all other workflow main.nf files that use external service APIs (AlphaFold, Amber, Galaxy tools) for similar version-compatibility issues.

---

## Session 2 Fixes — LT v13 ECS Cold Start + CLI Robustness (2026-04-17)

### Issue 6: ECS Agent Cold Start — 15-min RUNNABLE delay

**Root cause**: On fresh EC2 instances from AMI `ami-08fe495be97a3dbf4`, the `systemctl start ecs` call in LT v11 user-data hangs for 15+ minutes because the ECS agent Docker image is not cached on the AMI. `systemctl` waits synchronously for the service to become active, which requires pulling the agent image from Docker Hub.

**Symptom**: Batch jobs sit in RUNNABLE state for 15+ minutes before any instance becomes available.

**Fix** (LT v13): Added `docker pull public.ecr.aws/ecs/amazon-ecs-agent:latest || docker pull amazon/amazon-ecs-agent:latest || true` before `systemctl start ecs`. Pre-pulling the image means ECS starts in seconds.

---

### Issue 7: Exit 127 — `/opt/aws-cli/bin/aws: No such file or directory` in container

**Root cause (hypothesis)**: Previous run `ebe75fa0` INIT job `d464a10f` ran on instance `i-09fb565c7ae695e16`. The instance was likely manually started during the ECS cold-start investigation (not via Batch LT). The `systemctl start ecs` in v11 was blocking during user-data, and the manual `amazon-ecs-init start` from an SSM session may have started ECS before user-data completed (race condition). The volume mount was correctly set in the Batch job definition, but either `/opt/aws-cli` was empty at that moment or the mount source path didn't yet exist.

**Fix** (LT v13): Added explicit `chmod +x /opt/aws-cli/bin/aws` and `aws --version` verification after the CLI check. The script exits with code 1 if the CLI fails to verify, which prevents ECS from starting with a broken CLI installation.

---

### LT v13 Summary

| Version | Changes |
|---------|---------|
| v11 | Stop ECS in bootcmd; install AWS CLI if missing; start ECS |
| v12 | v11 + pre-pull ECS agent Docker image |
| v13 | v12 + chmod+x on AWS CLI binary + verify `aws --version` before ECS start |

Both `biomate-nextflow-cpu-v1` and `biomate-nextflow-cpu-v2` updated to LT v13.

