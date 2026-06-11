#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenVisR — loss_of_heterozygosity
// Visualize Loss of Heterozygosity (LOH) across a cohort or for a single chromosome in a single sample.
// Input: HCC1395_Germline
// Container: quay.io/biocontainers/bioconductor-genvisr:1.42.2--r45hdfd78af_0
// R packages: GenVisR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenVisR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot cohort-level LOH spectrum using lohSpec
//  * 2. [Visualization & Output] Plot single-sample LOH across a specific chromosome with an ideogram track using lohView

nextflow.enable.dsl = 2

process BIOC_GENVISR_LOSS_OF_HETEROZYGOSITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("GenVisR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(GenVisR)
    
    # 1. Read User Input
    # The pipeline expects 'HCC1395_Germline' in the working directory.
    # We check for common extensions (.csv, .tsv, .txt, .rds) or no extension.
    input_file <- NULL
    if (file.exists("HCC1395_Germline.csv")) {
      HCC1395_Germline <- read.csv("HCC1395_Germline.csv", stringsAsFactors = FALSE)
    } else if (file.exists("HCC1395_Germline.tsv")) {
      HCC1395_Germline <- read.delim("HCC1395_Germline.tsv", stringsAsFactors = FALSE)
    } else if (file.exists("HCC1395_Germline.txt")) {
      HCC1395_Germline <- read.delim("HCC1395_Germline.txt", stringsAsFactors = FALSE)
    } else if (file.exists("HCC1395_Germline.rds")) {
      HCC1395_Germline <- readRDS("HCC1395_Germline.rds")
    } else if (file.exists("HCC1395_Germline")) {
      HCC1395_Germline <- read.table("HCC1395_Germline", header = TRUE, stringsAsFactors = FALSE)
    } else {
      stop("Required input file 'HCC1395_Germline' (with .csv, .tsv, .txt, .rds extension or no extension) not found in the working directory.")
    }
    
    # 2. Plot cohort-level LOH spectrum using lohSpec
    # Save the plot to a PDF file
    pdf("lohSpec_plot.pdf", width = 11, height = 5)
    p_spec <- lohSpec(x = HCC1395_Germline)
    if (!is.null(p_spec)) {
      print(p_spec)
    }
    dev.off()
    
    # Save the lohSpec object as an RDS for downstream analysis
    saveRDS(p_spec, "lohSpec_output.rds")
    
    # 3. Plot single-sample LOH across a specific chromosome with an ideogram track using lohView
    # Save the plot to a PDF file
    pdf("lohView_plot.pdf", width = 11, height = 5)
    p_view <- lohView(HCC1395_Germline, chr = "chr5", genome = "hg19", ideogram_txtSize = 4)
    if (!is.null(p_view)) {
      print(p_view)
    }
    dev.off()
    
    # Save the lohView object as an RDS for downstream analysis
    saveRDS(p_view, "lohView_output.rds")

    writeLines(c(
        '"BIOC_GENVISR_LOSS_OF_HETEROZYGOSITY":',
        paste0('    GenVisR: ', as.character(packageVersion('GenVisR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_loss_of_heterozygosity.csv versions.yml
    """
}

workflow BIOC_GENVISR_LOSS_OF_HETEROZYGOSITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HCC1395_Germline ] ]

    main:
    BIOC_GENVISR_LOSS_OF_HETEROZYGOSITY(ch_input)

    emit:
    tables   = BIOC_GENVISR_LOSS_OF_HETEROZYGOSITY.out.tables
    plots    = BIOC_GENVISR_LOSS_OF_HETEROZYGOSITY.out.plots
    objects  = BIOC_GENVISR_LOSS_OF_HETEROZYGOSITY.out.objects
    versions = BIOC_GENVISR_LOSS_OF_HETEROZYGOSITY.out.versions
}
