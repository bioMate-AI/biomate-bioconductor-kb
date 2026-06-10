#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: branchpointer — snp_effect_evaluation
// Evaluate the functional effects of SNPs on branchpoint architecture and probabilities.
// Input: gencode.v26.annotation.gtf, SNP_example.txt
// Container: quay.io/biocontainers/bioconductor-branchpointer:1.32.0--r44hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, branchpointer
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg38, branchpointer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Convert GTF annotations to an exon GRanges object using gtfToExons() 2. Read query SNPs using readQueryFile() or retrieve SNP coor

nextflow.enable.dsl = 2

process BIOC_BRANCHPOINTER_SNP_EFFECT_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "branchpointer")
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
    
    # Define input file paths from the working directory
    gtfFile <- "gencode.v26.annotation.gtf"
    querySNPFile <- "SNP_example.txt"
    
    # 1. Convert GTF annotations to an exon GRanges object
    exons <- gtfToExons(gtfFile)
    
    # 2. Read query SNPs from the user-provided file
    querySNP <- readQueryFile(querySNPFile, 
                              queryType = "SNP", 
                              exons = exons, 
                              filter = TRUE)
    
    # Load the BSgenome object
    g <- BSgenome.Hsapiens.UCSC.hg38::BSgenome.Hsapiens.UCSC.hg38
    
    # 3. Predict branchpoint probabilities for reference and alternative alleles
    branchpointPredictionsSNP <- predictBranchpoints(querySNP,
                                            queryType = "SNP",
                                            BSgenome = g)
    
    # 4. Summarize the variant effects
    querySNPSummary <- predictionsToSummary(querySNP,branchpointPredictionsSNP)
    
    # 5. Visualize and compare reference vs. alternative branchpoint windows
    pdf("branchpoint_window_plot.pdf", width = 12, height = 8)
    plotBranchpointWindow(querySNP\$id[1], 
                          branchpointPredictionsSNP,
                          probabilityCutoff = 0.52,
                          plotMutated = TRUE,
                          plotStructure = TRUE,
                          exons = exons)
    dev.off()
    
    # Save outputs to the working directory
    saveRDS(branchpointPredictionsSNP, "branchpointPredictionsSNP.rds")
    saveRDS(querySNPSummary, "querySNPSummary.rds")
    
    write.csv(as.data.frame(branchpointPredictionsSNP), "branchpointPredictionsSNP.csv", row.names = FALSE)
    write.csv(as.data.frame(querySNPSummary), "querySNPSummary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_BRANCHPOINTER_SNP_EFFECT_EVALUATION":',
        paste0('    branchpointer: ', as.character(packageVersion('branchpointer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_effect_evaluation.csv versions.yml
    """
}

workflow BIOC_BRANCHPOINTER_SNP_EFFECT_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gencode.v26.annotation.gtf, SNP_example.txt ] ]

    main:
    BIOC_BRANCHPOINTER_SNP_EFFECT_EVALUATION(ch_input)

    emit:
    tables   = BIOC_BRANCHPOINTER_SNP_EFFECT_EVALUATION.out.tables
    plots    = BIOC_BRANCHPOINTER_SNP_EFFECT_EVALUATION.out.plots
    objects  = BIOC_BRANCHPOINTER_SNP_EFFECT_EVALUATION.out.objects
    versions = BIOC_BRANCHPOINTER_SNP_EFFECT_EVALUATION.out.versions
}
