#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sevenC — predict_loops_default_model
// Predict chromatin looping interactions from CTCF motifs and a ChIP-seq bigWig file using the default pre-trained model.
// Input: motifs.hg19.CTCF.chr22, GM12878_Stat1.chr22_1-30000000.bigWig
// Container: quay.io/biocontainers/bioconductor-sevenc:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicInteractions, sevenC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load CTCF motifs
//  * 2. [Input & Preparation] Read ChIP-seq coverage at motif sites using addCovToGR()
//  * 3. [Input & Preparation] Build candidate motif pairs within a distance threshold using prepareCisPairs()
//  * 4. [Core Analysis] Compute ChIP-seq signal correlation between pairs using addCovCor()
//  * 5. [Core Analysis] Predict loops using predLoops()
//  * 6. [Visualization & Output] Export predicted loops to a BEDPE file using export.bedpe()

nextflow.enable.dsl = 2

process BIOC_SEVENC_PREDICT_LOOPS_DEFAULT_MODEL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("sevenC", "GenomicInteractions")
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
    
    library(sevenC)
    library(GenomicInteractions)
    
    # 1. Load CTCF motifs from the user-provided RDS file in the working directory
    motifs <- readRDS("motifs.hg19.CTCF.chr22")
    
    # 2. Define the path to the user-provided ChIP-seq bigWig file
    bigWigFile <- "GM12878_Stat1.chr22_1-30000000.bigWig"
    
    # 3. Read ChIP-seq coverage at motif sites
    motifs <- addCovToGR(motifs, bigWigFile)
    
    # 4. Build candidate motif pairs within a distance threshold
    gi <- prepareCisPairs(motifs, maxDist = 10^6)
    
    # 5. Compute ChIP-seq signal correlation between pairs
    gi <- addCovCor(gi)
    
    # 6. Predict loops using the default model
    loops <- predLoops(gi)
    
    # 7. Export predicted loops to a BEDPE file
    export.bedpe(loops, "loop_interactions.bedpe", score = "pred")
    
    # 8. Save additional outputs (RDS and CSV summary)
    saveRDS(loops, "predicted_loops.rds")
    
    loops_df <- as.data.frame(loops)
    write.csv(loops_df, "predicted_loops_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SEVENC_PREDICT_LOOPS_DEFAULT_MODEL":',
        paste0('    sevenC: ', as.character(packageVersion('sevenC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_loops_default_model.csv versions.yml
    """
}

workflow BIOC_SEVENC_PREDICT_LOOPS_DEFAULT_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ motifs.hg19.CTCF.chr22, GM12878_Stat1.chr22_1-30000000.bigWig ] ]

    main:
    BIOC_SEVENC_PREDICT_LOOPS_DEFAULT_MODEL(ch_input)

    emit:
    tables   = BIOC_SEVENC_PREDICT_LOOPS_DEFAULT_MODEL.out.tables
    plots    = BIOC_SEVENC_PREDICT_LOOPS_DEFAULT_MODEL.out.plots
    objects  = BIOC_SEVENC_PREDICT_LOOPS_DEFAULT_MODEL.out.objects
    versions = BIOC_SEVENC_PREDICT_LOOPS_DEFAULT_MODEL.out.versions
}
