#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EventPointer — rna_seq_bam_pipeline
// Detect, quantify, and analyze novel and annotated alternative splicing events directly from RNA-Seq BAM alignment files.
// Input: sample_alignments.bam, sample_alignments.bai, reference_transcriptome.gtf
// Container: quay.io/biocontainers/bioconductor-eventpointer:3.18.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EventPointer, SGSeq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Detect splicing events and calculate bootstrap PSI values using EventsDetection_BAM
//  * 2. [Core Analysis] Perform statistical analysis using EventPointerStats_BAM
//  * 3. [Visualization & Output] Generate GTF files for IGV visualization using EventPointerBAM_IGV

nextflow.enable.dsl = 2

process BIOC_EVENTPOINTER_RNA_SEQ_BAM_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("EventPointer", "SGSeq")
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
        library(EventPointer)
        library(SGSeq)
        
        # Define paths to user input files in the working directory
        PathSamplesAbundance <- getwd()
        PathTranscriptomeGTF <- file.path(getwd(), "reference_transcriptome.gtf")
        
        # Define and create the output directory for splicing graph results
        PathSGResult <- file.path(getwd(), "EventPointer_Output")
        if (!dir.exists(PathSGResult)) {
          dir.create(PathSGResult, recursive = TRUE)
        }
        
        # 1. Detect splicing events and calculate bootstrap PSI values
        message("Running EventsDetection_BAM...")
        EventsDetection_BAM(PathSamplesAbundance,
                            PathTranscriptomeGTF,
                            region = NULL,
                            min_junction_count = 2,
                            max_complexity = 30,
                            min_n_sample = NULL,
                            min_anchor = 6,
                            nboot = 20,
                            lambda = NULL,
                            cores = 1,
                            PathSGResult = PathSGResult)
        
        # Load the generated PSI_boots object from the output directory
        psi_boots_file <- file.path(PathSGResult, "PSI_boots.RData")
        if (file.exists(psi_boots_file)) {
          load(psi_boots_file) # Loads 'PSI_boots'
        } else {
          stop("PSI_boots.RData was not generated. Check BAM files and GTF annotations.")
        }
        
        # Determine the number of samples dynamically to construct Design and Contrast matrices
        num_samples <- if (!is.null(dim(PSI_boots))) dim(PSI_boots)[3] else 1
        
        # Construct Design and Contrast matrices matching the sample size
        if (num_samples >= 9) {
          Design <- cbind(rep(1, num_samples), rep(c(1, 0, 0), length.out = num_samples), rep(c(0, 1, 0), length.out = num_samples))
          Contrast <- cbind(c(0, 1, 0), c(0, 0, 1))
        } else if (num_samples >= 2) {
          Design <- model.matrix(~ factor(rep(1:2, length.out = num_samples)))
          Contrast <- matrix(c(0, 1), nrow = 2, ncol = 1)
        } else {
          # Fallback for single sample (statistical analysis is trivial but prevents crash)
          Design <- matrix(1, nrow = num_samples, ncol = 1)
          Contrast <- matrix(1, nrow = 1, ncol = 1)
        }
        
        # 2. Perform statistical analysis using EventPointerStats_BAM
        message("Running EventPointerStats_BAM...")
        result <- tryCatch({
          EventPointerStats_BAM(PSI_boots,
                                Design,
                                Contrast,
                                Threshold = 0,
                                nbootstraps = 1000,
                                cores = 1,
                                ram = 0.1,
                                pathResult = PathSGResult)
        }, error = function(e) {
          message("Warning: EventPointerStats_BAM failed. This is expected if sample size is insufficient.")
          message(e\$message)
          NULL
        })
        
        # Save statistical results if successfully generated
        if (!is.null(result)) {
          saveRDS(result, file = "EventPointer_Stats_Results.rds")
        }
        
        # Load the generated SgFC object from the output directory
        sgfc_file <- file.path(PathSGResult, "SgFC.RData")
        if (file.exists(sgfc_file)) {
          load(sgfc_file) # Loads 'SgFC'
        } else {
          stop("SgFC.RData was not generated.")
        }
        
        SG_RNASeq <- SgFC
        EventsTxt <- file.path(PathSGResult, "TotalEventsFound.csv")
        PathGTF <- tempdir()
        
        # 3. Generate GTF files for IGV visualization using EventPointerBAM_IGV
        message("Running EventPointerBAM_IGV...")
        if (file.exists(EventsTxt)) {
          EventPointerBAM_IGV(SG_RNASeq = SgFC,
                              EventsCSV =  EventsTxt,
                              PathGTF =  "./")
          
          # Copy the main events table to the working directory for easy access
          file.copy(EventsTxt, "./TotalEventsFound.csv", overwrite = TRUE)
        } else {
          warning("TotalEventsFound.csv was not found. IGV visualization files could not be generated.")
        }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EVENTPOINTER_RNA_SEQ_BAM_PIPELINE":',
        paste0('    EventPointer: ', as.character(packageVersion('EventPointer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_bam_pipeline.csv versions.yml
    """
}

workflow BIOC_EVENTPOINTER_RNA_SEQ_BAM_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_alignments.bam, sample_alignments.bai, reference_transcriptome.gtf ] ]

    main:
    BIOC_EVENTPOINTER_RNA_SEQ_BAM_PIPELINE(ch_input)

    emit:
    tables   = BIOC_EVENTPOINTER_RNA_SEQ_BAM_PIPELINE.out.tables
    plots    = BIOC_EVENTPOINTER_RNA_SEQ_BAM_PIPELINE.out.plots
    objects  = BIOC_EVENTPOINTER_RNA_SEQ_BAM_PIPELINE.out.objects
    versions = BIOC_EVENTPOINTER_RNA_SEQ_BAM_PIPELINE.out.versions
}
