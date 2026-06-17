#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprViz — compare_multiple_guidesets
// Compare gRNA target distributions and PAM sites across different nucleases for the same genomic region.
// Input: List of GuideSet objects, GRangesList, BSgenome
// Container: quay.io/biocontainers/bioconductor-crisprviz:1.12.0--r45hdfd78af_0
// R packages: BSgenome, crisprDesign, crisprViz
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, crisprDesign, crisprViz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load GuideSets for different nucleases (e.g., SpCas9 and AsCas12a) targeting the same region
//  * 2. [Visualization & Output] Plot and compare the GuideSets side-by-side, including a GC content track

nextflow.enable.dsl = 2

process BIOC_CRISPRVIZ_COMPARE_MULTIPLE_GUIDESETS {
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
    .bm_deps <- c("BSgenome", "crisprDesign", "crisprViz")
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
    library(BSgenome)
    library(crisprDesign)
    library(crisprViz)
    
    # Define input file paths
    cas9_file <- "cas9GuideSet.rds"
    cas12a_file <- "cas12aGuideSet.rds"
    genemodel_file <- "ltn1GeneModel.rds"
    bsgenome_file <- "bsgenome.rds"
    
    # Verify existence of user input files
    if (!file.exists(cas9_file) || !file.exists(cas12a_file) || !file.exists(genemodel_file) || !file.exists(bsgenome_file)) {
      stop(paste("Error: Missing required input files in the working directory.",
                 "Please ensure 'cas9GuideSet.rds', 'cas12aGuideSet.rds', 'ltn1GeneModel.rds', and 'bsgenome.rds' are present."))
    }
    
    # Stage 1: Load GuideSets and Gene Model for different nucleases targeting the same region
    cas9GuideSet <- readRDS(cas9_file)
    cas12aGuideSet <- readRDS(cas12a_file)
    ltn1GeneModel <- readRDS(genemodel_file)
    BSgenome.Hsapiens.UCSC.hg38 <- readRDS(bsgenome_file)
    
    # Stage 2: Plot and compare the GuideSets side-by-side, including a GC content track
    output_pdf <- "multiple_guidesets_comparison.pdf"
    pdf(output_pdf, width = 8, height = 10)
    
    plotMultipleGuideSets(list(SpCas9=cas9GuideSet, AsCas12a=cas12aGuideSet),
                          geneModel=ltn1GeneModel,
                          targetGene="LTN1",
                          bsgenome=BSgenome.Hsapiens.UCSC.hg38,
                          margin=0.2,
                          gcWindow=10)
    
    dev.off()
    
    # Save the combined list of compared GuideSets as an RDS object for downstream analysis
    saveRDS(list(SpCas9=cas9GuideSet, AsCas12a=cas12aGuideSet), "compared_guidesets_list.rds")

    writeLines(c(
        '"BIOC_CRISPRVIZ_COMPARE_MULTIPLE_GUIDESETS":',
        paste0('    crisprViz: ', as.character(packageVersion('crisprViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_multiple_guidesets.csv versions.yml
    """
}

workflow BIOC_CRISPRVIZ_COMPARE_MULTIPLE_GUIDESETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ List of GuideSet objects, GRangesList, BSgenome ] ]

    main:
    BIOC_CRISPRVIZ_COMPARE_MULTIPLE_GUIDESETS(ch_input)

    emit:
    tables   = BIOC_CRISPRVIZ_COMPARE_MULTIPLE_GUIDESETS.out.tables
    plots    = BIOC_CRISPRVIZ_COMPARE_MULTIPLE_GUIDESETS.out.plots
    objects  = BIOC_CRISPRVIZ_COMPARE_MULTIPLE_GUIDESETS.out.objects
    versions = BIOC_CRISPRVIZ_COMPARE_MULTIPLE_GUIDESETS.out.versions
}
