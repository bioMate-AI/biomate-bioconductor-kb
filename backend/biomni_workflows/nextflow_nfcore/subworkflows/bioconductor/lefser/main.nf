#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lefser — metagenomic_biomarker_discovery
// Identify metagenomic biomarkers from taxonomic count data using relative abundance and terminal nodes.
// Input: SummarizedExperiment object containing taxonomic count data in assays and class/subclass metadata in colData.
// Container: quay.io/biocontainers/bioconductor-lefser:1.20.2--r45hdfd78af_0
// R packages: lefser, phyloseq, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, lefser
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter non-terminal nodes to avoid collinearity using get_terminal_nodes
//  * 2. [Core Analysis] Convert counts to relative abundances using relativeAb
//  * 3. [Core Analysis] Run the LEfSe analysis using lefser with a set seed for reproducibility
//  * 4. [Visualization & Output] Visualize the biomarker discovery results using lefserPlot

nextflow.enable.dsl = 2

process BIOC_LEFSER_METAGENOMIC_BIOMARKER_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("lefser", "phyloseq", "SummarizedExperiment")
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
        
    # Load required libraries
    library(lefser)
    
    library(SummarizedExperiment)
    # Define input file path (expected in the working directory)
    input_file <- "taxonomic_counts_se.rds"
    
    # Check if input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the SummarizedExperiment object containing taxonomic count data
    se <- readRDS(input_file)
    
    # 1. Filter non-terminal nodes to avoid collinearity using get_terminal_nodes
    tn <- get_terminal_nodes(rownames(se))
    setn <- se[tn,]
    
    # 2. Convert counts to relative abundances using relativeAb
    setn_ra <- relativeAb(setn)
    
    # 3. Run the LEfSe analysis using lefser with a set seed for reproducibility
    set.seed(1234)
    
    # Dynamically assign class and subclass columns based on the user's colData
    class_col <- colnames(colData(se))[1]
    
    if (ncol(colData(se)) > 1) {
      subclass_col <- colnames(colData(se))[2]
      res <- lefser(setn_ra, # relative abundance only with terminal nodes
                    classCol = class_col,
                    subclassCol = subclass_col)
    } else {
      res <- lefser(setn_ra, # relative abundance only with terminal nodes
                    classCol = class_col)
    }
    
    # Print head of results to standard output
    print(head(res))
    
    # Save tabular results to disk
    write.csv(res, "lefser_results.csv", row.names = FALSE)
    saveRDS(res, "lefser_results.rds")
    
    # 4. Visualize the biomarker discovery results using lefserPlot and save to PDF
    pdf("lefser_plot_default.pdf", width = 10, height = 8)
    print(lefserPlot(res))
    dev.off()
    
    pdf("lefser_plot_italic.pdf", width = 10, height = 8)
    print(lefserPlot(res, label.font.face = "italic"))
    dev.off()
    
    pdf("lefser_plot_red.pdf", width = 10, height = 8)
    print(lefserPlot(res, label.font.color = "red"))
    dev.off()

    writeLines(c(
        '"BIOC_LEFSER_METAGENOMIC_BIOMARKER_DISCOVERY":',
        paste0('    lefser: ', as.character(packageVersion('lefser')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metagenomic_biomarker_discovery.csv versions.yml
    """
}

workflow BIOC_LEFSER_METAGENOMIC_BIOMARKER_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment object containing taxonomic count data in assays and class/subclass metadata in colData. ] ]

    main:
    BIOC_LEFSER_METAGENOMIC_BIOMARKER_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_LEFSER_METAGENOMIC_BIOMARKER_DISCOVERY.out.tables
    plots    = BIOC_LEFSER_METAGENOMIC_BIOMARKER_DISCOVERY.out.plots
    objects  = BIOC_LEFSER_METAGENOMIC_BIOMARKER_DISCOVERY.out.objects
    versions = BIOC_LEFSER_METAGENOMIC_BIOMARKER_DISCOVERY.out.versions
}
