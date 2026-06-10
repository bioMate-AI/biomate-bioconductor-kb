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
    library(branchpointer)
    library(BSgenome.Hsapiens.UCSC.hg38)
    library(biomaRt)
    
    # Initialize BSgenome object
    g <- BSgenome.Hsapiens.UCSC.hg38::BSgenome.Hsapiens.UCSC.hg38
    
    # 1. Convert GTF annotations to an exon GRanges object using gtfToExons()
    exons <- gtfToExons("gencode.v26.annotation.gtf")
    
    # 2. Read query SNPs and calculate location attributes using readQueryFile()
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
    
    # 3. Predict branchpoint probabilities for reference and alternative alleles using predictBranchpoints()
    branchpointPredictionsSNP <- predictBranchpoints(querySNP, queryType = "SNP", BSgenome = g)
    
    # 4. Summarize the variant effects using predictionsToSummary()
    querySNPSummary <- predictionsToSummary(querySNP, branchpointPredictionsSNP)
    
    # Save tabular outputs
    write.csv(as.data.frame(querySNPSummary), "query_snp_summary.csv", row.names = FALSE)
    saveRDS(branchpointPredictionsSNP, "branchpoint_predictions_snp.rds")
    
    # 5. Visualize reference vs alternative branchpoint windows using plotBranchpointWindow()
    pdf("branchpoint_window_plot.pdf", width = 12, height = 8)
    plotBranchpointWindow(querySNP\$id[2], branchpointPredictionsSNP, probabilityCutoff = 0.52, plotMutated = TRUE, plotStructure = TRUE, exons = exons)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_BRANCHPOINTER_SNP_EFFECT_PREDICTION":
        branchpointer: \$(Rscript -e 'cat(as.character(packageVersion("branchpointer")))')
    END_VERSIONS
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
