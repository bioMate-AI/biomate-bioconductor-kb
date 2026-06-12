#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sevenC — train_custom_prediction_model
// Train a custom logistic regression model using known experimental loops and use it to predict chromatin loops.
// Input: motifs.hg19.CTCF.chr22, GM12878_Stat1.chr22_1-30000000.bigWig, GM12878_HiCCUPS.chr22_1-30000000.loop.txt
// Container: quay.io/biocontainers/bioconductor-sevenc:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, InteractionSet, sevenC
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load CTCF motifs and read ChIP-seq coverage using addCovToGR()
//  * 2. [Input & Preparation] Build candidate motif pairs using prepareCisPairs() and compute ChIP-seq signal correlation using addCovCor()
//  * 3. [Input & Preparation] Parse known experimental loops using parseLoopsRao()
//  * 4. [Core Analysis] Annotate candidate pairs with experimental interaction support using addInteractionSupport()
//  * 5. [Core Analysis] Fit a logistic regression model using glm()
//  * 6. [Core Analysis] Predict loops using the custom model coefficients and formula in predLoops()

nextflow.enable.dsl = 2

process BIOC_SEVENC_TRAIN_CUSTOM_PREDICTION_MODEL {
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
    .bm_deps <- c("sevenC", "GenomicRanges", "InteractionSet")
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
    library(sevenC)
    library(GenomicRanges)
    library(InteractionSet)
    
    # 1. Load CTCF motifs and read ChIP-seq coverage
    # Read the GRanges object containing CTCF motif locations from the working directory
    motifs <- readRDS("motifs.hg19.CTCF.chr22")
    
    # Define the path to the ChIP-seq coverage bigWig file
    bigWigFile <- "GM12878_Stat1.chr22_1-30000000.bigWig"
    
    # Add ChIP-seq coverage to the motifs
    motifs <- addCovToGR(motifs, bigWigFile)
    
    # 2. Build candidate motif pairs and compute ChIP-seq signal correlation
    gi <- prepareCisPairs(motifs, maxDist = 10^6)
    
    # Add correlation of ChIP-signal
    gi <- addCovCor(gi)
    
    # 3. Parse known experimental loops
    knownLoopFile <- "GM12878_HiCCUPS.chr22_1-30000000.loop.txt"
    knownLoops <- parseLoopsRao(knownLoopFile)
    
    # 4. Annotate candidate pairs with experimental interaction support
    gi <- addInteractionSupport(gi, knownLoops)
    
    # 5. Fit a logistic regression model
    fit <- glm(
      formula = loop ~ cor_chip + dist + strandOrientation, 
      data = mcols(gi), 
      family = binomial()
    )
    
    # 6. Predict loops using the custom model coefficients and formula
    gi <- predLoops(
      gi,
      formula = loop ~ cor_chip + dist + strandOrientation,
      betas = coef(fit),
      cutoff = NULL
    )
    
    # Write outputs
    # Save the fitted model object
    saveRDS(fit, "custom_loop_model.rds")
    
    # Save the annotated GInteractions object with predictions
    saveRDS(gi, "predicted_loops_gi.rds")
    
    # Export metadata and predictions as a CSV table
    write.csv(as.data.frame(mcols(gi)), "predicted_loops_metadata.csv", row.names = FALSE)
    
    # Generate and save the validation boxplot
    pdf("loop_prediction_boxplot.pdf", width = 5, height = 6)
    boxplot(gi\$pred ~ gi\$loop, 
            ylab = "Predicted interaction probability",
            xlab = "Experimental Loop Support",
            main = "Custom Model Predictions vs. Known Loops")
    dev.off()

    writeLines(c(
        '"BIOC_SEVENC_TRAIN_CUSTOM_PREDICTION_MODEL":',
        paste0('    sevenC: ', as.character(packageVersion('sevenC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_train_custom_prediction_model.csv versions.yml
    """
}

workflow BIOC_SEVENC_TRAIN_CUSTOM_PREDICTION_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ motifs.hg19.CTCF.chr22, GM12878_Stat1.chr22_1-30000000.bigWig, GM12878_HiCCUPS.chr22_1-30000000.loop.txt ] ]

    main:
    BIOC_SEVENC_TRAIN_CUSTOM_PREDICTION_MODEL(ch_input)

    emit:
    tables   = BIOC_SEVENC_TRAIN_CUSTOM_PREDICTION_MODEL.out.tables
    plots    = BIOC_SEVENC_TRAIN_CUSTOM_PREDICTION_MODEL.out.plots
    objects  = BIOC_SEVENC_TRAIN_CUSTOM_PREDICTION_MODEL.out.objects
    versions = BIOC_SEVENC_TRAIN_CUSTOM_PREDICTION_MODEL.out.versions
}
