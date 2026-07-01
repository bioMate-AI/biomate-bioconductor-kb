# Galaxy Backend Dockerfile — biomate-galaxy-backend:latest
#
# Bakes in EVERYTHING the runtime needs so that fresh `docker run` from this
# image starts a fully-working Galaxy without any post-start pip/apt installs.
# Until this Dockerfile is rebuilt, dev containers from the old (Mar 31) image
# are missing boto3/redis/psycopg2/nextflow/java, and the sync_to_dev.sh script
# papers over the gap with runtime installs.
#
# Build:
#   docker build -t biomate-galaxy-backend:latest -f backend/Dockerfile backend/
#
# BASE IMAGE — must stay on Debian bookworm, NOT trixie.
# python:3.9-slim (without explicit codename) now resolves to Debian 13 trixie
# whose glibc 2.41 has a flaky ld-linux dlopen path that AWS CRT native lib
# hits, randomly SIGSEGV'ing the JVM mid-run. Bookworm (Debian 12, glibc 2.36)
# is the known-good combination. Empirical evidence:
#   - 2026-06-05 parallel sweep of 19 workflows: 14/16 JVM SIGABRT on trixie
#   - Bookworm also still has openjdk-17 (which we pin below); trixie dropped it
# DO NOT REVERT to `python:3.9-slim` without first verifying both:
#   (a) glibc < 2.41 OR JDK 17 still available
#   (b) the workflow sweep passes without JVM crashes
FROM python:3.9-slim-bookworm

# Build-arg-driven version pins. Bump these in PRs only; never let the image
# upgrade Nextflow transitively (past incident: NF 26.04 broke 16+ workflow
# directives in cryosparc_standard_spa due to DSL2 strictness — L5 in
# docs/20260514_CICD_REBUILD_PLAN.md §6.3).
ARG NF_VERSION=25.10.5
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown

# CRITICAL: pin Nextflow version EVERYWHERE that can pin it.
# We've had NXF_VER stripped from nextflow_executor.py 5+ times by parallel
# sweeps. Each time, the launcher script silently downloaded the LATEST NF
# (was 26.04.2 last incident), which:
#   1. Made AWS CRT the default S3 client (→ JVM SIGSEGV chain)
#   2. Broke 16+ workflow directives in cryosparc_standard_spa from DSL2
#      strictness (L5 in docs/20260514_CICD_REBUILD_PLAN.md §6.3)
# Defense-in-depth:
#   - ENV NXF_VER below sets the env-var default at the container level
#   - ENV NXF_OFFLINE=true forbids the launcher from going to the network
#   - The nextflow-25.10.5-one.jar gets pre-fetched + cached at /opt/nextflow
#     so the launcher never even tries to download
# If any sweep strips one of these, the others still hold.
ENV NXF_VER=${NF_VERSION}
# NXF_OFFLINE intentionally NOT set: NF plugins (nf-amazon@3.4.4) are not
# pre-cached in the image, so the launcher must reach the plugin index on
# first run. The NXF_VER pin above is the load-bearing guard against version
# drift; NXF_OFFLINE was redundant with it and broke plugin resolution.
# (See commit f5cd88d97 — nextflow_executor.py also explicitly unsets it.)
ENV NXF_HOME=/opt/nextflow

WORKDIR /app

# System deps:
#   - gcc/g++/git/libpq-dev/sqlite3/curl  → existing build/runtime tooling
#   - openjdk-17-jre-headless              → required by Nextflow (cryosparc_executor)
#   - procps                                → ps/kill used by Gravity supervisord
#   - ca-certificates                       → boto3 / nextflow HTTPS
#   - unzip                                 → AWS CLI v2 installer
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ git libpq-dev sqlite3 curl unzip \
    openjdk-17-jre-headless \
    procps ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# JDK 17 is REQUIRED (do not change to default-jre-headless).
# default-jre-headless on Debian 13 trixie = OpenJDK 21. JDK 21 + glibc 2.41 +
# AWS CRT native lib randomly SIGSEGVs the JVM in ld-linux during the dlopen
# of /tmp/aws-crt-*.so. The crash hits Nextflow's FileTransfer/PublishDir
# threads, killing the entire NF process and dropping every workflow output
# even when AWS Batch tasks succeeded. JDK 17 + glibc 2.41 is known-good.
# Root-cause analysis: docs/20260605_19_WORKFLOW_SWEEP_RESULT.md.
# DO NOT REVERT to default-jre-headless without verifying glibc compatibility.

# Nextflow launcher script at a stable path. Pinned to ${NF_VERSION}.
# Install before Python deps so the pip layer can be rebuilt without
# re-downloading Nextflow.
RUN curl -fsSL "https://github.com/nextflow-io/nextflow/releases/download/v${NF_VERSION}/nextflow" \
        -o /usr/local/bin/nextflow \
    && chmod +x /usr/local/bin/nextflow

# Pre-fetch the framework JAR so the launcher never goes to the network at
# run time. Without this, the first invocation of `nextflow run ...`
# downloads nextflow-${NF_VERSION}-one.jar from GitHub even if NXF_VER is
# set — and if GitHub is throttling or NXF_VER got stripped, the launcher
# happily picks "latest" instead. With the jar pre-cached under
# /opt/nextflow/framework/${NF_VERSION}/ AND NXF_HOME=/opt/nextflow set as
# ENV above, the launcher resolves locally and the network is never touched.
# Verified: running `NXF_OFFLINE=true nextflow run ...` against a missing
# pre-cached jar fails fast rather than silently fetching a newer version.
RUN mkdir -p /opt/nextflow/framework/${NF_VERSION} \
    && curl -fsSL \
        "https://www.nextflow.io/releases/v${NF_VERSION}/nextflow-${NF_VERSION}-one.jar" \
        -o "/opt/nextflow/framework/${NF_VERSION}/nextflow-${NF_VERSION}-one.jar" \
    && chown -R 1000:1000 /opt/nextflow \
    && ls -la /opt/nextflow/framework/${NF_VERSION}/

# Also pre-fetch the nf-amazon plugin at a known-compatible version so we
# never auto-fetch a CRT-default-on plugin upgrade either. Plugin lives at
# $NXF_HOME/plugins by convention.
# (When/if we audit which nf-amazon version is the right pin, replace here.)
# For now: cache the version already present in NF 25.10.5's plugin manifest.

# Force-pin via env that nextflow_executor.py also re-asserts in subprocess
# env (5th re-application: 874e40fb8). Belt + suspenders.
RUN /usr/local/bin/nextflow -version 2>&1 | head -3

# AWS CLI v2 in /opt/aws-cli (self-contained — past incident: a symlink to
# /usr/bin/aws broke when Nextflow bind-mounted /opt/aws-cli into Batch task
# containers, causing exit 127 on ALL Batch jobs — L18).
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && /opt/aws-cli/bin/aws --version

# Galaxy refuses to start as root unless galaxy_user is set. Create the user
# BEFORE copying app code so we can chown-during-COPY (single layer, no
# expensive recursive chown that doubled disk usage and ran out of space).
# UID/GID 1000 matches the pre-2026-05-11 image's `lxd` user.
RUN groupadd -g 1000 galaxy && useradd -u 1000 -g 1000 -d /app -s /bin/bash galaxy

# Python dependencies. requirements.txt now includes boto3/redis/psycopg2-binary
# (added 2026-05-10) so fresh containers no longer need post-start pip installs.
COPY --chown=galaxy:galaxy requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code with correct ownership in one shot.
COPY --chown=galaxy:galaxy . .

# Container Galaxy config from the secret-free template (checked into git).
# Template uses ${ANTHROPIC_API_KEY} / ${OPENAI_API_KEY} placeholders that
# Galaxy interpolates from the container environment at startup. Secrets
# are NEVER baked into the image (L9).
#
# Note: in dev today, config/galaxy.yml.docker on the host has real secrets and
# is mounted in via the deploy. That file is gitignored on purpose and stays
# out of the image. Once Secrets Manager lands (P2.3), the container will
# fetch secrets at boot via IAM role and the host-mounted file goes away.
RUN cp config/galaxy.yml.template config/galaxy.yml \
    && mkdir -p database logs config/plugins /app/.nextflow \
    # Galaxy needs several .sample config files at /app/config/ at boot. The
    # canonical copies ship inside lib/galaxy/config/sample/ (upstream Galaxy).
    # The host's backend/config/*.sample files are gitignored so they don't
    # exist in the build context — pull from the vendored sample dir instead.
    && cp -n lib/galaxy/config/sample/tool_conf.xml.sample            config/ \
    && cp -n lib/galaxy/config/sample/datatypes_conf.xml.sample       config/ \
    && cp -n lib/galaxy/config/sample/job_conf.sample.yml             config/ \
    && cp -n lib/galaxy/config/sample/tool_data_table_conf.xml.sample config/ \
    && chmod +x /app/start_biomate.sh /app/run.sh \
    # Galaxy's default 'files' log handler writes to /app/galaxy.log; the file
    # must exist and be writable by the galaxy user BEFORE Galaxy starts,
    # otherwise dictConfig raises "Unable to configure handler 'files'".
    && touch /app/galaxy.log \
    # /app itself was created by WORKDIR before useradd and is root-owned;
    # COPY --chown only affects copied content, not the parent dir. Without
    # this, Nextflow's mkdir ~/.nextflow fails with EACCES when running as
    # the galaxy user.
    && chown galaxy:galaxy /app /app/galaxy.log /app/.nextflow \
    && chown -R galaxy:galaxy /app/database /app/logs /app/config/plugins

ENV PYTHONUNBUFFERED=1
ENV GALAXY_CONFIG_FILE=/app/config/galaxy.yml
ENV GALAXY_SKIP_NODE=1
# Docker doesn't auto-set HOME from /etc/passwd when USER is specified —
# Nextflow then tries to mkdir /.nextflow (HOME=/) and fails. Set HOME
# explicitly to galaxy's home (per useradd above).
ENV HOME=/app
ENV NXF_HOME=/app/.nextflow

# Bake build provenance into the image so a running container can be traced
# back to its source commit + build time (past incident L1 — stale `latest`
# tag masked 5-week image drift).
RUN echo "git_sha=${GIT_SHA}"      >  /image-build-info \
    && echo "build_date=${BUILD_DATE}" >> /image-build-info \
    && echo "nf_version=${NF_VERSION}" >> /image-build-info \
    && cat /image-build-info

# Bake the sentence-transformer CHAIN-embedding model (all-MiniLM-L6-v2) into
# the image's HF cache so the /api/workflows/search path loads it locally
# (local_files_only=True) in ~0.6s. Without this, the first request per worker
# fetches it from huggingface.co — 2s on a good network, but a ~13s CONNECT-TIMEOUT
# HANG when the network is slow/blocked, which tripped the connector's cold-start
# timeout (incident 2026-07-01). Root-owned + world-readable so the galaxy user
# can read it at runtime.
# NOTE: BGE (BAAI/bge-small-en-v1.5, workflow dense retrieval) is intentionally
# NOT baked here — enabling it also requires the prebuilt embeddings .npz, else
# _ensure_workflow_embeddings() runs a ~67s _build on every worker recycle. Bake
# BGE + its .npz together in a follow-up to re-enable dense retrieval.
ENV HF_HOME=/opt/hf_cache
RUN mkdir -p /opt/hf_cache \
    && HF_HOME=/opt/hf_cache python3 -c "from sentence_transformers import SentenceTransformer as S; S('all-MiniLM-L6-v2')" \
    && chmod -R a+rX /opt/hf_cache

USER galaxy

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/api/version || exit 1

# Use start_biomate.sh as the entrypoint — same script the existing dev container
# was running (previously injected manually via docker cp and committed).
ENTRYPOINT ["/bin/sh"]
CMD ["/app/start_biomate.sh"]
