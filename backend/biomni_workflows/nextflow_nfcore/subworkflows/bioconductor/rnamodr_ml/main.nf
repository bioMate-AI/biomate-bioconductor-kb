#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnamodr_ml — detect_2_o_methylations_ml
// Detect 2'-O-methylations from Ribo-meth-seq BAM files using machine learning classifiers.
// Input: sample1.bam, genome.fa, annotation.gff
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: GenomicRanges, rnamodr.ml, rnamodr_ml, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/r-base:4.3.1"

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
    .bm_deps <- c("GenomicRanges", "rnamodr.ml", "rnamodr_ml", "rtracklayer")
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
    
    # --- Load the package and define input file paths ---
    library(rnamodr.ml)
    
    # User-specified input files
    bamfiles <- "sample1.bam"
    fasta <- "genome.fa"
    gff <- "annotation.gff"
    
    # Robustness: Attempt to index the BAM file if the index does not exist
    if (file.exists("sample1.bam") && !file.exists("sample1.bam.bai")) {
      tryCatch({
        if (requireNamespace("Rsamtools", quietly = TRUE)) {
          Rsamtools::indexBam("sample1.bam")
        }
      }, error = function(e) {
        warning("Optional BAM indexing failed: ", e\$message)
      })
    }
    
    # --- Initialize the ModMLRiboMethSeq modifier object ---
    mod <- ModMLRiboMethSeq(bamfiles, fasta = fasta, gff = gff)
    
    # --- Extract predicted 2'-O-methylations using the ---
    mods <- modifications(mod)
    
    # --- Write named output files for the results ---
    saveRDS(mod, "rnamodr_modifier_object.rds")
    saveRDS(mods, "predicted_modifications.rds")
    
    # Attempt to save modifications as a CSV table for easy viewing
    tryCatch({
      mods_df <- as.data.frame(mods)
      write.csv(mods_df, "predicted_modifications.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not write modifications to CSV: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML":',
        paste0('        rnamodr_ml: ', as.character(packageVersion("rnamodr_ml")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_2_o_methylations_ml.csv versions.yml
    """
}

workflow BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample1.bam, genome.fa, annotation.gff ] ]

    main:
    BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML(ch_input)

    emit:
    tables   = BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML.out.tables
    plots    = BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML.out.plots
    objects  = BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML.out.objects
    versions = BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML.out.versions
}
