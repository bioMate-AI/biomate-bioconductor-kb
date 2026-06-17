#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CFAssay — two_way_anova_cfa
// Perform a two-way ANOVA with interaction on colony formation assay data to test for synergistic or sensitizing effects between two treatment factors.
// Input: anova_data.txt
// Container: quay.io/biocontainers/bioconductor-cfassay:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CFAssay
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and inspect the two-way experimental data
//  * 2. [Core Analysis] Fit the two-way ANOVA model with interaction
//  * 3. [Core Analysis] Print detailed ANOVA results and effect sizes
//  * 4. [Visualization & Output] Generate diagnostic plots for the experiments

nextflow.enable.dsl = 2

process BIOC_CFASSAY_TWO_WAY_ANOVA_CFA {
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
    .bm_deps <- c("CFAssay")
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
    
    # Load the required library
    library(CFAssay)
    
    # Stage 1: Load and inspect the two-way experimental data
    input_file <- "anova_data.txt"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    datatab <- read.table(input_file, header=TRUE, sep="\t")
    
    # Inspect the data structure
    names(datatab)
    head(datatab, 3)
    
    # Stage 2: Fit the two-way ANOVA model with interaction
    fitcomp <- cfa2way(datatab, A="siRNA", B="x5fuCis", param="A/B")
    
    # Stage 3: Print detailed ANOVA results and effect sizes, and save them
    print(fitcomp, labels=c(A="siRNA", B="x5fuCis"))
    
    # Save the fit object as an RDS file
    saveRDS(fitcomp, file="cfa2way_fit.rds")
    
    # Capture the printed summary to a text file
    sink("anova_summary.txt")
    print(fitcomp, labels=c(A="siRNA", B="x5fuCis"))
    sink()
    
    # Stage 4: Generate diagnostic plots for the experiments
    pdf("TwoWay_experimental_plots.pdf")
    plotExp(fitcomp, labels=c(A="siRNA", B="x5fuCis"))
    dev.off()

    writeLines(c(
        '"BIOC_CFASSAY_TWO_WAY_ANOVA_CFA":',
        paste0('    CFAssay: ', as.character(packageVersion('CFAssay')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_way_anova_cfa.csv versions.yml
    """
}

workflow BIOC_CFASSAY_TWO_WAY_ANOVA_CFA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ anova_data.txt ] ]

    main:
    BIOC_CFASSAY_TWO_WAY_ANOVA_CFA(ch_input)

    emit:
    tables   = BIOC_CFASSAY_TWO_WAY_ANOVA_CFA.out.tables
    plots    = BIOC_CFASSAY_TWO_WAY_ANOVA_CFA.out.plots
    objects  = BIOC_CFASSAY_TWO_WAY_ANOVA_CFA.out.objects
    versions = BIOC_CFASSAY_TWO_WAY_ANOVA_CFA.out.versions
}
