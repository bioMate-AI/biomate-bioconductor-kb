#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cpvSNP — vegas_analysis
// Perform gene set analysis on correlated SNP p-values using the VEGAS method, accounting for linkage disequilibrium (LD).
// Input: arrayData.csv, gene_sets.gmt, ld_matrix.rds
// Container: quay.io/biocontainers/bioconductor-cpvsnp:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, TxDb.Hsapiens.UCSC.hg19.knownGene, cpvSNP
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read user input files
//  * 2. [Core Analysis] Convert GWAS data frame to a GRanges object
//  * 3. [Core Analysis] Map gene IDs in the GeneSetCollection to SNP IDs
//  * 4. [Core Analysis] Run VEGAS
//  * 5. [Core Analysis] Extract results
//  * 6. [Core Analysis] Write outputs
//  * 7. [Core Analysis] Generate visualization plot

nextflow.enable.dsl = 2

process BIOC_CPVSNP_VEGAS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("cpvSNP", "GSEABase", "TxDb.Hsapiens.UCSC.hg19.knownGene")
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
        library(cpvSNP)
        library(GSEABase)
        library(TxDb.Hsapiens.UCSC.hg19.knownGene)
        
        # --- Read user input files ---
        arrayData_df <- read.csv("arrayData.csv", stringsAsFactors = FALSE)
        geneSets <- getGmt("gene_sets.gmt")
        ldMat <- readRDS("ld_matrix.rds")
        
        # --- Convert GWAS data frame to a GRanges object ---
        arrayDataGR <- createArrayData(arrayData_df, positionName="Position")
        
        # --- Map gene IDs in the GeneSetCollection to SNP IDs ---
        txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
        genesHg19 <- genes(txdb)
        snpsGSC <- geneToSNPList(geneSets, arrayDataGR, genesHg19)
        
        # --- Run VEGAS ---
        vRes <- vegas(snpsGSC, arrayDataGR, ldMat)
        
        # --- Extract results ---
        p_val <- pValue(vRes)
        df <- degreesOfFreedom(vRes)
        stat <- statistic(vRes)
        
        # --- Write outputs ---
        results_df <- data.frame(
          GeneSet = names(p_val),
          PValue = unlist(p_val),
          DegreesOfFreedom = unlist(df),
          Statistic = unlist(stat),
          stringsAsFactors = FALSE
        )
        
        write.csv(results_df, "vegas_results.csv", row.names = FALSE)
        saveRDS(vRes, "vegas_results.rds")
        
        # --- Generate visualization plot ---
        pdf("vegas_pval_plot.pdf")
        pvals <- arrayDataGR\$P
        names(pvals) <- arrayDataGR\$SNP
        assocPvalBySetPlot(pvals, snpsGSC[[1]])
        dev.off()

    writeLines(c(
        '"BIOC_CPVSNP_VEGAS_ANALYSIS":',
        paste0('    cpvSNP: ', as.character(packageVersion('cpvSNP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vegas_analysis.csv versions.yml
    """
}

workflow BIOC_CPVSNP_VEGAS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ arrayData.csv, gene_sets.gmt, ld_matrix.rds ] ]

    main:
    BIOC_CPVSNP_VEGAS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CPVSNP_VEGAS_ANALYSIS.out.tables
    plots    = BIOC_CPVSNP_VEGAS_ANALYSIS.out.plots
    objects  = BIOC_CPVSNP_VEGAS_ANALYSIS.out.objects
    versions = BIOC_CPVSNP_VEGAS_ANALYSIS.out.versions
}
