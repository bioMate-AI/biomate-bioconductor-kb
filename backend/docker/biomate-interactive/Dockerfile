# BioMate All-in-One Interactive Tools Container
# Combined: Jupyter + RStudio + CellxGene + Visualization tools
#
# Single container for ALL interactive analysis needs
# More efficient for local deployment

FROM jupyter/datascience-notebook:python-3.11

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="All-in-One Interactive Tools for BioMate"

USER root

# ============================================
# System dependencies (all tools)
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    build-essential \
    # HDF5/data formats
    libhdf5-dev \
    # Network/SSL
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    # Graphics
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libcairo2-dev \
    # Bioinformatics CLI
    samtools \
    bcftools \
    bedtools \
    tabix \
    # Web server
    nginx \
    supervisor \
    # RStudio dependencies
    psmisc \
    libclang-dev \
    gdebi-core \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Install RStudio Server (architecture-aware)
# ============================================
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "amd64" ]; then \
        curl -o /tmp/rstudio.deb https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2023.12.1-402-amd64.deb \
        && gdebi -n /tmp/rstudio.deb \
        && rm /tmp/rstudio.deb; \
    else \
        echo "RStudio Server not available for ARM64, using R console only"; \
    fi

# ============================================
# Python packages (Jupyter + CellxGene + viz)
# ============================================
USER ${NB_UID}

RUN mamba install -y -c conda-forge -c bioconda \
    # Core data science
    pandas numpy scipy matplotlib seaborn plotly bokeh \
    # Bioinformatics
    scanpy anndata pysam pyvcf3 biopython pybedtools \
    # Galaxy integration
    bioblend \
    # Genomics visualization
    pygenometracks igv-notebook \
    # Utilities
    h5py openpyxl xlrd requests \
    && mamba clean -a -y

# CellxGene and additional viz
RUN pip install --no-cache-dir \
    cellxgene \
    gseapy \
    adjustText \
    statannot \
    jupyterlab-git \
    dash \
    streamlit

# ============================================
# R packages (shared with RStudio)
# ============================================
RUN mamba install -y -c conda-forge -c bioconda \
    # Bioconductor
    bioconductor-deseq2 \
    bioconductor-edger \
    bioconductor-limma \
    bioconductor-clusterprofiler \
    bioconductor-enrichplot \
    bioconductor-complexheatmap \
    bioconductor-genomicranges \
    bioconductor-rtracklayer \
    # Visualization
    r-ggplot2 r-pheatmap r-ggrepel r-viridis r-rcolorbrewer \
    # Data manipulation
    r-tidyverse r-data.table r-dt \
    # Shiny for Pavian-like apps
    r-shiny r-shinydashboard r-plotly \
    && mamba clean -a -y

# Install Pavian
RUN R -e "install.packages('remotes', repos='https://cloud.r-project.org/')" && \
    R -e "remotes::install_github('fbreitwieser/pavian')"

USER root

# ============================================
# Configuration files
# ============================================

# Supervisor config to run all services
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Nginx config for unified access
COPY nginx.conf /etc/nginx/sites-available/default

# Jupyter config
COPY jupyter_config.py /home/${NB_USER}/.jupyter/jupyter_notebook_config.py

# RStudio config
RUN echo "www-port=8787" >> /etc/rstudio/rserver.conf && \
    echo "www-address=127.0.0.1" >> /etc/rstudio/rserver.conf && \
    echo "auth-none=1" >> /etc/rstudio/rserver.conf

# Startup script
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

# Create directories
RUN mkdir -p /import /export /home/${NB_USER}/shared && \
    chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}

# ============================================
# Ports
# ============================================
# 80   - Nginx (main entry, routes to services)
# 8888 - Jupyter
# 8787 - RStudio
# 5005 - CellxGene
# 3838 - Shiny (Pavian)
EXPOSE 80 8888 8787 5005 3838

# Environment
ENV GALAXY_URL="" \
    GALAXY_API_KEY="" \
    HISTORY_ID=""

WORKDIR /home/${NB_USER}

CMD ["/usr/local/bin/startup.sh"]
