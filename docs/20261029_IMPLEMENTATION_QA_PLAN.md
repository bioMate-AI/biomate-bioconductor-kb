# Prepared implementation QA — 29 October 2026

Historical preparation plan. Execution is now complete: see `20261029_AWS_INTEGRATION_QA_EXECUTION.md` for the approved retry, 215 passing tests and verified termination. At preparation time, no instance had been provisioned and no new spend was authorised. Earlier stage-0/1 spend is unreconciled and no currently running worker is available. An explicit budget reservation and approved launch wrapper are required before execution. No dollar estimate is asserted without a fresh regional Spot-price and ancillary-cost check.

## CPU validation package

Use a dedicated EC2 Spot c6i.xlarge in the approved region, Python 3.11 and a 20-minute runner timeout. The wrapper must additionally set an independent instance shutdown deadline, upload logs continuously, preserve failure status and terminate on success/failure. Installation time counts within the runner timeout. A timeout or installation failure is not a test failure or pass; inspect the recorded phase.

Runner: `research/guangzhou_all_atom/cyclic_llm/allatom_paper/hybrid/ec2/qa_integration.sh`.

The runner refuses non-Spot/non-EC2 execution through IMDSv2 before any Python invocation. It creates an isolated virtual environment and records dependency installation, `pip freeze`, `pip check`, versions, pytest output, JUnit results and exit status. The proposed environment pins Torch 2.6.0 CPU, Transformers 4.51.3, PEFT 0.15.2, Accelerate 1.6.0, NumPy 2.2.6, SciPy 1.15.3, RDKit 2025.3.2 and pytest 8.3.5. These candidate versions have not been resolver-tested here; preserve the full resulting transitive lock and revise only against observed failures. No model download is needed; Hugging Face network access is disabled during tests.

Upload the listed evidence files, excluding the output directory's `venv/` subtree. The virtual environment is disposable execution infrastructure, not an audit artifact.

The previous `/tmp/method-qa-ssm-v5.json` used the existing worker's `/w/venv` Torch plus separately installed NumPy/SciPy/RDKit/pytest. Its 50 passing tests did not require the new Transformers/PEFT synthetic adapter-merging fixture. That existing environment is not assumed available for a fresh instance.

Bundle the `cyclic_llm` source tree with its directory layout preserved, including `allatom_paper`, predecessor `ihlm` modules imported by package initialisers, and any referenced source-only support modules. Use an explicit reviewed source manifest; exclude model weights, raw corpora, credentials, Git history and macOS sidecars. Record SHA-256 for the archive and each included file. Do not upload this private QA bundle to the public benchmark repository.

After approval and staging, the wrapper runs (paths are illustrative remote destinations):

```bash
bash /w/code/cyclic_llm/allatom_paper/hybrid/ec2/qa_integration.sh \
  /w/code/cyclic_llm /w/out/integration-qa
```

The runner executes all current `hybrid/` tests plus orchestrator, budget harness, retrieval, preference-updater and stopping-monitor regressions. The new tiny Llama/PEFT fixture is randomly initialised synthetic software validation: it checks adaptation merge, frozen-reference equivalence and fresh trainable LoRA separation. It does not train a scientific model. Acceptance requires positive test count and zero failures, errors or skips. `done.flag` alone is insufficient; inspect the command exit, JUnit summary and dependency report.

## Separate GPU acceptance

CPU success permits review of a separately budgeted GPU diagnostic; it does not authorise provisioning or establish M1. Use an already approved Spot GPU allocation only after checkpoint, corpus/evidence and run configuration are frozen. The diagnostic must check genuine ChemFM loaded identity, finite nonzero adapter updates, accepted-completion yield, policy/reference likelihood agreement, knowledge-use traces and full checkpoint restore. A bare pretrained smoke and an adapted smoke are distinct configurations.

`hybrid.verify_restore` now accepts `--adaptation-dir`, `--initialization-manifest` and `--initialization-manifest-sha256`, matching the generator's verified adaptation hand-off. Its checkpoint must contain the identical `initialization_identity`. The manifest binds base config/tokenizer/weights and adaptation config/weights; changing any bound file or the chosen reference rejects restore. This diagnostic compares restored state only, not an uninterrupted-versus-resumed trajectory. It remains separate from an M1 certificate.

No outcome table, scientific claim, knowledge-benefit estimate or completed-training claim can be filled from the prepared runner or synthetic fixture results alone.

## Concrete launch prepared after source review

A source-only snapshot and a launch request are prepared at `/tmp/method-integration-qa-20261029.tar.gz` and `/tmp/method-integration-qa-launch-r2/launch.json`. Current archive SHA-256: `5b05d2897a86f493d6015c1cb9b63a4623f937572b2c666a6003eefcfe82dc25`; source-manifest SHA-256: `57a5b836b49caf2e3cb2880b0ca0e1e16345d1f9dea47a1e34b1b14df262e4c1`. The 67-file archive is synthetic-test source only, not a complete scientific-run bundle. Rebuild and change the pinned archive hash if any test dependency changes.

`hybrid/ec2/prepare_qa_launch.py` prepares, but does not launch, one c6i.xlarge Spot worker using the existing project AL2023 AMI, IAM profile and security group in us-west-2d. It requests a 40-GB encrypted gp3 root volume deleted on termination, requires IMDSv2, caps the Spot compute bid at USD 0.10/hour, schedules shutdown 25 minutes after bootstrap starts, uploads logs and shuts down after success or failure. The operator must independently terminate a worker that has not stopped within 30 minutes of launch. The application timeout remains 20 minutes including dependency installation. No model weights are downloaded for this CPU fixture suite.

Read-only AWS checks on 29 October confirmed the AMI and subnet available. Observed c6i.xlarge Spot quotes were USD 0.0716–0.0838/hour across the four regional AZs. At the bid ceiling, 30 minutes has a compute envelope of USD 0.05, excluding boot extension, storage, IPv4, S3 and other charges. An additional USD 1 total CPU-QA allowance was requested because the previous USD 14 study allowance has no certified remaining headroom. The user subsequently approved this USD 1 request with “go”; execution and termination are documented in `20261029_AWS_INTEGRATION_QA_EXECUTION.md`. This allowance would not authorise GPU training, stage 2 or additional extraction.

## Literature and patent repair suites included

The r2 source package adds K2 semantic-review contracts and K4 sequence-repair regressions. Each package runs in a separate pytest process because both use top-level legacy module names. Acceptance requires positive test counts and zero failures, errors or skips in each of the three JUnit reports. Tests use synthetic records only: this CPU allowance does not authorise reprocessing the patent corpus or new extraction. The r1 launch specification is superseded and must not be used with the rebuilt archive. The r2 attempt failed during dependency installation; the repaired r3 package passed all remote suites. See the execution note for its new hashes and retained evidence.
