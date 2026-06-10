#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rfastp — umi_preprocessing
// Preprocess paired-end FASTQ files containing Unique Molecular Identifiers (UMIs) to extract and append UMIs to read headers.
// Input: pe_read1, pe_read2
// Container: quay.io/biocontainers/bioconductor-rfastp:1.20.1--r45ha27e39d_0
// Requires: Rfastp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run rfastp with UMI extraction enabled and specified location/length
//  * 2. [Core Analysis] Run rfastp with customized UMI prefix and formatting options

nextflow.enable.dsl = 2

process BIOC_RFASTP_UMI_PREPROCESSING {
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
    .bm_deps <- c("Rfastp")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(Rfastp)
    
    # Define input files exactly as declared in the user input requirements
    pe_read1 <- "pe_read1"
    pe_read2 <- "pe_read2"
    
    # Verify that the input files exist before proceeding
    if (!file.exists(pe_read1)) {
      stop(paste("Error: Input file 'pe_read1' not found in the working directory:", getwd()))
    }
    if (!file.exists(pe_read2)) {
      stop(paste("Error: Input file 'pe_read2' not found in the working directory:", getwd()))
    }
    
    # Define output prefix for the processed files
    outputPrefix <- "umi_processed"
    
    # Stage 1: Run rfastp with UMI extraction enabled and specified location/length
    umi_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2, 
        outputFastq = paste0(outputPrefix, '_umi1'), umi = TRUE, umiLoc = "read1",
        umiLength = 16)
    
    # Save results from Stage 1
    saveRDS(umi_json_report, file = "umi_json_report_stage1.rds")
    
    tryCatch({
      df_summary1 <- qcSummary(umi_json_report)
      write.csv(df_summary1, file = "qc_summary_stage1.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not generate QC summary for Stage 1: ", e\$message)
    })
    
    tryCatch({
      df_trim1 <- trimSummary(umi_json_report)
      write.csv(df_trim1, file = "trim_summary_stage1.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not generate trim summary for Stage 1: ", e\$message)
    })
    
    
    # Stage 2: Run rfastp with customized UMI prefix and formatting options
    umi_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2, 
        outputFastq = paste0(outputPrefix, '_umi2'), umi = TRUE, umiLoc = "read1",
        umiLength = 16, umiPrefix = "#", umiNoConnection = TRUE, 
        umiIgnoreSeqNameSpace = TRUE)
    
    # Save results from Stage 2
    saveRDS(umi_json_report, file = "umi_json_report_stage2.rds")
    
    tryCatch({
      df_summary2 <- qcSummary(umi_json_report)
      write.csv(df_summary2, file = "qc_summary_stage2.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not generate QC summary for Stage 2: ", e\$message)
    })
    
    tryCatch({
      df_trim2 <- trimSummary(umi_json_report)
      write.csv(df_trim2, file = "trim_summary_stage2.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not generate trim summary for Stage 2: ", e\$message)
    })
    
    # Generate and save diagnostic plots from the final run
    tryCatch({
      p1 <- curvePlot(umi_json_report)
      pdf("base_quality_plot.pdf", width = 8, height = 6)
      print(p1)
      dev.off()
    }, error = function(e) {
      warning("Could not generate base quality plot: ", e\$message)
    })
    
    tryCatch({
      p2 <- curvePlot(umi_json_report, curve = "content_curves")
      pdf("gc_content_plot.pdf", width = 8, height = 6)
      print(p2)
      dev.off()
    }, error = function(e) {
      warning("Could not generate GC content plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RFASTP_UMI_PREPROCESSING":',
        paste0('    Rfastp: ', as.character(packageVersion('Rfastp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_umi_preprocessing.csv versions.yml
    """
}

workflow BIOC_RFASTP_UMI_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pe_read1, pe_read2 ] ]

    main:
    BIOC_RFASTP_UMI_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_RFASTP_UMI_PREPROCESSING.out.tables
    plots    = BIOC_RFASTP_UMI_PREPROCESSING.out.plots
    objects  = BIOC_RFASTP_UMI_PREPROCESSING.out.objects
    versions = BIOC_RFASTP_UMI_PREPROCESSING.out.versions
}
