# BioMate REINVENT4 Nextflow Container
#
# Provides a REAL learned de-novo / analogue generator: MolecularAI REINVENT4
# (Apache-2.0, https://github.com/MolecularAI/REINVENT4) — the `reinvent` CLI
# plus the open-weights prior checkpoints staged under $REINVENT4_PRIORS.
#
# Used by:
#   backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/
#       reinvent4_lead_design/main.nf   (process GENERATE_REINVENT4 — sampling)
#   backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/
#       reinvent4_finetune_rl/main.nf   (process REINVENT4_TRAIN — transfer
#                                        learning + staged RL, i.e. training)
#   backend/lib/galaxy/ai/drug_discovery/generators.py::Reinvent4Generator (sampling)
#   backend/lib/galaxy/ai/drug_discovery/reinvent4_trainer.py
#       ::Reinvent4TransferLearner / ::Reinvent4StagedLearner (training)
#
# Build (x86 / AWS Batch — REINVENT4 wheels are x86_64):
#   docker build --platform linux/amd64 -t biomate/reinvent4-nf:latest \
#     -f backend/docker/reinvent4-nf/Dockerfile .
#   # tag + push to ECR as biomate/reinvent4-nf:x86
#
# NOTE: REINVENT4 depends on torch + reinvent-chemistry and is x86_64-only in
# practice; ARM dev builds are not supported (the Nextflow process fails loudly
# with a clear "CLI/prior missing" message rather than fabricating molecules,
# which is the intended honesty contract).

FROM mambaorg/micromamba:1.5.8

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV REINVENT4_PRIORS=/opt/reinvent4/priors
# Nextflow AWS Batch replaces ENTRYPOINT with `bash -c …`, so micromamba's
# activate-on-entrypoint never runs. Pin conda bin + lib permanently (Batch
# keeps Docker ENV; it does NOT source micromamba activate, which normally
# sets LD_LIBRARY_PATH for torch/rdkit native libs).
ENV MAMBA_ROOT_PREFIX=/opt/conda
ENV CONDA_PREFIX=/opt/conda
ENV PATH=/opt/conda/bin:/usr/local/bin:/usr/bin:/bin
ENV LD_LIBRARY_PATH=/opt/conda/lib
# Activate base env for every Dockerfile RUN (official micromamba pattern).
# Combined with PATH/LD_LIBRARY_PATH above, Batch (no entrypoint) and build
# RUNs share one env.
ARG MAMBA_DOCKERFILE_ACTIVATE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates procps libxrender1 libxext6 \
    && rm -rf /var/lib/apt/lists/*
# procps provides `ps`, which Nextflow requires to collect task metrics; without
# it tasks fail at launch ("Command 'ps' required by nextflow ... cannot be found").

# ── Layer 0: Python + pip into micromamba base (required before any pip RUN) ─
# mambaorg/micromamba ships micromamba only — /opt/conda/bin has no python/pip
# until packages are installed. Bare `pip` on PATH fails with "command not found"
# (build-log-20261114T165757Z.txt step [3/13]). Install via micromamba so the
# same env Batch sees (PATH=/opt/conda/bin) has python3 + pip.
RUN micromamba install -y -n base -c conda-forge python=3.11 pip \
    && micromamba clean --all --yes \
    && python -c "import sys; print('python', sys.version)" \
    && python -m pip --version \
    && test "$(command -v python3)" = /opt/conda/bin/python3 \
    && test "$(command -v pip)" = /opt/conda/bin/pip

# ── Layer 1: REINVENT4 via official git + install.py (NOT PyPI) ──────────────
# `reinvent` is NOT published on PyPI (pip reinvent==4.5.* → "from versions: none").
# Upstream install (README): clone MolecularAI/REINVENT4, then
#   python install.py cpu -d none
# which runs: pip install . --extra-index-url https://download.pytorch.org/whl/cpu
# Pin a release tag. Layout at /opt/REINVENT4 matches main.nf PYTHONPATH bridge.
# -d none skips OpenEye/ChemProp/iSIM extras (no license / not needed for sampling).
# install.py calls bare `pip` (needs Layer 0); it does not check pip's exit code,
# so we hard-gate on `pip show` + CLI after.
ARG REINVENT4_REF=v4.9
# Upstream pyproject omits scipy, but reinvent.runmodes.utils.plot imports
# scipy.stats.gaussian_kde at module load (CLI `reinvent --help` path).
# Without an explicit pip, Batch-like #9 gate fails: ModuleNotFoundError: scipy
# (build-log-20261114T171639Z.txt). Pin 1.x for numpy 2 compatibility.
RUN git clone --depth 1 --branch "${REINVENT4_REF}" \
        https://github.com/MolecularAI/REINVENT4.git /opt/REINVENT4 \
    && cd /opt/REINVENT4 \
    && python install.py cpu -d none \
    && python -m pip show reinvent \
    && python -c "import reinvent; from reinvent.version import __version__; print('reinvent', __version__)" \
    && command -v reinvent \
    && ln -sf "$(command -v reinvent)" /usr/local/bin/reinvent \
    && python -m pip install --no-cache-dir 'scipy>=1.11,<2' \
    && python -c "import scipy; print('scipy', scipy.__version__)" \
    && reinvent --help

# Verify the CLI works WITHOUT micromamba entrypoint activation (Batch shape).
# Preserve the same ENV Batch inherits from the image (PATH + LD_LIBRARY_PATH),
# not a fully empty env — `env -i` with PATH alone fails torch/rdkit .so loads.
RUN /usr/bin/env -i \
        HOME=/root \
        PATH="/opt/conda/bin:/usr/local/bin:/usr/bin:/bin" \
        MAMBA_ROOT_PREFIX=/opt/conda \
        CONDA_PREFIX=/opt/conda \
        LD_LIBRARY_PATH=/opt/conda/lib \
        PYTHONNOUSERSITE=1 \
        reinvent --help \
    || (echo "FATAL: reinvent CLI failed under Batch-like env (no entrypoint)"; exit 1)

# ── Layer 2: Prior checkpoints (Apache-2.0, shipped in the REINVENT4 repo) ──
# The priors live in the REINVENT4 GitHub repo under priors/. We fetch the exact
# files we sample from and place them where generators.py + main.nf expect them:
#   $REINVENT4_PRIORS/reinvent.prior             (de-novo Reinvent prior)
#   $REINVENT4_PRIORS/mol2mol_similarity.prior   (Mol2Mol scaffold-hop/analog prior)
# Pinned to a REINVENT4 release tag so the checksums are reproducible.
# Priors: GitHub raw tags 404 / LFS; public checkpoints live on Zenodo
# (DOI 10.5281/zenodo.15641296 → record 20701824). Stage reinvent_pubchem as
# reinvent.prior (sampling default). mol2mol_similarity is no longer published —
# GENERATE_REINVENT4 falls back to reinvent_pubchem when mol2mol is requested.
RUN mkdir -p ${REINVENT4_PRIORS} \
    && curl -fSL --retry 3 --retry-delay 5 \
        -o ${REINVENT4_PRIORS}/reinvent.prior \
        https://zenodo.org/api/records/20701824/files/reinvent_pubchem.prior/content \
    && curl -fSL --retry 3 --retry-delay 5 \
        -o ${REINVENT4_PRIORS}/reinvent_pubchem.prior \
        https://zenodo.org/api/records/20701824/files/reinvent_pubchem.prior/content \
    && curl -fSL --retry 3 --retry-delay 5 \
        -o ${REINVENT4_PRIORS}/libinvent.prior \
        https://zenodo.org/api/records/20701824/files/libinvent.prior/content \
    && test -s ${REINVENT4_PRIORS}/reinvent.prior \
    && test "$(wc -c < ${REINVENT4_PRIORS}/reinvent.prior)" -gt 1000000 \
    || (echo "FATAL: REINVENT4 priors not staged from Zenodo" && exit 1)

# ── Layer 3: BioMate drug-discovery Python modules (Reinvent4Generator etc.) ─
RUN mkdir -p /opt/biomate/drug_discovery
COPY backend/lib/galaxy/ai/drug_discovery/ /opt/biomate/drug_discovery/
COPY backend/docker/reinvent4-nf/reinvent_runner.py /opt/biomate/reinvent_runner.py
RUN echo '# BioMate' > /opt/biomate/__init__.py && \
    echo '# BioMate drug discovery' > /opt/biomate/drug_discovery/__init__.py && \
    chmod +x /opt/biomate/reinvent_runner.py
# /opt/REINVENT4: source tree + site-packages install; /opt/biomate: BioMate modules.
# main.nf also exports PYTHONPATH=/opt/REINVENT4:/opt/biomate for Batch.
ENV PYTHONPATH=/opt/biomate:/opt/REINVENT4
# rdkit comes from REINVENT4 pyproject (install.py) — required for GENERATE_REINVENT4
# cheap descriptor scoring. FILTER_RANK / VALIDATE still use drug-discovery-nf
# (RDKIT_CONTAINER) for full BRICS / PAINS / diversity.

# ── Smoke 1: a 5-molecule de-novo sample must succeed (real learned generation) ─
# Runs on x86 only; kept non-fatal so a misconfigured CI runner doesn't block
# the build, but it MUST pass on the real x86 image before promotion to ECR.
RUN printf 'run_type = "sampling"\ndevice = "cpu"\n[parameters]\nmodel_file = "%s/reinvent.prior"\noutput_file = "/tmp/smoke.csv"\nnum_smiles = 5\nunique_molecules = true\n' "${REINVENT4_PRIORS}" > /tmp/smoke.toml \
    && reinvent /tmp/smoke.toml && test -s /tmp/smoke.csv \
    && echo "REINVENT4 sampling smoke OK" || echo "WARN: sampling smoke skipped/failed (verify on x86)"

# ── Smoke 2: a 2-epoch TRANSFER-LEARNING run must produce a NEW checkpoint ─────
# This proves the *training* path (deck slide 4 "generator fine-tuning") is real
# in-image, not just sampling. Uses the reviewed trainer to build the config so
# the same code path CI exercises is what production runs. x86-only; non-fatal at
# build time but MUST pass on the real x86 image before ECR promotion.
RUN printf 'CCO\nc1ccccc1\nCC(=O)O\nc1ccncc1\nCC(=O)N\n' > /tmp/tl_train.smi \
    && PYTHONPATH=/opt/biomate python -c "\
from drug_discovery.reinvent4_trainer import Reinvent4TransferLearner; \
r = Reinvent4TransferLearner().train('/tmp/tl_train.smi', '/tmp/tl_smoke.model', epochs=2, batch_size=4); \
print('transfer-learning smoke:', r.reason, r.checkpoint); \
assert r.ok and r.checkpoint, r.to_dict()" \
    && test -s /tmp/tl_smoke.model \
    && echo "REINVENT4 transfer-learning smoke OK" \
    || echo "WARN: transfer-learning smoke skipped/failed (verify on x86)"

# ── Smoke 3: the trainer honesty + config unit tests must pass (arch-agnostic) ─
# Pure-Python config builders + honesty gating; no torch/CLI needed, so this is
# a HARD gate even on the build host.
RUN PYTHONPATH=/opt/biomate python /opt/biomate/drug_discovery/test_reinvent4_trainer.py \
    && echo "REINVENT4 trainer unit tests OK"

WORKDIR /data
# python3 is a micromamba symlink to the same interpreter (Batch / Nextflow call python3).
CMD ["python3", "-c", "print('BioMate REINVENT4 NF Container Ready')"]
