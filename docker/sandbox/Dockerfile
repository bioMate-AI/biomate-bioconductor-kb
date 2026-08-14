# biomate-nextflow-sandbox — hardened Nextflow HEAD runner for Feature ① sandbox.
#
# The compute-platform-v2 sandbox (backend/lib/galaxy/ai/compute/sandbox/)
# wraps a user run's Nextflow HEAD process in a locked-down container. This is
# the image that container runs. It is built FROM the production Batch *task*
# base (python3 + awscli + rdkit/gget/biopython) so a local-executor user
# workflow's tasks share the same runtime as production Batch tasks, then adds
# the two things the head needs and the task base lacks: a JRE and Nextflow.
#
# It runs under the exact flags command.py emits:
#   --read-only --cap-drop ALL --security-opt no-new-privileges
#   --user <non-root uid> --tmpfs /tmp --pids-limit --cpus --memory
#   --network none|<egress-net>   (+ --runtime runsc for tier 3)
# so ALL writable state must live in /tmp (tmpfs) or the bind-mounted work
# dir. Nextflow insists on a WRITABLE NXF_HOME (plugins/tmp dirs); under a
# read-only rootfs we bake the framework into a read-only /opt/nxf_seed and an
# entrypoint seeds a writable NXF_HOME on tmpfs from it at each run start.
#
# Build on the TEST host (amd64), from this directory as context:
#   docker build -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-sandbox:latest \
#     -f docker/sandbox/Dockerfile docker/sandbox
ARG BASE=399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest
FROM ${BASE}

# Keep in lockstep with the executor's pin (_sanitize_subprocess_env NXF_VER).
ARG NXF_VER=25.10.5

# Java 21 — Nextflow 25.x supports JRE 17-21; the base is Debian 13 (trixie),
# which ships openjdk-21 (17 was dropped). headless keeps it slim.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-21-jre-headless curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download the launcher + pre-bake the framework/capsule into a READ-ONLY seed
# so nothing is fetched at runtime (works offline / under --network none).
ENV NXF_VER=${NXF_VER}
RUN mkdir -p /opt/nxf_seed/capsule \
    && curl -s https://get.nextflow.io | bash \
    && mv nextflow /usr/local/bin/nextflow \
    && chmod 755 /usr/local/bin/nextflow \
    && NXF_HOME=/opt/nxf_seed CAPSULE_CACHE_DIR=/opt/nxf_seed/capsule NXF_VER=${NXF_VER} nextflow -version \
    && chmod -R a+rX /opt/nxf_seed

# Entrypoint: seed a writable NXF_HOME (tmpfs) from the read-only baked copy,
# so Nextflow can create its plugins/tmp dirs even with a read-only rootfs.
RUN printf '#!/bin/sh\nset -e\nexport NXF_HOME="${NXF_HOME:-/tmp/.nextflow}"\nmkdir -p "$NXF_HOME"\ncp -rn /opt/nxf_seed/. "$NXF_HOME"/ 2>/dev/null || true\nexec "$@"\n' \
      > /usr/local/bin/nxf-entrypoint.sh \
    && chmod 755 /usr/local/bin/nxf-entrypoint.sh

# Runtime env: writable state -> /tmp (tmpfs) or the mounted work dir.
# HOME=/tmp so Java/Nextflow have a writable home under a numeric --user with
# no /etc/passwd entry. NXF_OFFLINE keeps the head hermetic (tier 2 has no net).
ENV HOME=/tmp \
    NXF_HOME=/tmp/.nextflow \
    CAPSULE_CACHE_DIR=/tmp/.nextflow/capsule \
    NXF_ANSI_LOG=false \
    NXF_OFFLINE=true

ENTRYPOINT ["/usr/local/bin/nxf-entrypoint.sh"]
CMD ["bash"]
