# BioMate RStudio Interactive Tool
# For Galaxy Interactive Tools framework
#
# Features:
# - RStudio Server with Bioconductor
# - Pre-installed DESeq2, edgeR, visualization packages
# - Galaxy data integration

FROM rocker/rstudio:4.3

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="RStudio for Galaxy Interactive Tools"

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libhdf5-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgit2-dev \
    samtools \
    bcftools \
    bedtools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Bioconductor packages
# ============================================
RUN R -e "install.packages('BiocManager', repos='https://cloud.r-project.org/')" && \
    R -e "BiocManager::install(c( \
        'DESeq2', 'edgeR', 'limma', \
        'clusterProfiler', 'enrichplot', 'org.Hs.eg.db', \
        'ComplexHeatmap', 'GenomicRanges', 'rtracklayer', \
        'Rsamtools', 'VariantAnnotation' \
    ), ask=FALSE, update=FALSE)"

# ============================================
# CRAN packages
# ============================================
RUN R -e "install.packages(c( \
        'tidyverse', 'ggplot2', 'pheatmap', 'ggrepel', \
        'viridis', 'RColorBrewer', 'plotly', 'DT', \
        'data.table', 'openxlsx', 'devtools', 'shiny' \
    ), repos='https://cloud.r-project.org/')"

# ============================================
# Galaxy Interactive Tools configuration
# ============================================
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

# RStudio default port
ENV RSTUDIO_PORT=8787
EXPOSE 8787

# Disable authentication for Galaxy IT
ENV DISABLE_AUTH=true

CMD ["/usr/local/bin/startup.sh"]
