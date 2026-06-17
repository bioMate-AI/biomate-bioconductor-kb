#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RRHO — compare_two_lists
// Compare two ranked lists of genes to identify and visualize statistically significant overlap patterns with FDR and FWER corrections.
// Input: gene.list1, gene.list2
// Container: quay.io/biocontainers/bioconductor-rrho:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RRHO, lattice
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute overlap and significance using RRHO
//  * 2. [Visualization & Output] Visualize nominal p-values using lattice::levelplot
//  * 3. [Core Analysis] Compute FWER-corrected p-values using pvalRRHO
//  * 4. [Visualization & Output] Plot the empirical cumulative distribution function (ECDF) of the minimum p-values
//  * 5. [Visualization & Output] Visualize B-Y corrected p-values using lattice::levelplot

nextflow.enable.dsl = 2

process BIOC_RRHO_COMPARE_TWO_LISTS {
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
    .bm_deps <- c("RRHO", "lattice")
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
    library(RRHO)
    library(lattice)
    
    # 1. Read User Input Files
    # The pipeline reads exactly these files from the working directory:
    # - gene.list1 (data frame with gene identifiers and ranking values)
    # - gene.list2 (data frame with gene identifiers and ranking values)
    gene.list1 <- read.table("gene.list1", header=TRUE, stringsAsFactors=FALSE)
    gene.list2 <- read.table("gene.list2", header=TRUE, stringsAsFactors=FALSE)
    
    # 2. Compute overlap and significance using RRHO
    RRHO.example <- RRHO(gene.list1, gene.list2, 
                         BY=TRUE, alternative='enrichment')
    
    # 3. Compute FWER corrected p-values using 50 random permutations
    pval.testing <- pvalRRHO(RRHO.example, 50)
    fwer_pval <- pval.testing\$pval
    
    # 4. Generate and save plots to PDF
    pdf("rrho_plots.pdf", width=7, height=7)
    
    # Stage 2: Visualize Nominal (-log) p-values
    # Note: levelplot is a lattice function, so we use print() to ensure it renders in the PDF device
    print(lattice::levelplot(RRHO.example\$hypermat, main="Nominal (-log) P-values"))
    
    # Stage 4: Plot the empirical cumulative distribution function (ECDF) of the minimum p-values
    xs <- seq(0, 10, length=100)
    plot(Vectorize(pval.testing\$FUN.ecdf)(xs)~xs, 
         xlab='-log(pvalue)', ylab='ECDF', type='S',
         main="ECDF of Minimum Nominal P-values")
    
    # Stage 5: Visualize B-Y corrected p-values
    print(lattice::levelplot(RRHO.example\$hypermat.by, main="B-Y Corrected P-values"))
    
    dev.off()
    
    # 5. Write output files
    # Save the main RRHO and permutation testing objects
    saveRDS(RRHO.example, "rrho_results.rds")
    saveRDS(pval.testing, "rrho_pval_testing.rds")
    
    # Save the matrices as CSV files
    write.csv(as.data.frame(RRHO.example\$hypermat), "rrho_hypermat_nominal.csv", row.names=TRUE)
    write.csv(as.data.frame(RRHO.example\$hypermat.by), "rrho_hypermat_by_corrected.csv", row.names=TRUE)
    
    # Save a summary text file with the FWER p-value
    summary_df <- data.frame(
      Metric = "FWER_corrected_pvalue",
      Value = fwer_pval,
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, "rrho_summary.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_RRHO_COMPARE_TWO_LISTS":',
        paste0('    RRHO: ', as.character(packageVersion('RRHO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_two_lists.csv versions.yml
    """
}

workflow BIOC_RRHO_COMPARE_TWO_LISTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene.list1, gene.list2 ] ]

    main:
    BIOC_RRHO_COMPARE_TWO_LISTS(ch_input)

    emit:
    tables   = BIOC_RRHO_COMPARE_TWO_LISTS.out.tables
    plots    = BIOC_RRHO_COMPARE_TWO_LISTS.out.plots
    objects  = BIOC_RRHO_COMPARE_TWO_LISTS.out.objects
    versions = BIOC_RRHO_COMPARE_TWO_LISTS.out.versions
}
