#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cpvSNP — glossi_analysis
// Perform gene set analysis on independent (LD-pruned) SNP p-values using the GLOSSI method.
// Input: arrayData.csv, gene_sets.gmt, independent_snps.txt
// Container: quay.io/biocontainers/bioconductor-cpvsnp:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, TxDb.Hsapiens.UCSC.hg19.knownGene, cpvSNP
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files from the working directory
//  * 2. [Visualization & Output] Convert GWAS data frame to a GRanges object using
//  * 3. [Visualization & Output] Map gene IDs in the GeneSetCollection to SNP IDs using
//  * 4. [Visualization & Output] Subset the GWAS GRanges to independent SNPs and extract
//  * 5. [Visualization & Output] Run GLOSSI using glossi
//  * 6. [Visualization & Output] Extract results using pValue, degreesOfFreedom, and
//  * 7. [Visualization & Output] Visualize results using plotPvals and save to a PDF file

nextflow.enable.dsl = 2

process BIOC_CPVSNP_GLOSSI_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    
    # --- Read user input files from the working directory ---
    arrayData <- read.csv("arrayData.csv", stringsAsFactors = FALSE)
    geneSets <- getGmt("gene_sets.gmt")
    indep <- read.table("independent_snps.txt", header = FALSE, stringsAsFactors = FALSE)
    
    # --- Convert GWAS data frame to a GRanges object using ---
    arrayDataGR <- createArrayData(arrayData, positionName = "Position")
    
    # --- Map gene IDs in the GeneSetCollection to SNP IDs using ---
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    genesHg19 <- genes(txdb)
    snpsGSC <- geneToSNPList(geneSets, arrayDataGR, genesHg19)
    
    # --- Subset the GWAS GRanges to independent SNPs and extract ---
    pvals <- arrayDataGR\$P[is.element(arrayDataGR\$SNP, indep\$V1)]
    names(pvals) <- arrayDataGR\$SNP[is.element(arrayDataGR\$SNP, indep\$V1)]
    
    # --- Run GLOSSI using glossi ---
    gRes <- glossi(pvals, snpsGSC)
    
    # --- Extract results using pValue, degreesOfFreedom, and ---
    p_values <- pValue(gRes)
    dfs <- degreesOfFreedom(gRes)
    stats <- statistic(gRes)
    
    # Create a summary data frame and write to a CSV file
    results_df <- data.frame(
      GeneSet = names(p_values),
      PValue = unlist(p_values),
      DegreesOfFreedom = unlist(dfs),
      Statistic = unlist(stats),
      row.names = NULL,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "glossi_results.csv", row.names = FALSE)
    
    # Save the GLOSSIResultCollection object as an RDS file
    saveRDS(gRes, "glossi_results.rds")
    
    # --- Visualize results using plotPvals and save to a PDF file ---
    pdf("glossi_pvals_plot.pdf")
    plotPvals(gRes, main = "GLOSSI P-values")
    dev.off()

    writeLines(c(
        '"BIOC_CPVSNP_GLOSSI_ANALYSIS":',
        paste0('    cpvSNP: ', as.character(packageVersion('cpvSNP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_glossi_analysis.csv versions.yml
    """
}

workflow BIOC_CPVSNP_GLOSSI_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ arrayData.csv, gene_sets.gmt, independent_snps.txt ] ]

    main:
    BIOC_CPVSNP_GLOSSI_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CPVSNP_GLOSSI_ANALYSIS.out.tables
    plots    = BIOC_CPVSNP_GLOSSI_ANALYSIS.out.plots
    objects  = BIOC_CPVSNP_GLOSSI_ANALYSIS.out.objects
    versions = BIOC_CPVSNP_GLOSSI_ANALYSIS.out.versions
}
