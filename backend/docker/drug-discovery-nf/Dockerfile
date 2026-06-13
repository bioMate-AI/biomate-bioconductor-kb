# BioMate Drug Discovery Nextflow Container
#
# Extends biomate/biomni-structure-to-drug (rdkit + scipy already present)
# and adds the gap-filling tools:
#   - aizynthfinder   : retrosynthesis (Gap 4)
#   - pydeseq2        : Python DESeq2 for drug MoA pipeline (Gap 9)
#   - gseapy          : GSEA / pathway enrichment (Gap 9)
#   - pubchempy       : vendor availability lookup (Gap 10)
#   - BioMate drug discovery Python modules (Gaps 1,5,6,7,10)
#
# Build:
#   docker build -t biomate/biomni-drug-discovery-nf:latest \
#     -f backend/docker/drug-discovery-nf/Dockerfile .
#
# The image is used by Nextflow workflows in:
#   backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-structure-to-drug:x86

LABEL maintainer="BioMate Team"
LABEL description="Drug discovery Nextflow tools: aizynthfinder, AutoDock Vina, ViennaRNA, pydeseq2, gseapy + BioMate modules"
LABEL version="1.1.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV BIOMATE_DD=/opt/biomate/drug_discovery

# ── Layer 1: Extra system deps needed by aizynthfinder ─────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxrender1 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# ── Layer 2: Gap-filling Python packages ───────────────────────────────────
RUN pip install --no-cache-dir \
    aizynthfinder>=4.4.1 \
    pydeseq2 \
    gseapy \
    pubchempy \
    adjustText \
    vina \
    gemmi \
    meeko \
    ViennaRNA \
    openbabel-wheel

# ── Layer 3: AiZynthFinder minimal config + stock ──────────────────────────
# We provide a self-contained config that uses a template-based expansion
# policy (SMARTS reaction templates shipped with the aizynthfinder package)
# and a small stock of commodity starting materials.
# No large model download required for this baseline config.
RUN mkdir -p /opt/aizynthfinder/stock

# Write a SMILES stock file of common starting materials and the AiZynthFinder config.
# Use || true so QEMU x86-on-ARM emulation segfaults don't abort the image build;
# the script will succeed on real x86 hardware (AWS Batch).
COPY backend/docker/drug-discovery-nf/setup_aizynthfinder.py /tmp/setup_aizynthfinder.py
RUN python3 /tmp/setup_aizynthfinder.py || true
RUN rm -f /tmp/setup_aizynthfinder.py

# Verify installed packages. Each check is non-fatal under QEMU x86-on-ARM
# emulation (some native extensions segfault); all will pass on real x86.
RUN python3 -c "from importlib.metadata import version; print('aizynthfinder:', version('aizynthfinder'))" || true
RUN python3 -c "import gseapy; print('gseapy:', gseapy.__version__)" || true
RUN python3 -c "from pydeseq2.dds import DeseqDataSet; print('pydeseq2: OK')" || true
RUN python3 -c "import rdkit; print('rdkit:', rdkit.__version__)" || true
RUN python3 -c "from vina import Vina; print('vina: OK')" || true
RUN python3 -c "import RNA; print('ViennaRNA: OK')" || true
RUN echo "Drug discovery layer complete (verify on real x86)"

# ── Layer 4: USPTO expansion model + templates (canonical Zenodo URLs) ─────
# Pulls ~90 MB of USPTO ONNX model + templates straight from Zenodo, the
# canonical source named in aizynthfinder.tools.download_public_data.
# (That module is a CLI entry-point — not importable — so the prior
# Dockerfile's `from ... import download_public_data` always failed and was
# masked by `|| true`, leaving the image with no expansion policy.) Curl is
# pinned to the same Zenodo records used by the upstream package.
# Fail loudly if either file fails to download — a broken image is worse
# than a failed build.
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/aizynthfinder/models \
    && curl -fSL --retry 3 --retry-delay 5 \
        -o /opt/aizynthfinder/models/uspto_model.onnx \
        https://zenodo.org/record/7797465/files/uspto_model.onnx \
    && curl -fSL --retry 3 --retry-delay 5 \
        -o /opt/aizynthfinder/models/uspto_templates.csv.gz \
        https://zenodo.org/record/7341155/files/uspto_unique_templates.csv.gz \
    && test -s /opt/aizynthfinder/models/uspto_model.onnx \
    && test -s /opt/aizynthfinder/models/uspto_templates.csv.gz

# Re-run setup so config.yml picks up the now-present model + templates.
COPY backend/docker/drug-discovery-nf/setup_aizynthfinder.py /tmp/setup_aizynthfinder2.py
RUN python3 /tmp/setup_aizynthfinder2.py
RUN grep -q "^expansion:" /opt/aizynthfinder/config.yml \
    || (echo "FATAL: config.yml has no expansion: block — model staging failed" && exit 1)
RUN rm -f /tmp/setup_aizynthfinder2.py

# ── Layer 5: Copy BioMate drug discovery Python modules ────────────────────
RUN mkdir -p ${BIOMATE_DD}
COPY backend/lib/galaxy/ai/drug_discovery/ /opt/biomate/drug_discovery/
RUN echo '# BioMate drug discovery package' > /opt/biomate/__init__.py && \
    echo '# BioMate drug discovery modules' > /opt/biomate/drug_discovery/__init__.py

# Make modules importable
ENV PYTHONPATH="/opt/biomate:${PYTHONPATH}"

# ── Verify complete stack ───────────────────────────────────────────────────
# verify_stack.py asserts the aizynthfinder runtime is actually wired (config
# has an expansion: block + USPTO ONNX is present + non-truncated). Failing
# the build here is the point — a silent broken image is what we're fixing.
COPY backend/docker/drug-discovery-nf/verify_stack.py /tmp/verify_stack.py
RUN python3 /tmp/verify_stack.py
RUN rm -f /tmp/verify_stack.py

WORKDIR /data
CMD ["python3", "-c", "print('BioMate Drug Discovery NF Container Ready')"]
