# BioMate Analysis Notebook
# For automated batch analysis and visualization

FROM jupyter/datascience-notebook:python-3.11

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="BioMate Analysis Notebook with Galaxy integration"

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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER ${NB_UID}

# ============================================
# Python packages
# ============================================
RUN mamba install -y -c conda-forge -c bioconda \
    pandas numpy scipy matplotlib seaborn plotly \
    scanpy anndata pysam biopython bioblend \
    papermill nbconvert requests h5py openpyxl \
    && mamba clean -a -y

RUN pip install --no-cache-dir \
    gseapy adjustText statannot pyvcf3

# ============================================
# R packages via BiocManager (more reliable)
# ============================================
RUN R -e "install.packages('BiocManager', repos='https://cloud.r-project.org/')"

# Bioconductor - core
RUN R -e "BiocManager::install(c('DESeq2', 'edgeR', 'limma'), ask=FALSE, update=FALSE)"

# Bioconductor - enrichment
RUN R -e "BiocManager::install(c('clusterProfiler', 'enrichplot'), ask=FALSE, update=FALSE)"

# Bioconductor - heatmaps
RUN R -e "BiocManager::install('ComplexHeatmap', ask=FALSE, update=FALSE)"

# CRAN packages
RUN R -e "install.packages(c('ggplot2', 'pheatmap', 'ggrepel', 'viridis', 'RColorBrewer', 'tidyverse', 'data.table'), repos='https://cloud.r-project.org/')"

# ============================================
# Galaxy integration
# ============================================
COPY --chown=${NB_UID}:${NB_GID} galaxy_integration/ /opt/conda/lib/python3.11/site-packages/galaxy_notebook/
COPY --chown=${NB_UID}:${NB_GID} templates/ /home/${NB_USER}/templates/
COPY --chown=${NB_UID}:${NB_GID} jupyter_notebook_config.py /home/${NB_USER}/.jupyter/

ENV GALAXY_URL="" \
    HISTORY_ID="" \
    BIOMATE_NOTEBOOK_VERSION="1.0"

WORKDIR /home/${NB_USER}
EXPOSE 8888

CMD ["start-notebook.sh", "--NotebookApp.token=''"]
