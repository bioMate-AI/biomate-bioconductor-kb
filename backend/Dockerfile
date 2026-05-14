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

WORKDIR /app

# System deps:
#   - gcc/g++/git/libpq-dev/sqlite3/curl  → existing build/runtime tooling
#   - openjdk-17-jre-headless              → required by Nextflow (cryosparc_executor)
#   - procps                                → ps/kill used by Gravity supervisord
#   - ca-certificates                       → boto3 / nextflow HTTPS
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ git libpq-dev sqlite3 curl \
    default-jre-headless \
    procps ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Nextflow binary at a stable path. Install before Python deps so the
# pip layer can be rebuilt without re-downloading Nextflow.
RUN curl -fsSL https://get.nextflow.io | bash \
    && mv nextflow /usr/local/bin/nextflow \
    && chmod +x /usr/local/bin/nextflow

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

# Use container-specific Galaxy config (avoids the local-dev galaxy.yml which has
# `/home/yzhang/...` hardcoded paths and PYTHONPATH overrides that break inside
# the container). galaxy.yml.docker uses container-relative paths and the
# `galaxy_user: galaxy` setting Gravity requires when running as non-root.
RUN mv config/galaxy.yml.docker config/galaxy.yml \
    && mkdir -p database logs config/plugins \
    && chmod +x /app/start_biomate.sh /app/run.sh 2>/dev/null || true \
    # Galaxy's default 'files' log handler writes to /app/galaxy.log; the file
    # must exist and be writable by the galaxy user BEFORE Galaxy starts,
    # otherwise dictConfig raises "Unable to configure handler 'files'".
    && touch /app/galaxy.log \
    && chown galaxy:galaxy /app/galaxy.log

ENV PYTHONUNBUFFERED=1
ENV GALAXY_CONFIG_FILE=/app/config/galaxy.yml
ENV GALAXY_SKIP_NODE=1

USER galaxy

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/api/version || exit 1

# Use start_biomate.sh as the entrypoint — same script the existing dev container
# was running (previously injected manually via docker cp and committed).
ENTRYPOINT ["/bin/sh"]
CMD ["/app/start_biomate.sh"]
