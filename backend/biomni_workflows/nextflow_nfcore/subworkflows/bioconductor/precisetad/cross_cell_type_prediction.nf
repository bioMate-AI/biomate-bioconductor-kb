#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: preciseTAD — cross_cell_type_prediction
// Predict precise TAD boundaries in a new cell type using a pre-trained model and cell-type-specific genomic annotations.
// Input: CHR22_GM12878_5kb_Peakachu.rds, ctcf.bed, rad21.bed, smc3.bed, znf143.bed
// Container: quay.io/biocontainers/bioconductor-precisetad:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: preciseTAD
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the pre-trained model using readRDS()
//  * 2. [Input & Preparation] Read and convert target cell-type BED files into a GRangesList using bedToGRangesList()
//  * 3. [Core Analysis] Predict precise boundaries using preciseTAD()

nextflow.enable.dsl = 2

process BIOC_PRECISETAD_CROSS_CELL_TYPE_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("preciseTAD")
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
    library(preciseTAD)
    
    # 1. Load the pre-trained model from the working directory
    tadModel <- readRDS("CHR22_GM12878_5kb_Peakachu.rds")
    
    # 2. Read target cell-type BED files from the working directory
    ctcf <- as.data.frame(read.delim("ctcf.bed", sep = "\t", header = FALSE))
    rad21 <- as.data.frame(read.delim("rad21.bed", sep = "\t", header = FALSE))
    smc3 <- as.data.frame(read.delim("smc3.bed", sep = "\t", header = FALSE))
    znf143 <- as.data.frame(read.delim("znf143.bed", sep = "\t", header = FALSE))
    
    # Combine into a list
    helaList <- list(ctcf, rad21, smc3, znf143)
    
    # Convert to GRangesList using bedToGRangesList
    hela.GR <- bedToGRangesList(bedList=helaList, bedNames=c("Ctcf", "Rad21", "Smc3", "Znf143"), signal=5)
    
    # 3. Predict precise boundaries using preciseTAD
    set.seed(123)
    pt <- preciseTAD(
      genomicElements.GR = hela.GR,
      featureType = "distance",
      CHR = "CHR22",
      chromCoords = list(25500000, 27500000),
      tadModel = tadModel[[1]],
      threshold = 1.0,
      verbose = FALSE,
      parallel = NULL,
      DBSCAN_params = list(30000, 100),
      slope = 5000,
      BaseProbs = FALSE,
      savetobed = FALSE
    )
    
    # 4. Save outputs
    # Save the full preciseTAD results list
    saveRDS(pt, "preciseTAD_output.rds")
    
    # Save PTBPs (Precise TAD Boundary Points) in Juicebox-ready format
    if (!is.null(pt\$PTBP) && length(pt\$PTBP) > 0) {
      pt_juice <- juicer_func(pt\$PTBP)
      write.table(pt_juice, "pt_juice.bed", quote = FALSE, col.names = FALSE, row.names = FALSE, sep = "\t")
    }
    
    # Save PTBRs (Precise TAD Boundary Regions) as a TSV
    if (!is.null(pt\$PTBR) && length(pt\$PTBR) > 0) {
      ptbr_df <- as.data.frame(pt\$PTBR)
      write.table(ptbr_df, "pt_regions.tsv", quote = FALSE, sep = "\t", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_PRECISETAD_CROSS_CELL_TYPE_PREDICTION":',
        paste0('    preciseTAD: ', as.character(packageVersion('preciseTAD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_cell_type_prediction.csv versions.yml
    """
}

workflow BIOC_PRECISETAD_CROSS_CELL_TYPE_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CHR22_GM12878_5kb_Peakachu.rds, ctcf.bed, rad21.bed, smc3.bed, znf143.bed ] ]

    main:
    BIOC_PRECISETAD_CROSS_CELL_TYPE_PREDICTION(ch_input)

    emit:
    tables   = BIOC_PRECISETAD_CROSS_CELL_TYPE_PREDICTION.out.tables
    plots    = BIOC_PRECISETAD_CROSS_CELL_TYPE_PREDICTION.out.plots
    objects  = BIOC_PRECISETAD_CROSS_CELL_TYPE_PREDICTION.out.objects
    versions = BIOC_PRECISETAD_CROSS_CELL_TYPE_PREDICTION.out.versions
}
