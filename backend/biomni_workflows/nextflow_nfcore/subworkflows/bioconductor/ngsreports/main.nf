#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ngsreports — fastqc_quality_control_analysis
// Parse multiple FastQC reports, extract quality modules, and generate summary and detailed quality plots.
// Input: fastqc.zip, fastqc_extracted_dir
// Container: quay.io/biocontainers/bioconductor-ngsreports:2.12.1--r45hdfd78af_0
// R packages: dplyr, ggplot2, ngsReports, pander
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NGSREPORTS_FASTQC_QUALITY_CONTROL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ngsreports:2.12.1--r45hdfd78af_0"

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
    .bm_deps <- c("dplyr", "ggplot2", "ngsReports", "pander")
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
    library(ngsReports)
    library(ggplot2)
    library(dplyr)
    
    # ==========================================
    # 1. Load FastQC files into a FastqcDataList
    # ==========================================
    
    # Read exactly the declared user input files from the working directory
    zip_file <- "fastqc.zip"
    extracted_dir <- "fastqc_extracted_dir"
    
    if (file.exists(zip_file)) {
      files <- zip_file
    } else if (dir.exists(extracted_dir)) {
      # List files inside the extracted directory
      files <- list.files(extracted_dir, full.names = TRUE, recursive = TRUE)
      if (length(files) == 0) {
        files <- extracted_dir
      }
    } else {
      stop("Required input files 'fastqc.zip' or 'fastqc_extracted_dir' not found in the working directory.")
    }
    
    # Construct the FastqcDataList object
    fdl <- FastqcDataList(files)
    
    # Save the FastqcDataList object as an RDS file for downstream use
    saveRDS(fdl, "fastqc_data_list.rds")
    
    # ==========================================
    # 2. Extract specific modules or read totals
    # ==========================================
    
    # Extract Summary module for the first sample and save to CSV
    tryCatch({
      summary_info <- getModule(fdl[[1]], "Summary")
      write.csv(summary_info, "summary_module_first_sample.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not extract Summary module: ", e\$message)
    })
    
    # Extract read totals and save to CSV
    tryCatch({
      reads <- readTotals(fdl)
      write.csv(reads, "read_totals.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not extract read totals: ", e\$message)
    })
    
    # ==========================================
    # 3. Generate summary plots of PASS/WARN/FAIL status
    # ==========================================
    
    tryCatch({
      pdf("plot_summary.pdf")
      print(plotSummary(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotSummary: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # ==========================================
    # 4. Plot read totals
    # ==========================================
    
    tryCatch({
      pdf("plot_read_totals.pdf")
      print(plotReadTotals(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotReadTotals: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # ==========================================
    # 5. Visualize quality control metrics
    # ==========================================
    
    # --- Base Qualities ---
    tryCatch({
      pdf("plot_base_quals_first.pdf")
      print(plotBaseQuals(fdl[[1]]))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotBaseQuals for first sample: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_base_quals_all.pdf")
      print(plotBaseQuals(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotBaseQuals for all samples: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_base_quals_boxplot.pdf")
      print(plotBaseQuals(fdl[1:4], plotType = "boxplot"))
      dev.off()
    }, error = function(e) {
      message("plotBaseQuals(fdl[1:4], plotType = 'boxplot') failed, attempting safe fallback: ", e\$message)
      if (dev.cur() > 1) dev.off()
      tryCatch({
        pdf("plot_base_quals_boxplot.pdf")
        print(plotBaseQuals(fdl[1:min(4, length(fdl))], plotType = "boxplot"))
        dev.off()
      }, error = function(e2) {
        message("Fallback plotBaseQuals boxplot failed: ", e2\$message)
        if (dev.cur() > 1) dev.off()
      })
    })
    
    # --- Sequence Qualities ---
    tryCatch({
      pdf("plot_seq_quals_first.pdf")
      print(plotSeqQuals(fdl[[1]]))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotSeqQuals for first sample: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_seq_quals_all.pdf")
      print(plotSeqQuals(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotSeqQuals for all samples: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    r2 <- grepl("R2", names(fdl))
    tryCatch({
      pdf("plot_seq_quals_r2_line.pdf")
      print(plotSeqQuals(fdl[r2], plotType = "line"))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotSeqQuals for R2 samples: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # --- Sequence Content ---
    tryCatch({
      pdf("plot_seq_content_first.pdf")
      print(plotSeqContent(fdl[[1]]))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotSeqContent for first sample: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_seq_content_all.pdf")
      print(plotSeqContent(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotSeqContent for all samples: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_seq_content_line.pdf")
      print(plotSeqContent(fdl[1:2], plotType = "line", nc = 1))
      dev.off()
    }, error = function(e) {
      message("plotSeqContent(fdl[1:2], plotType = 'line', nc = 1) failed, attempting safe fallback: ", e\$message)
      if (dev.cur() > 1) dev.off()
      tryCatch({
        pdf("plot_seq_content_line.pdf")
        print(plotSeqContent(fdl[1:min(2, length(fdl))], plotType = "line", nc = 1))
        dev.off()
      }, error = function(e2) {
        message("Fallback plotSeqContent line failed: ", e2\$message)
        if (dev.cur() > 1) dev.off()
      })
    })
    
    # --- Adapter Content ---
    tryCatch({
      pdf("plot_adapter_content_first.pdf")
      print(plotAdapterContent(fdl[[1]]))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotAdapterContent for first sample: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_adapter_content_all.pdf")
      print(plotAdapterContent(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotAdapterContent for all samples: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # --- Duplication Levels ---
    tryCatch({
      pdf("plot_dup_levels_first.pdf")
      print(plotDupLevels(fdl[[1]]))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotDupLevels for first sample: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_dup_levels_all.pdf")
      print(plotDupLevels(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotDupLevels for all samples: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # --- GC Content ---
    tryCatch({
      gc_avail <- gcAvail(gcTheoretical, "Genome")
      write.csv(gc_avail, "gc_theoretical_avail_genome.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not query theoretical GC content: ", e\$message)
    })
    
    tryCatch({
      pdf("plot_gc_content_first.pdf")
      print(plotGcContent(fdl[[1]], species = "Hsapiens", gcType = "Transcriptome"))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotGcContent for first sample: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_gc_content_all.pdf")
      print(plotGcContent(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotGcContent for all samples: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_gc_content_line.pdf")
      print(plotGcContent(fdl, plotType = "line",  gcType = "Transcriptome"))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotGcContent line plot: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # --- Overrepresented Sequences ---
    tryCatch({
      pdf("plot_overrep_first.pdf")
      print(plotOverrep(fdl[[1]]))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotOverrep for first sample: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    tryCatch({
      pdf("plot_overrep_all.pdf")
      print(plotOverrep(fdl))
      dev.off()
    }, error = function(e) {
      message("Could not generate plotOverrep for all samples: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # ==========================================
    # 6. Export overrepresented sequences to FASTA
    # ==========================================
    
    tryCatch({
      overRep2Fasta(fdl, n = 10)
      message("Successfully exported overrepresented sequences to FASTA.")
    }, error = function(e) {
      message("Could not export overrepresented sequences to FASTA: ", e\$message)
    })

    writeLines(c(
        '"BIOC_NGSREPORTS_FASTQC_QUALITY_CONTROL_ANALYSIS":',
        paste0('        ngsreports: ', as.character(packageVersion("ngsreports")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastqc_quality_control_analysis.csv versions.yml
    """
}

workflow BIOC_NGSREPORTS_FASTQC_QUALITY_CONTROL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fastqc.zip, fastqc_extracted_dir ] ]

    main:
    BIOC_NGSREPORTS_FASTQC_QUALITY_CONTROL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NGSREPORTS_FASTQC_QUALITY_CONTROL_ANALYSIS.out.tables
    plots    = BIOC_NGSREPORTS_FASTQC_QUALITY_CONTROL_ANALYSIS.out.plots
    objects  = BIOC_NGSREPORTS_FASTQC_QUALITY_CONTROL_ANALYSIS.out.objects
    versions = BIOC_NGSREPORTS_FASTQC_QUALITY_CONTROL_ANALYSIS.out.versions
}
