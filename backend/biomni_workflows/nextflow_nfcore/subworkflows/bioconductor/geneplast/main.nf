#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geneplast — evolutionary_plasticity_analysis
// Calculate the diversity, abundance, and evolutionary plasticity index (EPI) of orthologous groups.
// Input: cogdata, sspids, cogids
// Container: quay.io/biocontainers/bioconductor-geneplast:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: geneplast
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess orthology data using gplast.preprocess
//  * 2. [Core Analysis] Run plasticity analysis using gplast
//  * 3. [Core Analysis] Retrieve results using gplast.get

nextflow.enable.dsl = 2

process BIOC_GENEPLAST_EVOLUTIONARY_PLASTICITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("geneplast")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(geneplast)
    
    # Helper function to read cogdata from the working directory
    read_cogdata <- function() {
      if (file.exists("cogdata.csv")) {
        return(read.csv("cogdata.csv", stringsAsFactors = FALSE))
      } else if (file.exists("cogdata.tsv")) {
        return(read.delim("cogdata.tsv", stringsAsFactors = FALSE))
      } else if (file.exists("cogdata.rds")) {
        return(readRDS("cogdata.rds"))
      } else if (file.exists("cogdata")) {
        out <- tryCatch({
          read.csv("cogdata", stringsAsFactors = FALSE)
        }, error = function(e) {
          tryCatch({
            readRDS("cogdata")
          }, error = function(err) {
            stop("Could not parse 'cogdata' file as CSV or RDS.")
          })
        })
        return(out)
      } else {
        stop("Required input file 'cogdata' (CSV, TSV, or RDS) not found in the working directory.")
      }
    }
    
    # Helper function to read vector files (sspids or cogids) from the working directory
    read_vector <- function(filename) {
      for (ext in c(".txt", ".csv", ".rds")) {
        full_path <- paste0(filename, ext)
        if (file.exists(full_path)) {
          if (ext == ".txt") {
            return(readLines(full_path))
          } else if (ext == ".csv") {
            return(as.character(read.csv(full_path, header = FALSE, stringsAsFactors = FALSE)[[1]]))
          } else if (ext == ".rds") {
            return(as.character(readRDS(full_path)))
          }
        }
      }
      if (file.exists(filename)) {
        out <- tryCatch({
          readLines(filename)
        }, error = function(e) {
          tryCatch({
            as.character(readRDS(filename))
          }, error = function(err) {
            stop(paste("Could not parse", filename, "as text or RDS."))
          })
        })
        return(out)
      } else {
        stop(paste("Required input file", filename, "not found in the working directory."))
      }
    }
    
    # Read user inputs
    cogdata <- read_cogdata()
    sspids <- read_vector("sspids")
    cogids <- read_vector("cogids")
    
    # 1. Preprocess orthology data using gplast.preprocess
    ogp <- gplast.preprocess(cogdata=cogdata, sspids=sspids, cogids=cogids, verbose=FALSE)
    
    # 2. Run plasticity analysis using gplast
    ogp <- gplast(ogp, verbose=FALSE)
    
    # 3. Retrieve results using gplast.get
    res <- gplast.get(ogp, what="results")
    head(res)
    
    # Write outputs to the working directory
    write.csv(res, "gplast_results.csv", row.names = TRUE)
    saveRDS(ogp, "gplast_ogp.rds")
    
    # Generate and save distribution plots of the calculated metrics
    pdf("gplast_metrics_distribution.pdf", width = 10, height = 4)
    par(mfrow = c(1, 3))
    if ("abundance" %in% colnames(res)) {
      hist(res\$abundance, main = "Abundance Distribution", xlab = "Abundance", col = "skyblue", border = "white")
    }
    if ("diversity" %in% colnames(res)) {
      hist(res\$diversity, main = "Diversity Distribution", xlab = "Diversity", col = "salmon", border = "white")
    }
    if ("plasticity" %in% colnames(res)) {
      hist(res\$plasticity, main = "Plasticity Distribution", xlab = "Plasticity Index (EPI)", col = "lightgreen", border = "white")
    }
    dev.off()

    writeLines(c(
        '"BIOC_GENEPLAST_EVOLUTIONARY_PLASTICITY_ANALYSIS":',
        paste0('    geneplast: ', as.character(packageVersion('geneplast')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_evolutionary_plasticity_analysis.csv versions.yml
    """
}

workflow BIOC_GENEPLAST_EVOLUTIONARY_PLASTICITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cogdata, sspids, cogids ] ]

    main:
    BIOC_GENEPLAST_EVOLUTIONARY_PLASTICITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENEPLAST_EVOLUTIONARY_PLASTICITY_ANALYSIS.out.tables
    plots    = BIOC_GENEPLAST_EVOLUTIONARY_PLASTICITY_ANALYSIS.out.plots
    objects  = BIOC_GENEPLAST_EVOLUTIONARY_PLASTICITY_ANALYSIS.out.objects
    versions = BIOC_GENEPLAST_EVOLUTIONARY_PLASTICITY_ANALYSIS.out.versions
}
