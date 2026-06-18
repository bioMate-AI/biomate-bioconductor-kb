#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: branchpointer — snp_effect_prediction
// Evaluate the in silico effects of single nucleotide polymorphisms (SNPs) on branchpoint architecture.
// Input: gencode.v26.annotation.gtf, SNP_example.txt
// Container: quay.io/biocontainers/bioconductor-branchpointer:1.32.0--r44hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, biomaRt, branchpointer
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-branchpointer:1.32.0--r44hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "biomaRt", "branchpointer")
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
    library(branchpointer)
    library(BSgenome.Hsapiens.UCSC.hg38)
    library(biomaRt)
    
    # Initialize BSgenome object
    g <- BSgenome.Hsapiens.UCSC.hg38::BSgenome.Hsapiens.UCSC.hg38
    
    # --- Convert GTF annotations to an exon GRanges object using ---
    exons <- gtfToExons("gencode.v26.annotation.gtf")
    
    # --- Read query SNPs and calculate location attributes using ---
    querySNPFile <- "SNP_example.txt"
    querySNP <- readQueryFile(querySNPFile, queryType = "SNP", exons = exons, filter = TRUE)
    
    # Fetch SNP attributes from BioMart using makeBranchpointWindowForSNP()
    # Wrapped in a tryCatch to ensure robustness if biomaRt services are down,
    # falling back to the querySNP object loaded from the user's file.
    tryCatch({
      mart <- useMart("ENSEMBL_MART_SNP", dataset="hsapiens_snp", host="www.ensembl.org")
      querySNP <- makeBranchpointWindowForSNP(c("rs587776767","rs786205083"), mart.snp = mart, exons = exons, filter  = FALSE)
    }, error = function(e) {
      message("BioMart query failed or timed out. Proceeding with query SNPs loaded from SNP_example.txt.")
    })
    
    # --- Predict branchpoint probabilities for reference and ---
    branchpointPredictionsSNP <- predictBranchpoints(querySNP, queryType = "SNP", BSgenome = g)
    
    # --- Summarize the variant effects using predictionsToSummary() ---
    querySNPSummary <- predictionsToSummary(querySNP, branchpointPredictionsSNP)
    
    # Save tabular outputs
    write.csv(as.data.frame(querySNPSummary), "query_snp_summary.csv", row.names = FALSE)
    saveRDS(branchpointPredictionsSNP, "branchpoint_predictions_snp.rds")
    
    # --- Visualize reference vs alternative branchpoint windows ---
    pdf("branchpoint_window_plot.pdf", width = 12, height = 8)
    plotBranchpointWindow(querySNP\$id[2], branchpointPredictionsSNP, probabilityCutoff = 0.52, plotMutated = TRUE, plotStructure = TRUE, exons = exons)
    dev.off()

    writeLines(c(
        '"BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION":',
        paste0('        branchpointer: ', as.character(packageVersion("branchpointer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_effect_prediction.csv versions.yml
    """
}

workflow BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gencode.v26.annotation.gtf, SNP_example.txt ] ]

    main:
    BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION(ch_input)

    emit:
    tables   = BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION.out.tables
    plots    = BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION.out.plots
    objects  = BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION.out.objects
    versions = BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION.out.versions
}
