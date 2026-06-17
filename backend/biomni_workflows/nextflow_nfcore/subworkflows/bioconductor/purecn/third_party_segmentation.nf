#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PureCN — third_party_segmentation
// Run PureCN using pre-computed copy number segmentations or log2-ratios from third-party tools like CNVkit or GATK4.
// Input: tumor.seg, tumor.cnr, tumor_mutect.vcf, interval.txt
// Container: quay.io/biocontainers/bioconductor-purecn:2.16.0--r45hdfd78af_0
// R packages: PureCN
// Bioconductor: 3.20 | R: 4.4
// Requires: PureCN
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run absolute copy number estimation using pre-segmented data with runAbsoluteCN
//  * 2. [Core Analysis] Alternatively, calculate log2-ratios from coverage files and run runAbsoluteCN with custom log-ratios

nextflow.enable.dsl = 2

process BIOC_PURECN_THIRD_PARTY_SEGMENTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("PureCN")
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
        
        # Load required library
        library(PureCN)
        
        # Define input file paths as specified in the user workflow
        seg.file <- "tumor.seg"
        vcf.file <- "tumor_mutect.vcf"
        interval.file <- "interval.txt"
        tumor.cnr.file <- "tumor.cnr" # Optional CNVkit file
        
        # Verify that the primary required files exist
        if (!file.exists(seg.file)) {
            stop("Required input file missing: ", seg.file)
        }
        if (!file.exists(vcf.file)) {
            stop("Required input file missing: ", vcf.file)
        }
        if (!file.exists(interval.file)) {
            stop("Required input file missing: ", interval.file)
        }
        
        # ==========================================
        # STAGE 1: Run absolute copy number estimation using pre-segmented data
        # ==========================================
        message("Starting Stage 1: Absolute copy number estimation from pre-segmented data...")
        
        retSegmented <- runAbsoluteCN(seg.file = seg.file, 
            interval.file = interval.file, vcf.file = vcf.file, 
            max.candidate.solutions = 1, genome = "hg19",
            test.purity = seq(0.3, 0.7, by = 0.05), verbose = FALSE, 
            plot.cnv = FALSE)
        
        # Save Stage 1 results
        saveRDS(retSegmented, file = "retSegmented.rds")
        
        # Generate meaningful outputs from Stage 1
        tryCatch({
            # Predict somatic status and cellular fraction
            somatic_predictions <- predictSomatic(retSegmented)
            write.csv(somatic_predictions, file = "segmented_somatic_predictions.csv", row.names = FALSE)
            
            # Call gene-level alterations
            gene_calls <- callAlterations(retSegmented)
            write.csv(gene_calls, file = "segmented_gene_calls.csv", row.names = FALSE)
            
            # Call loss of heterozygosity (LOH)
            loh_calls <- callLOH(retSegmented)
            write.csv(loh_calls, file = "segmented_loh_calls.csv", row.names = FALSE)
            
            # Generate diagnostic plots
            pdf("segmented_plots.pdf", width = 10, height = 11)
            plotAbs(retSegmented, type = "all")
            dev.off()
            
            message("Stage 1 completed successfully. Outputs written.")
        }, error = function(e) {
            message("Error writing Stage 1 outputs: ", e\$message)
        })
        
        
        # ==========================================
        # STAGE 2: Alternatively, run runAbsoluteCN using CNVkit .cnr file
        # ==========================================
        message("Starting Stage 2: runAbsoluteCN using CNVkit .cnr file...")
        
        # Define coverage files for Stage 2. 
        # We use 'tumor.cnr' as the tumor coverage file.
        normalDB.file <- "normalDB.rds"
        
        tryCatch({
            if (!file.exists(tumor.cnr.file)) {
                stop("Tumor coverage file missing: ", tumor.cnr.file)
            }
            
            # Load normalDB if available, otherwise default to NULL
            normalDB <- if (file.exists(normalDB.file)) readRDS(normalDB.file) else NULL
            if (is.null(normalDB)) {
                message("Warning: normalDB.rds not found. Running runAbsoluteCN without normalDB.")
            }
            
            # Run absolute copy number estimation using the CNVkit .cnr file
            retLogRatio <- runAbsoluteCN(tumor.coverage.file = tumor.cnr.file,
                interval.file = interval.file, vcf.file = vcf.file, 
                max.candidate.solutions = 1, genome = "hg19",
                test.purity = seq(0.3, 0.7, by = 0.05), verbose = FALSE, 
                normalDB = normalDB, plot.cnv = FALSE)
            
            # Save Stage 2 results
            saveRDS(retLogRatio, file = "retLogRatio.rds")
            
            # Generate meaningful outputs from Stage 2
            logratio_somatic <- predictSomatic(retLogRatio)
            write.csv(logratio_somatic, file = "logratio_somatic_predictions.csv", row.names = FALSE)
            
            pdf("logratio_plots.pdf", width = 10, height = 11)
            plotAbs(retLogRatio, type = "all")
            dev.off()
            
            message("Stage 2 completed successfully. Outputs written.")
        }, error = function(e) {
            message("Stage 2 (Log-ratio workflow) was skipped or failed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_PURECN_THIRD_PARTY_SEGMENTATION":',
        paste0('    PureCN: ', as.character(packageVersion('PureCN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_third_party_segmentation.csv versions.yml
    """
}

workflow BIOC_PURECN_THIRD_PARTY_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tumor.seg, tumor.cnr, tumor_mutect.vcf, interval.txt ] ]

    main:
    BIOC_PURECN_THIRD_PARTY_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_PURECN_THIRD_PARTY_SEGMENTATION.out.tables
    plots    = BIOC_PURECN_THIRD_PARTY_SEGMENTATION.out.plots
    objects  = BIOC_PURECN_THIRD_PARTY_SEGMENTATION.out.objects
    versions = BIOC_PURECN_THIRD_PARTY_SEGMENTATION.out.versions
}
