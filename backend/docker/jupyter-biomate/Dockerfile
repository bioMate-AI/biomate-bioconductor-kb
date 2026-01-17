# BioMate Jupyter Interactive Tool
# For Galaxy Interactive Tools framework
#
# Features:
# - Full bioinformatics Python stack
# - R kernel with Bioconductor
# - Galaxy data integration
# - Pre-installed visualization libraries

FROM jupyter/datascience-notebook:python-3.11

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="Jupyter for Galaxy Interactive Tools"

USER root

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libhdf5-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    samtools \
    bcftools \
    bedtools \
    tabix \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER ${NB_UID}

# ============================================
# Python bioinformatics packages
# ============================================
RUN mamba install -y -c conda-forge -c bioconda \
    # Core
    pandas numpy scipy matplotlib seaborn plotly \
    # Bioinformatics
    scanpy anndata pysam pyvcf3 biopython pybedtools \
    # Galaxy
    bioblend \
    # Genomics visualization
    pygenometracks igv-notebook \
    # Utilities
    h5py openpyxl xlrd \
    && mamba clean -a -y

# Additional Python packages
RUN pip install --no-cache-dir \
    gseapy adjustText statannot \
    jupyterlab-git

# ============================================
# R packages (Bioconductor + visualization)
# ============================================
RUN mamba install -y -c conda-forge -c bioconda \
    bioconductor-deseq2 \
    bioconductor-edger \
    bioconductor-limma \
    bioconductor-clusterprofiler \
    bioconductor-enrichplot \
    bioconductor-complexheatmap \
    bioconductor-genomicranges \
    bioconductor-rtracklayer \
    r-ggplot2 r-pheatmap r-ggrepel r-viridis \
    r-tidyverse r-data.table r-dt \
    && mamba clean -a -y

# ============================================
# Galaxy Interactive Tools configuration
# ============================================

# Entry point script for Galaxy IT
COPY --chown=${NB_UID}:${NB_GID} startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

# Galaxy expects specific port
ENV JUPYTER_PORT=8888
EXPOSE 8888

WORKDIR /home/${NB_USER}

# Galaxy IT entry point
CMD ["/usr/local/bin/startup.sh"]
