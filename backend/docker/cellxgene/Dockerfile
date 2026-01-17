# BioMate CellxGene Interactive Tool
# Single-cell data visualization
#
# Features:
# - cellxgene for AnnData visualization
# - Pre-configured for Galaxy IT

FROM python:3.11-slim

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="CellxGene for Galaxy Interactive Tools"

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libhdf5-dev \
    build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install cellxgene
RUN pip install --no-cache-dir \
    cellxgene \
    scanpy \
    anndata

# Create user
RUN useradd -m -s /bin/bash cellxgene
USER cellxgene
WORKDIR /home/cellxgene

# Startup script
COPY --chown=cellxgene:cellxgene startup.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/startup.sh
USER cellxgene

# Default port
ENV CELLXGENE_PORT=5005
EXPOSE 5005

CMD ["/usr/local/bin/startup.sh"]
