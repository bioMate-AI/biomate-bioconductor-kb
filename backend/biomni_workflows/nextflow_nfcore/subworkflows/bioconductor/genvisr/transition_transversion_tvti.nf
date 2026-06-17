#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenVisR — transition_transversion_tvti
// Visualize the proportions or frequencies of transition and transversion mutation types across a cohort.
// Input: brcaMAF
// Container: quay.io/biocontainers/bioconductor-genvisr:1.42.2--r45hdfd78af_0
// R packages: GenVisR, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: GenVisR, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load mutation data
//  * 2. [Visualization & Output] Generate the TvTi plot showing proportions or frequencies
//  * 3. [Core Analysis] Optionally overlay apriori expectations

nextflow.enable.dsl = 2

process BIOC_GENVISR_TRANSITION_TRANSVERSION_TVTI {
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
    .bm_deps <- c("GenVisR", "ggplot2")
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
    library(GenVisR)
    library(ggplot2)
    
    # ==========================================
    # 1. Load mutation data
    # ==========================================
    # The pipeline reads EXACTLY 'brcaMAF' from the working directory.
    # We support RDS, TSV, or a generic file named 'brcaMAF'.
    if (file.exists("brcaMAF.rds")) {
      brcaMAF <- readRDS("brcaMAF.rds")
    } else if (file.exists("brcaMAF.tsv")) {
      brcaMAF <- read.delim("brcaMAF.tsv", header=TRUE, sep="\t", stringsAsFactors=FALSE)
    } else if (file.exists("brcaMAF")) {
      brcaMAF <- tryCatch({
        readRDS("brcaMAF")
      }, error = function(e) {
        read.delim("brcaMAF", header=TRUE, sep="\t", stringsAsFactors=FALSE)
      })
    } else {
      stop("Required input file 'brcaMAF' (or brcaMAF.rds/brcaMAF.tsv) not found in the working directory.")
    }
    
    # ==========================================
    # 2. Generate the TvTi plot showing proportions or frequencies
    # ==========================================
    
    # Call 1: Default proportions
    pdf("TvTi_proportions_default.pdf", width=11, height=5.5)
    p1 <- TvTi(brcaMAF, lab_txtAngle=75, fileType="MAF")
    print(p1)
    dev.off()
    
    # Call 2: Frequencies with custom palette
    pdf("TvTi_frequencies_custom_colors.pdf", width=11, height=5.5)
    p2 <- TvTi(brcaMAF, type = "Frequency", palette = c("#77C55D", "#A461B4", "#C1524B", "#93B5BB", "#4F433F", "#BFA753"), lab_txtAngle = 75, fileType = "MAF")
    print(p2)
    dev.off()
    
    # ==========================================
    # 3. Overlay apriori expectations
    # ==========================================
    
    # Define apriori expectations
    expec <- c(`A->C or T->G (TV)` = 0.066, `A->G or T->C (TI)` = 0.217, `A->T or T->A (TV)` = 0.065, `G->A or C->T (TI)` = 0.4945, `G->C or C->G (TV)` = 0.0645, `G->T or C->A (TV)` = 0.093)
    
    # Call 3: Proportions with expectations
    pdf("TvTi_proportions_with_expectations.pdf", width=11, height=5.5)
    p3 <- TvTi(brcaMAF, y = expec, lab_txtAngle = 45, fileType = "MAF")
    print(p3)
    dev.off()
    
    # Save the expectations vector as an RDS for reference
    saveRDS(expec, "apriori_expectations.rds")
    
    message("TvTi pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GENVISR_TRANSITION_TRANSVERSION_TVTI":',
        paste0('    GenVisR: ', as.character(packageVersion('GenVisR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transition_transversion_tvti.csv versions.yml
    """
}

workflow BIOC_GENVISR_TRANSITION_TRANSVERSION_TVTI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brcaMAF ] ]

    main:
    BIOC_GENVISR_TRANSITION_TRANSVERSION_TVTI(ch_input)

    emit:
    tables   = BIOC_GENVISR_TRANSITION_TRANSVERSION_TVTI.out.tables
    plots    = BIOC_GENVISR_TRANSITION_TRANSVERSION_TVTI.out.plots
    objects  = BIOC_GENVISR_TRANSITION_TRANSVERSION_TVTI.out.objects
    versions = BIOC_GENVISR_TRANSITION_TRANSVERSION_TVTI.out.versions
}
