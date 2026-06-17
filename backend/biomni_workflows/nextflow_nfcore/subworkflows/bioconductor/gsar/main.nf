#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSAR — microarray_gsa
// Perform self-contained gene set analysis on microarray expression data to test for differences in distribution, mean, variance, or correlation structure, and vi
// Input: p53DataSet, c2.pathways, group.label
// Container: quay.io/biocontainers/bioconductor-gsar:1.44.0--r45hdfd78af_0
// R packages: ALL, Biobase, GSAR, GSEABase, gsvadata, MASS
// Bioconductor: 3.20 | R: 4.4
// Requires: GSAR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files from the working directory
//  * 2. [Visualization & Output] Execute the documented workflow exactly as specified
//  * 3. [Visualization & Output] Write output files

nextflow.enable.dsl = 2

process BIOC_GSAR_MICROARRAY_GSA {
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
    .bm_deps <- c("ALL", "Biobase", "GSAR", "GSEABase", "gsvadata", "MASS")
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
    library(GSAR)
    
    # --- Read user input files from the working directory ---
    if (file.exists("p53DataSet.rds")) {
      p53DataSet <- readRDS("p53DataSet.rds")
    } else if (file.exists("p53DataSet.csv")) {
      p53DataSet <- as.matrix(read.csv("p53DataSet.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: p53DataSet file not found (expected p53DataSet.rds or p53DataSet.csv)")
    }
    
    if (file.exists("c2.pathways.rds")) {
      c2.pathways <- readRDS("c2.pathways.rds")
    } else {
      stop("Error: c2.pathways file not found (expected c2.pathways.rds)")
    }
    
    if (file.exists("group.label.rds")) {
      group.label <- readRDS("group.label.rds")
    } else if (file.exists("group.label.txt")) {
      group.label <- as.numeric(readLines("group.label.txt"))
    } else {
      stop("Error: group.label file not found (expected group.label.rds or group.label.txt)")
    }
    
    # --- Execute the documented workflow exactly as specified ---
    # Intersect all pathway genes with dataset row names to avoid NAs
    c2.pathways <- lapply(c2.pathways, intersect, rownames(p53DataSet))
    
    # Define path.index and pathway.name dynamically based on user input
    path.index <- 1
    pathway.name <- names(c2.pathways)[path.index]
    
    target.pathway <- p53DataSet[c2.pathways[[path.index]],]
    
    WW_pvalue <- WWtest(target.pathway, group.label)
    KS_pvalue <- KStest(target.pathway, group.label)
    MD_pvalue <- MDtest(target.pathway, group.label)
    AD_pvalue <- ADtest(target.pathway, group.label)
    CVM_pvalue <- CVMtest(target.pathway, group.label)
    RKS_pvalue <- RKStest(target.pathway, group.label)
    RMD_pvalue <- RMDtest(target.pathway, group.label)
    RAD_pvalue <- RADtest(target.pathway, group.label)
    RCVM_pvalue <- RCVMtest(target.pathway, group.label)
    F_pvalue <- AggrFtest(target.pathway, group.label)
    GSNCA_pvalue <- GSNCAtest(target.pathway, group.label)
    
    # Plot the MST2 correlation network and save to PDF
    pdf("MST2_plot.pdf", width = 10, height = 8)
    plotMST2.pathway(object=target.pathway, group=group.label, name=pathway.name, legend.size=1.2, leg.x=-1.2, leg.y=2, label.size=1, label.dist=0.8, cor.method="pearson")
    dev.off()
    
    # Run GSA on multiple gene sets sequentially
    # Use head() to dynamically determine the number of pathways to test and avoid out-of-bounds errors
    results <- TestGeneSets(object=p53DataSet, group=group.label, geneSets=head(c2.pathways, 3), min.size=10, max.size=100, test="GSNCAtest")
    
    # --- Write output files ---
    # Save individual test p-values
    pvalues_df <- data.frame(
      Test = c("WWtest", "KStest", "MDtest", "ADtest", "CVMtest", "RKStest", "RMDtest", "RADtest", "RCVMtest", "AggrFtest", "GSNCAtest"),
      P_Value = c(WW_pvalue, KS_pvalue, MD_pvalue, AD_pvalue, CVM_pvalue, RKS_pvalue, RMD_pvalue, RAD_pvalue, RCVM_pvalue, F_pvalue, GSNCA_pvalue)
    )
    write.csv(pvalues_df, "individual_pvalues.csv", row.names = FALSE)
    
    # Save TestGeneSets results
    saveRDS(results, "test_gene_sets_results.rds")
    results_df <- data.frame(
      GeneSet = names(results),
      P_Value = unlist(results)
    )
    write.csv(results_df, "test_gene_sets_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GSAR_MICROARRAY_GSA":',
        paste0('    GSAR: ', as.character(packageVersion('GSAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_gsa.csv versions.yml
    """
}

workflow BIOC_GSAR_MICROARRAY_GSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ p53DataSet, c2.pathways, group.label ] ]

    main:
    BIOC_GSAR_MICROARRAY_GSA(ch_input)

    emit:
    tables   = BIOC_GSAR_MICROARRAY_GSA.out.tables
    plots    = BIOC_GSAR_MICROARRAY_GSA.out.plots
    objects  = BIOC_GSAR_MICROARRAY_GSA.out.objects
    versions = BIOC_GSAR_MICROARRAY_GSA.out.versions
}
