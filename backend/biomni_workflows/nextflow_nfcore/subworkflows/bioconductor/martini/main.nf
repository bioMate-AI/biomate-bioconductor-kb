#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: martini — gwas_network_association
// Find connected explanatory SNPs (ConES) using GWAS data and a SNP network.
// Input: minigwas, minisnpMapping, minippi
// Container: quay.io/biocontainers/bioconductor-martini:1.30.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: martini, snpStats
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package
//  * 2. [Input & Preparation] Create genomic structure (GS), gene-membership (GM), or gene-interaction (GI) networks
//  * 3. [Core Analysis] Run SConES with grid search cross-validation
//  * 4. [Core Analysis] Inspect the selected explanatory SNPs

nextflow.enable.dsl = 2

process BIOC_MARTINI_GWAS_NETWORK_ASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("martini", "snpStats")
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
    
    # 1. Load the packages
    library(martini)
    library(snpStats) # Required for SnpMatrix class handling
    
    # Load user input files from the working directory
    if (file.exists("minigwas.rds")) {
      minigwas <- readRDS("minigwas.rds")
    } else {
      stop("Error: minigwas.rds not found in the working directory.")
    }
    
    if (file.exists("minisnpMapping.rds")) {
      minisnpMapping <- readRDS("minisnpMapping.rds")
    } else if (file.exists("minisnpMapping.csv")) {
      minisnpMapping <- read.csv("minisnpMapping.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: minisnpMapping (RDS or CSV) not found in the working directory.")
    }
    
    if (file.exists("minippi.rds")) {
      minippi <- readRDS("minippi.rds")
    } else if (file.exists("minippi.csv")) {
      minippi <- read.csv("minippi.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: minippi (RDS or CSV) not found in the working directory.")
    }
    
    # 2. Create genomic structure (GS), gene-membership (GM), or gene-interaction (GI) networks
    message("Creating GS network...")
    gs <- get_GS_network(minigwas)
    
    message("Creating GM network...")
    gm <- get_GM_network(minigwas, snpMapping = minisnpMapping)
    
    message("Creating GI network...")
    gi <- get_GI_network(minigwas, snpMapping = minisnpMapping, ppi = minippi)
    
    # Save networks to RDS
    saveRDS(gs, "gs_network.rds")
    saveRDS(gm, "gm_network.rds")
    saveRDS(gi, "gi_network.rds")
    
    # Plot networks to PDF
    pdf("networks_plots.pdf", width = 8, height = 8)
    par(mar = c(0, 0, 0, 0) + 0.1)
    plot(gs)
    title("GS Network", line = -2)
    plot(gm)
    title("GM Network", line = -2)
    plot(gi)
    title("GI Network", line = -2)
    dev.off()
    
    # 3. Run SConES with grid search cross-validation
    message("Running SConES cross-validation...")
    cones <- scones.cv(minigwas, gi)
    
    # 4. Inspect the selected explanatory SNPs
    message("Inspecting selected explanatory SNPs:")
    print(head(cones))
    
    # Save results
    write.csv(as.data.frame(cones), "cones_results.csv", row.names = FALSE)
    saveRDS(cones, "cones_results.rds")
    
    message("Pipeline completed successfully. Outputs saved to 'cones_results.csv', 'cones_results.rds', 'networks_plots.pdf', and network RDS files.")

    writeLines(c(
        '"BIOC_MARTINI_GWAS_NETWORK_ASSOCIATION":',
        paste0('    martini: ', as.character(packageVersion('martini')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwas_network_association.csv versions.yml
    """
}

workflow BIOC_MARTINI_GWAS_NETWORK_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ minigwas, minisnpMapping, minippi ] ]

    main:
    BIOC_MARTINI_GWAS_NETWORK_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_MARTINI_GWAS_NETWORK_ASSOCIATION.out.tables
    plots    = BIOC_MARTINI_GWAS_NETWORK_ASSOCIATION.out.plots
    objects  = BIOC_MARTINI_GWAS_NETWORK_ASSOCIATION.out.objects
    versions = BIOC_MARTINI_GWAS_NETWORK_ASSOCIATION.out.versions
}
