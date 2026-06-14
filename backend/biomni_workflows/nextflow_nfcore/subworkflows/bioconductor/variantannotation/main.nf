#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VariantAnnotation — variant_annotation_and_prediction
// Read a VCF file, locate variants relative to gene models, predict amino acid coding changes, and query PolyPhen for functional impact.
// Input: chr22.vcf.gz, TxDb.Hsapiens.UCSC.hg19.knownGene, BSgenome.Hsapiens.UCSC.hg19, PolyPhen.Hsapiens.dbSNP131
// Container: quay.io/biocontainers/bioconductor-variantannotation:1.56.0--r45h01b2380_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, PolyPhen.Hsapiens.dbSNP131, TxDb.Hsapiens.UCSC.hg19.knownGene, AnnotationHub, GenomicRanges, ggplot2, microbenchmark, rjsoncons, VariantAnnotation
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, PolyPhen.Hsapiens.dbSNP131, TxDb.Hsapiens.UCSC.hg19.knownGene, VariantAnnotation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the VCF file into a VCF object
//  * 2. [Input & Preparation] Align chromosome naming styles (seqlevels) between the
//  * 3. [Input & Preparation] Locate variants in coding regions using locateVariants
//  * 4. [Input & Preparation] Predict amino acid coding changes for the variants using
//  * 5. [Input & Preparation] Query the PolyPhen database to retrieve functional impact

nextflow.enable.dsl = 2

process BIOC_VARIANTANNOTATION_VARIANT_ANNOTATION_AND_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "PolyPhen.Hsapiens.dbSNP131", "TxDb.Hsapiens.UCSC.hg19.knownGene", "AnnotationHub", "GenomicRanges", "ggplot2", "microbenchmark", "rjsoncons", "VariantAnnotation", "SummarizedExperiment")
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
    lib    library(SummarizedExperiment)
rary(VariantAnnotation)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(PolyPhen.Hsapiens.dbSNP131)
    
    # Define input file path (must exist in the working directory)
    fl <- "chr22.vcf.gz"
    
    if (!file.exists(fl)) {
      stop(paste("Required input file missing in the working directory:", fl))
    }
    
    # --- Read the VCF file into a VCF object ---
    message("Reading VCF file...")
    vcf <- readVcf(fl, "hg19")
    
    # --- Align chromosome naming styles (seqlevels) between the ---
    message("Aligning seqlevels...")
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    seqlevels(vcf) <- "chr22"
    rd <- rowRanges(vcf)
    
    # --- Locate variants in coding regions using locateVariants ---
    message("Locating variants...")
    loc <- locateVariants(rd, txdb, CodingVariants())
    
    # --- Predict amino acid coding changes for the variants using ---
    message("Predicting coding changes...")
    coding <- predictCoding(vcf, txdb, seqSource=Hsapiens)
    
    # Filter for nonsynonymous variants
    nms <- names(coding) 
    idx <- mcols(coding)\$CONSEQUENCE == "nonsynonymous"
    nonsyn <- coding[idx]
    names(nonsyn) <- nms[idx]
    rsids <- unique(names(nonsyn)[grep("rs", names(nonsyn), fixed=TRUE)])
    
    # --- Query the PolyPhen database to retrieve functional impact ---
    message("Querying PolyPhen database...")
    pp <- select(PolyPhen.Hsapiens.dbSNP131, keys=rsids,
                 cols=c("TRAININGSET", "PREDICTION", "PPH2PROB"))
    
    # Helper function to safely convert GRanges with list-like columns to flat data.frame for CSV export
    flatten_granges <- function(gr) {
      df <- as.data.frame(gr)
      for (col in names(df)) {
        if (is.list(df[[col]]) || inherits(df[[col]], "List") || inherits(df[[col]], "IntegerList") || inherits(df[[col]], "CharacterList")) {
          df[[col]] <- sapply(df[[col]], function(x) {
            val <- unlist(x)
            if (is.null(val) || length(val) == 0) "" else paste(val, collapse = ";")
          })
        }
      }
      return(df)
    }
    
    # Write outputs to the working directory
    message("Writing output files...")
    
    # Save located variants
    saveRDS(loc, "located_variants.rds")
    write.csv(flatten_granges(loc), "located_variants.csv", row.names = FALSE)
    
    # Save predicted coding changes
    saveRDS(coding, "predicted_coding.rds")
    write.csv(flatten_granges(coding), "predicted_coding.csv", row.names = FALSE)
    
    # Save PolyPhen predictions
    write.csv(pp, "polyphen_predictions.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_VARIANTANNOTATION_VARIANT_ANNOTATION_AND_PREDICTION":',
        paste0('    VariantAnnotation: ', as.character(packageVersion('VariantAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variant_annotation_and_prediction.csv versions.yml
    """
}

workflow BIOC_VARIANTANNOTATION_VARIANT_ANNOTATION_AND_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr22.vcf.gz, TxDb.Hsapiens.UCSC.hg19.knownGene, BSgenome.Hsapiens.UCSC.hg19, PolyPhen.Hsapiens.dbSNP131 ] ]

    main:
    BIOC_VARIANTANNOTATION_VARIANT_ANNOTATION_AND_PREDICTION(ch_input)

    emit:
    tables   = BIOC_VARIANTANNOTATION_VARIANT_ANNOTATION_AND_PREDICTION.out.tables
    plots    = BIOC_VARIANTANNOTATION_VARIANT_ANNOTATION_AND_PREDICTION.out.plots
    objects  = BIOC_VARIANTANNOTATION_VARIANT_ANNOTATION_AND_PREDICTION.out.objects
    versions = BIOC_VARIANTANNOTATION_VARIANT_ANNOTATION_AND_PREDICTION.out.versions
}
