FROM rocker/tidyverse:4.3.1

# Pre-install PKNCA and rmarkdown so NCA_PKNCA_ANALYSIS doesn't install at runtime
RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    install.packages(c('PKNCA', 'rmarkdown', 'knitr', 'DT', 'plotly', 'nlme'), \
        dependencies = TRUE, quiet = TRUE) \
"

# Verify
RUN Rscript -e "library(PKNCA); cat('PKNCA', as.character(packageVersion('PKNCA')), 'OK\n')"

WORKDIR /data
