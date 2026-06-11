#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirTarRnaSeq — mirna_mrna_relationship_two_timepoint
// Identify significant miRNA-mRNA fold change differences between two time points compared to a background distribution.
// Input: mRNA0_5.txt.gz, miRNA0_5.txt.gz
// Container: quay.io/biocontainers/bioconductor-mirtarrnaseq:1.18.0--r45hdfd78af_0
// R packages: mirTarRnaSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: mirTarRnaSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load differential expression files for mRNA and miRNA
//  * 2. [Input & Preparation] Parse fold changes and filter mRNAs by p-value threshold using one2OneRnaMiRNA
//  * 3. [Core Analysis] Estimate miRNA-mRNA fold change differences using twoTimePoint
//  * 4. [Core Analysis] Generate a background distribution of fold change differences using twoTimePointSamp
//  * 5. [Core Analysis] Retrieve species-specific miRanda target predictions using getInputSpecies
//  * 6. [Core Analysis] Identify relationships below a p-value threshold using threshSigInter
//  * 7. [Core Analysis] Intersect significant relationships with miRanda predictions using mirandaIntersectInter
//  * 8. [Core Analysis] Format final results using finInterResult
//  * 9. [Visualization & Output] Draw fold change plots using drawInterPlots and a heatmap using mirRnaHeatmapDiff

nextflow.enable.dsl = 2

process BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("mirTarRnaSeq")
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
    library(mirTarRnaSeq)
    
    # 1. Load differential expression files for mRNA and miRNA from the working directory
    mrna_df <- read.table("mRNA0_5.txt.gz", as.is = TRUE, header = TRUE, sep = "\t")
    mirna_df <- read.table("miRNA0_5.txt.gz", as.is = TRUE, header = TRUE, sep = "\t")
    
    # Construct the named lists as expected by the package functions
    mrna_files <- list("mRNA0_5" = mrna_df)
    mirna_files <- list("miRNA0_5" = mirna_df)
    
    # 2. Parse fold changes and filter mRNAs by p-value threshold using one2OneRnaMiRNA
    mrna <- one2OneRnaMiRNA(mrna_files, pthreshold = 0.05)\$foldchanges
    mirna <- one2OneRnaMiRNA(mirna_files)\$foldchanges
    
    # 3. Estimate miRNA-mRNA fold change differences using twoTimePoint
    inter0 <- twoTimePoint(mrna, mirna)
    
    # 4. Generate a background distribution of fold change differences using twoTimePointSamp
    outs <- twoTimePointSamp(mrna, mirna, Shrounds = 10)
    
    # 5. Retrieve species-specific miRanda target predictions using getInputSpecies
    miRanda <- getInputSpecies("Mouse", threshold = 140)
    
    # 6. Identify relationships below a p-value threshold using threshSigInter
    sig_InterR <- threshSigInter(inter0, outs)
    
    # 7. Intersect significant relationships with miRanda predictions using mirandaIntersectInter
    results <- mirandaIntersectInter(sig_InterR, outs, mrna, mirna, miRanda)
    
    # 8. Format final results using finInterResult
    final_results <- finInterResult(results)
    
    # Save tabular results and R objects
    write.csv(final_results, "final_results.csv", row.names = FALSE)
    saveRDS(results, "results.rds")
    
    # 9. Draw fold change plots using drawInterPlots and a heatmap using mirRnaHeatmapDiff
    pdf("mirna_mrna_plots.pdf", width = 8, height = 8)
    par(mar = c(4, 4, 2, 1))
    drawInterPlots(mrna, mirna, final_results)
    CorRes <- results\$corrs
    mirRnaHeatmapDiff(CorRes, upper_bound = 9.9)
    dev.off()

    writeLines(c(
        '"BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT":',
        paste0('    mirTarRnaSeq: ', as.character(packageVersion('mirTarRnaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_mrna_relationship_two_timepoint.csv versions.yml
    """
}

workflow BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mRNA0_5.txt.gz, miRNA0_5.txt.gz ] ]

    main:
    BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT(ch_input)

    emit:
    tables   = BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT.out.tables
    plots    = BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT.out.plots
    objects  = BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT.out.objects
    versions = BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT.out.versions
}
