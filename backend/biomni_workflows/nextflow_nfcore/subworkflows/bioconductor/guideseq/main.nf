#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: guideseq — step_by_step_guideseq
// Perform GUIDE-seq analysis step-by-step to remove PCR bias, identify peaks, merge strands, and analyze off-targets.
// Input: bowtie2.HEK293_site4_chr13.sort.bam, UMI-HEK293_site4_chr13.txt, T2.fa, T2plus100OffTargets.bed
// Container: quay.io/biocontainers/bioconductor-guideseq:1.40.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, GUIDEseq, knitr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GUIDESEQ_STEP_BY_STEP_GUIDESEQ {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-guideseq:1.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "GUIDEseq", "knitr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(GUIDEseq)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # Define input files from the working directory
    bamfile <- "bowtie2.HEK293_site4_chr13.sort.bam"
    umifile <- "UMI-HEK293_site4_chr13.txt"
    gRNAs <- "T2.fa"
    peaks_file <- "T2plus100OffTargets.bed"
    
    # Verify input files exist
    inputs <- c(bamfile, umifile, gRNAs, peaks_file)
    missing_files <- inputs[!file.exists(inputs)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", paste(missing_files, collapse = ", ")))
    }
    
    # --- Remove PCR bias and obtain unique cleavage events ---
    message("Step 1: Removing PCR bias and obtaining unique cleavage events...")
    uniqueCleavageEvents <- getUniqueCleavageEvents(bamfile, umifile, n.cores.max = 1)
    saveRDS(uniqueCleavageEvents, "uniqueCleavageEvents.rds")
    
    # --- Summarize cleavage events into peaks ---
    message("Step 2: Summarizing cleavage events into peaks...")
    peaks <- getPeaks(uniqueCleavageEvents\$cleavage.gr, min.reads = 80)
    peaks.gr <- peaks\$peaks
    saveRDS(peaks, "peaks.rds")
    
    # --- Merge peaks from plus and minus strands ---
    message("Step 3: Merging plus and minus peaks...")
    mergedPeaks <- mergePlusMinusPeaks(peaks.gr = peaks.gr,  
        output.bedfile = "mergedPeaks.bed")
    saveRDS(mergedPeaks, "mergedPeaks.rds")
    
    # --- Perform off-target analysis of extended regions around ---
    message("Step 4: Performing off-target analysis of peak regions...")
    outputDir <- getwd() 
    
    # Reassign peaks variable to the BED file path as in the documented code
    peaks <- peaks_file
    
    offTargets <- offTargetAnalysisOfPeakRegions(gRNA = gRNAs, peaks = peaks,
        format=c("fasta", "bed"),
        peaks.withHeader = TRUE, BSgenomeName = Hsapiens,
        upstream = 50, downstream = 50, PAM.size = 3, gRNA.size = 20,
        PAM = "NGG", PAM.pattern = "(NAG|NGG|NGA)\$", max.mismatch = 2,
        outputDir = outputDir,
        orderOfftargetsBy = "predicted_cleavage_score",
        allowed.mismatch.PAM = 2, overwrite = TRUE
    )
    saveRDS(offTargets, "offTargets.rds")
    
    message("GUIDE-seq step-by-step pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GUIDESEQ_STEP_BY_STEP_GUIDESEQ":',
        paste0('        guideseq: ', as.character(packageVersion("guideseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_guideseq.csv versions.yml
    """
}

workflow BIOC_GUIDESEQ_STEP_BY_STEP_GUIDESEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bowtie2.HEK293_site4_chr13.sort.bam, UMI-HEK293_site4_chr13.txt, T2.fa, T2plus100OffTargets.bed ] ]

    main:
    BIOC_GUIDESEQ_STEP_BY_STEP_GUIDESEQ(ch_input)

    emit:
    tables   = BIOC_GUIDESEQ_STEP_BY_STEP_GUIDESEQ.out.tables
    plots    = BIOC_GUIDESEQ_STEP_BY_STEP_GUIDESEQ.out.plots
    objects  = BIOC_GUIDESEQ_STEP_BY_STEP_GUIDESEQ.out.objects
    versions = BIOC_GUIDESEQ_STEP_BY_STEP_GUIDESEQ.out.versions
}
