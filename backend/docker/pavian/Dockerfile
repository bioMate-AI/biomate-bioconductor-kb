# BioMate Pavian Interactive Tool
# Metagenomics visualization (Kraken/Bracken results)
#
# Features:
# - Interactive Sankey diagrams
# - Taxonomic abundance visualization
# - Multi-sample comparison

FROM rocker/shiny:4.3

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="Pavian for Galaxy Interactive Tools"

# Install Pavian dependencies
RUN R -e "install.packages(c( \
    'remotes', 'shiny', 'shinydashboard', 'DT', \
    'htmlwidgets', 'networkD3', 'sankeyD3', \
    'dplyr', 'plyr', 'RColorBrewer' \
), repos='https://cloud.r-project.org/')"

# Install Pavian
RUN R -e "remotes::install_github('fbreitwieser/pavian')"

# Create app directory
RUN mkdir -p /srv/shiny-server/pavian
COPY app.R /srv/shiny-server/pavian/
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

# Shiny port
EXPOSE 3838

CMD ["/usr/local/bin/startup.sh"]
