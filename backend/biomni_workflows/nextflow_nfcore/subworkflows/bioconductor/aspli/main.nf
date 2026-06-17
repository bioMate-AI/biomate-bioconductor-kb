#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ASpli — aspli_alternative_splicing_pipeline
// Perform an integrative alternative splicing analysis from RNA-seq BAM files and a genome annotation, resulting in interactive HTML reports of integrated splicin
// Input: genes.gtf, sample_bams/, merged_bams/
// Container: quay.io/biocontainers/bioconductor-aspli:2.20.0--r45hdfd78af_0
// R packages: ASpli, GenomicFeatures
// Bioconductor: 3.20 | R: 4.4
// Requires: ASpli, GenomicFeatures, txdbmaker
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build TxDb from GTF and bin the genome using binGenome
//  * 2. [Input & Preparation] Define targets and merged BAMs data frames
//  * 3. [Input & Preparation] Count read overlaps against genomic features using gbCounts
//  * 4. [Core Analysis] Quantify junction inclusion indices (PSI, PIR, PJU) using jCounts
//  * 5. [Core Analysis] Estimate differential gene expression and bin usage using gbDUreport
//  * 6. [Core Analysis] Estimate differential junction usage using jDUreport
//  * 7. [Core Analysis] Integrate bin and junction signals using splicingReport
//  * 8. [Visualization & Output] Summarize region-specific differential usage signals using integrateSignals
//  * 9. [Visualization & Output] Export interactive HTML reports using exportIntegratedSignals

nextflow.enable.dsl = 2

process BIOC_ASPLI_ASPLI_ALTERNATIVE_SPLICING_PIPELINE {
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
    .bm_deps <- c("ASpli", "GenomicFeatures")
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
    library(ASpli)
    library(GenomicFeatures)
    
    # Verify user input files and directories exist
    if (!file.exists("genes.gtf")) {
      stop("Error: 'genes.gtf' not found in the working directory.")
    }
    if (!dir.exists("sample_bams")) {
      stop("Error: 'sample_bams/' directory not found in the working directory.")
    }
    if (!dir.exists("merged_bams")) {
      stop("Error: 'merged_bams/' directory not found in the working directory.")
    }
    
    # 1. Build TxDb from GTF and bin the genome using binGenome
    gtfFileName <- "genes.gtf"
    genomeTxDb  <- txdbmaker::makeTxDbFromGFF( gtfFileName )
    features    <- binGenome( genomeTxDb )
    
    # 2. Define targets and merged BAMs data frames from user input directories
    BAMFiles <- list.files("sample_bams", pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(BAMFiles) == 0) {
      stop("Error: No BAM files found in 'sample_bams/'")
    }
    BAMFiles <- sort(BAMFiles)
    
    # Assign conditions (control vs treatment) based on file names or split in half
    f1 <- rep("control", length(BAMFiles))
    treat_idx <- grep("treat|tr|case|mut|stim", basename(BAMFiles), ignore.case = TRUE)
    if (length(treat_idx) > 0 && length(treat_idx) < length(BAMFiles)) {
      f1[treat_idx] <- "treatment"
      f1[-treat_idx] <- "control"
    } else {
      half <- ceiling(length(BAMFiles) / 2)
      f1[seq(from = half + 1, to = length(BAMFiles))] <- "treatment"
    }
    
    targets <- data.frame(row.names = paste0('Sample', seq_along(BAMFiles)),
                           bam = BAMFiles,
                           f1  = f1,
                           stringsAsFactors = FALSE)
    
    # Identify merged BAMs for each condition
    merged_files <- list.files("merged_bams", pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(merged_files) == 0) {
      stop("Error: No BAM files found in 'merged_bams/'")
    }
    
    control_merged <- merged_files[grep("control|ct", basename(merged_files), ignore.case = TRUE)]
    treatment_merged <- merged_files[grep("treat|tr|case|mut|stim", basename(merged_files), ignore.case = TRUE)]
    
    if (length(control_merged) == 0) {
      control_merged <- merged_files[1]
    }
    if (length(treatment_merged) == 0) {
      if (length(merged_files) > 1) {
        treatment_merged <- merged_files[2]
      } else {
        treatment_merged <- merged_files[1]
      }
    }
    
    mBAMs <- data.frame(bam = c(control_merged[1], treatment_merged[1]),
                         condition = c("control", "treatment"),
                         stringsAsFactors = FALSE)
    
    # 3. Count read overlaps against genomic features using gbCounts
    gbcounts <- gbCounts(features=features, targets=targets,
                         minReadLength = 100, maxISize = 50000)
    
    # 4. Quantify junction inclusion indices (PSI, PIR, PJU) using jCounts
    asd <- jCounts(counts=gbcounts, features=features, minReadLength=100)
    
    # 5. Estimate differential gene expression and bin usage using gbDUreport
    gb  <- gbDUreport(gbcounts, contrast = c(-1,1))
    
    # 6. Estimate differential junction usage using jDUreport
    jdur <- jDUreport(asd, contrast=c(-1,1))
    
    # 7. Integrate bin and junction signals using splicingReport
    sr <- splicingReport(gb, jdur, counts=gbcounts)
    
    # 8. Summarize region-specific differential usage signals using integrateSignals
    is <- integrateSignals(sr,asd)
    
    # 9. Export interactive HTML reports using exportIntegratedSignals
    exportIntegratedSignals(is,sr=sr,
                              output.dir = "aspliExample",
                              counts=gbcounts,features=features,asd=asd,
                              mergedBams = mBAMs)
    
    # Save meaningful intermediate and final R objects
    saveRDS(features, "aspli_features.rds")
    saveRDS(gbcounts, "aspli_gbcounts.rds")
    saveRDS(asd, "aspli_asd.rds")
    saveRDS(gb, "aspli_gb.rds")
    saveRDS(jdur, "aspli_jdur.rds")
    saveRDS(sr, "aspli_sr.rds")
    saveRDS(is, "aspli_is.rds")
    
    # Export results as CSV tables
    writeCounts(counts=gbcounts, output.dir = "aspli_exported_counts")
    writeRds(counts=gbcounts, output.dir = "aspli_exported_counts")
    writeAS(as=asd, output.dir = "aspli_exported_as")
    writeDU(gb, output.dir = "aspli_exported_du")
    writeSplicingReport(sr, output.dir = "aspli_exported_splicing_report")

    writeLines(c(
        '"BIOC_ASPLI_ASPLI_ALTERNATIVE_SPLICING_PIPELINE":',
        paste0('    ASpli: ', as.character(packageVersion('ASpli')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aspli_alternative_splicing_pipeline.csv versions.yml
    """
}

workflow BIOC_ASPLI_ASPLI_ALTERNATIVE_SPLICING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes.gtf, sample_bams/, merged_bams/ ] ]

    main:
    BIOC_ASPLI_ASPLI_ALTERNATIVE_SPLICING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ASPLI_ASPLI_ALTERNATIVE_SPLICING_PIPELINE.out.tables
    plots    = BIOC_ASPLI_ASPLI_ALTERNATIVE_SPLICING_PIPELINE.out.plots
    objects  = BIOC_ASPLI_ASPLI_ALTERNATIVE_SPLICING_PIPELINE.out.objects
    versions = BIOC_ASPLI_ASPLI_ALTERNATIVE_SPLICING_PIPELINE.out.versions
}
