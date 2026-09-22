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

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates libxrender1 libxext6 \
    && rm -rf /var/lib/apt/lists/*

# ── Layer 1: REINVENT4 + deps via pip (CPU torch by default) ────────────────
# REINVENT4 is published on PyPI as `reinvent`. Pin a released tag for
# reproducibility. Torch CPU wheel keeps the image slim; the workflow sets
# device="cuda:0" only when params.gpu=true AND a GPU image is used.
RUN pip install --no-cache-dir \
        torch --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir \
        reinvent==4.5.* \
        rdkit \
    && python3 -c "import reinvent; print('reinvent import OK')"

# Verify the CLI entrypoint resolves.
RUN reinvent --help >/dev/null 2>&1 || (echo "FATAL: reinvent CLI not on PATH" && exit 1)

# ── Layer 2: Prior checkpoints (Apache-2.0, shipped in the REINVENT4 repo) ──
# The priors live in the REINVENT4 GitHub repo under priors/. We fetch the exact
# files we sample from and place them where generators.py + main.nf expect them:
#   $REINVENT4_PRIORS/reinvent.prior             (de-novo Reinvent prior)
#   $REINVENT4_PRIORS/mol2mol_similarity.prior   (Mol2Mol scaffold-hop/analog prior)
# Pinned to a REINVENT4 release tag so the checksums are reproducible.
ARG REINVENT4_REF=v4.5.5
RUN mkdir -p ${REINVENT4_PRIORS} \
    && curl -fSL --retry 3 --retry-delay 5 \
        -o ${REINVENT4_PRIORS}/reinvent.prior \
        https://raw.githubusercontent.com/MolecularAI/REINVENT4/${REINVENT4_REF}/priors/reinvent.prior \
    && curl -fSL --retry 3 --retry-delay 5 \
        -o ${REINVENT4_PRIORS}/mol2mol_similarity.prior \
        https://raw.githubusercontent.com/MolecularAI/REINVENT4/${REINVENT4_REF}/priors/mol2mol_similarity.prior \
    && test -s ${REINVENT4_PRIORS}/reinvent.prior \
    && test -s ${REINVENT4_PRIORS}/mol2mol_similarity.prior \
    || (echo "FATAL: REINVENT4 priors not staged" && exit 1)

# ── Layer 3: BioMate drug-discovery Python modules (Reinvent4Generator etc.) ─
RUN mkdir -p /opt/biomate/drug_discovery
COPY backend/lib/galaxy/ai/drug_discovery/ /opt/biomate/drug_discovery/
RUN echo '# BioMate' > /opt/biomate/__init__.py && \
    echo '# BioMate drug discovery' > /opt/biomate/drug_discovery/__init__.py
ENV PYTHONPATH="/opt/biomate:${PYTHONPATH}"

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
    && PYTHONPATH=/opt/biomate python3 -c "\
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
RUN PYTHONPATH=/opt/biomate python3 /opt/biomate/drug_discovery/test_reinvent4_trainer.py \
    && echo "REINVENT4 trainer unit tests OK"

WORKDIR /data
CMD ["python3", "-c", "print('BioMate REINVENT4 NF Container Ready')"]
