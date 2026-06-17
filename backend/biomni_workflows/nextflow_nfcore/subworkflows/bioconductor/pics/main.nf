#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PICS — pics_peak_calling
// Identify transcription factor binding sites from aligned ChIP-Seq reads using a probabilistic mixture model.
// Input: ip_reads.bam, control_reads.bam
// Container: quay.io/biocontainers/bioconductor-pics:2.50.0--r44h3df3fcb_1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicAlignments, GenomicRanges, PICS, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Segment the genome into candidate regions using segmentReads
//  * 2. [Core Analysis] Run the probabilistic peak detection using pics
//  * 3. [Core Analysis] Convert the results to a GRanges object for downstream analysis

nextflow.enable.dsl = 2

process BIOC_PICS_PICS_PEAK_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("PICS", "GenomicRanges", "GenomicAlignments", "rtracklayer")
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
        library(PICS)
        library(GenomicRanges)
        library(GenomicAlignments)
        library(rtracklayer)
        
        # Define input file paths
        ip_bam <- "ip_reads.bam"
        control_bam <- "control_reads.bam"
        
        # Validate input files
        if (!file.exists(ip_bam)) {
          stop("Error: Input file 'ip_reads.bam' not found in the working directory.")
        }
        if (!file.exists(control_bam)) {
          stop("Error: Input file 'control_reads.bam' not found in the working directory.")
        }
        
        # Step 1: Read BAM files and convert to GRanges objects
        message("Reading IP and Control BAM files...")
        IP <- granges(readGAlignments(ip_bam))
        Control <- granges(readGAlignments(control_bam))
        
        # Step 2: Segment the genome into candidate regions using segmentReads
        message("Segmenting reads...")
        seg <- segmentReads(IP, Control, minReads = 2, map = NULL)
        
        # Step 3: Run the probabilistic peak detection using PICS
        message("Running PICS peak calling...")
        ans <- PICS(seg, nco = 1)
        
        # Step 4: Convert the results to a GRanges object for downstream analysis
        message("Converting results to GRanges...")
        rd <- as(ans, "GRanges")
        
        # Step 5: Write output files
        message("Writing output files...")
        
        # Save the GRanges object as RDS
        saveRDS(rd, "pics_peaks.rds")
        
        # Save the full PICS result object as RDS
        saveRDS(ans, "pics_fit.rds")
        
        # Export peaks to CSV
        peaks_df <- as.data.frame(rd)
        write.csv(peaks_df, "pics_peaks.csv", row.names = FALSE)
        
        # Export peaks to BED format
        tryCatch({
          export(rd, "pics_peaks.bed")
        }, error = function(e) {
          warning("Could not export to BED format: ", e\$message)
        })
        
        message("PICS peak calling workflow completed successfully.")

    writeLines(c(
        '"BIOC_PICS_PICS_PEAK_CALLING":',
        paste0('    PICS: ', as.character(packageVersion('PICS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pics_peak_calling.csv versions.yml
    """
}

workflow BIOC_PICS_PICS_PEAK_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ip_reads.bam, control_reads.bam ] ]

    main:
    BIOC_PICS_PICS_PEAK_CALLING(ch_input)

    emit:
    tables   = BIOC_PICS_PICS_PEAK_CALLING.out.tables
    plots    = BIOC_PICS_PICS_PEAK_CALLING.out.plots
    objects  = BIOC_PICS_PICS_PEAK_CALLING.out.objects
    versions = BIOC_PICS_PICS_PEAK_CALLING.out.versions
}
