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
FROM python:3.9-slim

# Build-arg-driven version pins. Bump these in PRs only; never let the image
# upgrade Nextflow transitively (past incident: NF 26.04 broke 16+ workflow
# directives in cryosparc_standard_spa due to DSL2 strictness — L5 in
# docs/20260514_CICD_REBUILD_PLAN.md §6.3).
ARG NF_VERSION=24.10.5
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown

WORKDIR /app

# System deps:
#   - gcc/g++/git/libpq-dev/sqlite3/curl  → existing build/runtime tooling
#   - openjdk-17-jre-headless              → required by Nextflow (cryosparc_executor)
#   - procps                                → ps/kill used by Gravity supervisord
#   - ca-certificates                       → boto3 / nextflow HTTPS
#   - unzip                                 → AWS CLI v2 installer
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ git libpq-dev sqlite3 curl unzip \
    default-jre-headless \
    procps ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Nextflow binary at a stable path. Pinned to ${NF_VERSION}. Install before
# Python deps so the pip layer can be rebuilt without re-downloading Nextflow.
RUN curl -fsSL "https://github.com/nextflow-io/nextflow/releases/download/v${NF_VERSION}/nextflow" \
        -o /usr/local/bin/nextflow \
    && chmod +x /usr/local/bin/nextflow \
    && /usr/local/bin/nextflow -version

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

USER galaxy

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/api/version || exit 1

# Use start_biomate.sh as the entrypoint — same script the existing dev container
# was running (previously injected manually via docker cp and committed).
ENTRYPOINT ["/bin/sh"]
CMD ["/app/start_biomate.sh"]
