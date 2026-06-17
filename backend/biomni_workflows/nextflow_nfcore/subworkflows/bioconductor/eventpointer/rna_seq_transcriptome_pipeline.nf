#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EventPointer — rna_seq_transcriptome_pipeline
// Identify and analyze alternative splicing events using annotated reference transcriptomes and transcript abundance estimates from pseudo-aligners.
// Input: reference_transcriptome.gtf, abundance.tsv
// Container: quay.io/biocontainers/bioconductor-eventpointer:3.18.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EventPointer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Detect and classify alternative splicing events from the reference transcriptome using EventDetection_transcriptome
//  * 2. [Input & Preparation] Load pseudo-alignment bootstrap data using getbootstrapdata
//  * 3. [Core Analysis] Calculate PSI values and path expressions using GetPSI_FromTranRef
//  * 4. [Core Analysis] Perform statistical analysis using EventPointer_Bootstraps
//  * 5. [Visualization & Output] Generate GTF files for IGV visualization using EventPointer_RNASeq_TranRef_IGV

nextflow.enable.dsl = 2

process BIOC_EVENTPOINTER_RNA_SEQ_TRANSCRIPTOME_PIPELINE {
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
    .bm_deps <- c("EventPointer")
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
    
    # Define input files from the working directory
    inputFile <- "reference_transcriptome.gtf"
    abundance_file <- "abundance.tsv"
    
    # Check if input files exist
    if (!file.exists(inputFile)) {
      stop("Required input file 'reference_transcriptome.gtf' not found in the working directory.")
    }
    if (!file.exists(abundance_file)) {
      stop("Required input file 'abundance.tsv' not found in the working directory.")
    }
    
    # 1. Detect and classify alternative splicing events from the reference transcriptome
    Pathtxt <- "events_output"
    dir.create(Pathtxt, showWarnings = FALSE, recursive = TRUE)
    
    EventXtrans <- EventDetection_transcriptome(inputFile = inputFile,
                                                 Pathtxt = Pathtxt,
                                                 cores = 1)
    
    # 2. Load pseudo-alignment data
    if (dir.exists(abundance_file)) {
      # Input is a directory of pseudo-alignment outputs
      PathSamples <- dir(abundance_file, full.names = TRUE)
      
      # Auto-detect pseudo-aligner type (Salmon uses quant.sf, Kallisto uses abundance.tsv)
      pseudo_type <- ifelse(file.exists(file.path(PathSamples[1], "quant.sf")), "salmon", "kallisto")
      
      RNASeq <- getbootstrapdata(PathSamples = PathSamples, type = pseudo_type)
      
      # Clean transcript names for the first element (EventPointer uses this to match)
      rownames(RNASeq[[1]]) <- sapply(strsplit(rownames(RNASeq[[1]]), "\\\\|"), function(X) return(X[1]))
      
      Bootstrap_flag <- TRUE
      num_samples <- length(RNASeq)
    } else {
      # Read the combined abundance matrix provided by the user (rows = transcripts, columns = samples)
      RNASeq <- read.delim(abundance_file, sep = "\t", row.names = 1)
      RNASeq <- as.matrix(RNASeq)
      
      # Clean transcript names (remove version/pipe delimiters)
      rownames(RNASeq) <- sapply(strsplit(rownames(RNASeq), "\\\\|"), function(X) return(X[1]))
      
      Bootstrap_flag <- FALSE
      num_samples <- ncol(RNASeq)
    }
    
    # 3. Calculate PSI values and path expressions
    PSIss <- GetPSI_FromTranRef(PathsxTranscript = EventXtrans,
                                   Samples = RNASeq,
                                   Bootstrap = Bootstrap_flag,
                                   Filter = FALSE)
    
    PSI <- PSIss\$PSI
    Expression <- PSIss\$ExpEvs
    
    # Save intermediate PSI and Expression objects
    saveRDS(PSI, "PSI.rds")
    saveRDS(Expression, "Expression.rds")
    
    # 4. Perform statistical analysis using EventPointer_Bootstraps
    # Dynamically create the design matrix based on the number of samples
    half_samples <- floor(num_samples / 2)
    Dmatrix <- cbind(1, c(rep(0, half_samples), rep(1, num_samples - half_samples)))
    Cmatrix <- matrix(c(0, 1), nrow = 2)
    
    Fit_bots <- EventPointer_Bootstraps(PSI = PSI,
                                   Design = Dmatrix,
                                   Contrast = Cmatrix,
                                   cores = 1,
                                   ram = 1,
                                   nbootstraps = 10,
                                   UsePseudoAligBootstrap = Bootstrap_flag)
    
    # Save statistical results
    saveRDS(Fit_bots, "Fit_bots.rds")
    
    # Extract and save top-ranked events
    res_table <- ResulTable(EP_Result = Fit_bots, coef = 1, number = 5)
    write.csv(res_table, "EventPointer_results_top5.csv", row.names = TRUE)
    
    # 5. Generate GTF files for IGV visualization
    SG_List <- EventXtrans\$SG_List
    PathEventsTxt <- file.path(Pathtxt, "EventsFound.txt")
    PathGTF <- "IGV_output"
    dir.create(PathGTF, showWarnings = FALSE, recursive = TRUE)
    
    EventPointer_RNASeq_TranRef_IGV(SG_List = SG_List, pathtoeventstable = PathEventsTxt, PathGTF = PathGTF)

    writeLines(c(
        '"BIOC_EVENTPOINTER_RNA_SEQ_TRANSCRIPTOME_PIPELINE":',
        paste0('    EventPointer: ', as.character(packageVersion('EventPointer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_transcriptome_pipeline.csv versions.yml
    """
}

workflow BIOC_EVENTPOINTER_RNA_SEQ_TRANSCRIPTOME_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference_transcriptome.gtf, abundance.tsv ] ]

    main:
    BIOC_EVENTPOINTER_RNA_SEQ_TRANSCRIPTOME_PIPELINE(ch_input)

    emit:
    tables   = BIOC_EVENTPOINTER_RNA_SEQ_TRANSCRIPTOME_PIPELINE.out.tables
    plots    = BIOC_EVENTPOINTER_RNA_SEQ_TRANSCRIPTOME_PIPELINE.out.plots
    objects  = BIOC_EVENTPOINTER_RNA_SEQ_TRANSCRIPTOME_PIPELINE.out.objects
    versions = BIOC_EVENTPOINTER_RNA_SEQ_TRANSCRIPTOME_PIPELINE.out.versions
}
