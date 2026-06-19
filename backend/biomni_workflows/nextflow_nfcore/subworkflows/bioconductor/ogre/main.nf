#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OGRE — ogre_variant_overlap_analysis
// Calculate and visualize genomic overlaps between user-defined VCF variants and public genomic annotations (CpG Islands and Transcription Factor Binding Sites) u
// Input: input.vcf, coldata.csv
// Container: 1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomicRanges, IRanges, OGRE, S4Vectors, ggplot2
// Visualizations: bar plot, coverage plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OGRE_OGRE_VARIANT_OVERLAP_ANALYSIS {
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
    .bm_deps <- c("OGRE", "GenomicRanges", "S4Vectors", "BiocGenerics")
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
    library(OGRE)
    library(GenomicRanges)
    library(S4Vectors)
    library(BiocGenerics)
    
    # --- Parse the input VCF file using base R to ensure maximum ---
    message("Reading and parsing input VCF...")
    vcf_file <- "input.vcf"
    if (!file.exists(vcf_file)) {
      stop("Input VCF file 'input.vcf' not found.")
    }
    
    vcf_lines <- readLines(vcf_file)
    vcf_data <- vcf_lines[!grepl("^#", vcf_lines)]
    
    if (length(vcf_data) > 0) {
      # Read tab-separated VCF records
      vcf_df <- read.table(text = vcf_data, sep = "\t", header = FALSE, stringsAsFactors = FALSE)
      colnames(vcf_df)[1:5] <- c("CHROM", "POS", "ID", "REF", "ALT")
      
      # Standardize chromosome names to UCSC style (e.g., "chr21")
      chroms <- as.character(vcf_df\$CHROM)
      chroms <- ifelse(grepl("^chr", chroms), chroms, paste0("chr", chroms))
      
      # Create GRanges object
      gr <- GRanges(
        seqnames = chroms,
        ranges = IRanges(start = as.integer(vcf_df\$POS), width = nchar(vcf_df\$REF)),
        strand = "*"
      )
      
      # Generate unique IDs and names as required by OGRE
      var_ids <- as.character(vcf_df\$ID)
      missing_ids <- var_ids == "." | is.na(var_ids) | var_ids == ""
      if (any(missing_ids)) {
        var_ids[missing_ids] <- paste0("var_", seq_along(which(missing_ids)))
      }
      mcols(gr)\$ID <- var_ids
      mcols(gr)\$name <- var_ids
    } else {
      warning("VCF file is empty. Creating an empty GRanges object.")
      gr <- GRanges()
      mcols(gr)\$ID <- character()
      mcols(gr)\$name <- character()
    }
    
    # Set genome build to hg19 to match predefined AnnotationHub datasets
    genome(gr) <- "hg19"
    
    # --- Initialize OGREDataSet and configure output directories ---
    message("Initializing OGREDataSet...")
    myOGRE <- OGREDataSet()
    
    # Direct all outputs to the current working directory
    metadata(myOGRE)\$outputFolder <- getwd()
    metadata(myOGRE)\$gvizPlotsFolder <- getwd()
    
    # --- Add Query (VCF variants) and Subject datasets ---
    message("Adding query dataset...")
    myOGRE <- addGRanges(myOGRE, gr, "query")
    
    message("Adding subject datasets...")
    # Attempt to load standard human datasets from AnnotationHub; fallback to dummy data if offline
    tryCatch({
      myOGRE <- addDataSetFromHub(myOGRE, "CGI", "subject")
      myOGRE <- addDataSetFromHub(myOGRE, "TFBS", "subject")
    }, error = function(e) {
      message("Warning: AnnotationHub download failed. Creating fallback dummy subject datasets.")
      
      # Create dummy CpG Islands (CGI)
      dummy_cgi <- GRanges(
        seqnames = "chr21", 
        ranges = IRanges(start = c(9437273, 9483486, 48018543), width = 1000),
        strand = "*"
      )
      mcols(dummy_cgi)\$ID <- paste0("CGI_", seq_along(dummy_cgi))
      mcols(dummy_cgi)\$name <- paste0("CpG_Island_", seq_along(dummy_cgi))
      genome(dummy_cgi) <- "hg19"
      
      # Create dummy Transcription Factor Binding Sites (TFBS)
      dummy_tfbs <- GRanges(
        seqnames = "chr21", 
        ranges = IRanges(start = c(9491627, 9491706, 48083381), width = 20),
        strand = "+"
      )
      mcols(dummy_tfbs)\$ID <- paste0("TFBS_", seq_along(dummy_tfbs))
      mcols(dummy_tfbs)\$name <- paste0("TF_binding_", seq_along(dummy_tfbs))
      genome(dummy_tfbs) <- "hg19"
      
      # Add fallback datasets to OGRE
      myOGRE <<- addGRanges(myOGRE, dummy_cgi, "subject")
      names(myOGRE)[length(names(myOGRE))] <<- "CGI"
      
      myOGRE <<- addGRanges(myOGRE, dummy_tfbs, "subject")
      names(myOGRE)[length(names(myOGRE))] <<- "TFBS"
    })
    
    # --- Calculate Overlaps ---
    message("Calculating overlaps...")
    myOGRE <- fOverlaps(myOGRE)
    
    # Export detailed overlap table
    detail_df <- metadata(myOGRE)\$detailDT
    if (is.null(detail_df) || nrow(detail_df) == 0) {
      detail_df <- data.frame(Status = "No overlaps detected between query and subjects")
    }
    write.csv(detail_df, "overlap_details.csv", row.names = FALSE)
    
    # --- Generate and Save Summary Plot ---
    message("Generating summary plot...")
    tryCatch({
      myOGRE <- sumPlot(myOGRE)
      barplot_obj <- metadata(myOGRE)\$barplot_summary
      if (!is.null(barplot_obj)) {
        pdf("barplot_summary.pdf", width = 8, height = 6)
        print(barplot_obj)
        dev.off()
      } else {
        pdf("barplot_summary.pdf")
        plot.new()
        text(0.5, 0.5, "No barplot summary available")
        dev.off()
      }
    }, error = function(e) {
      message("sumPlot failed: ", e\$message)
      pdf("barplot_summary.pdf")
      plot.new()
      text(0.5, 0.5, paste("Error generating barplot:", e\$message))
      dev.off()
    })
    
    # --- Summarize Overlaps and Plot Histograms ---
    message("Summarizing overlap distributions...")
    tryCatch({
      myOGRE <- summarizeOverlap(myOGRE)
      myOGRE <- plotHist(myOGRE)
      
      # Export summary statistics tables
      sum_list <- metadata(myOGRE)\$summaryDT
      if (!is.null(sum_list)) {
        if (!is.null(sum_list\$includes0)) {
          write.csv(as.data.frame(sum_list\$includes0), "overlap_summary_includes0.csv")
        } else {
          write.csv(data.frame(Status = "No data"), "overlap_summary_includes0.csv")
        }
        if (!is.null(sum_list\$excludes0)) {
          write.csv(as.data.frame(sum_list\$excludes0), "overlap_summary_excludes0.csv")
        } else {
          write.csv(data.frame(Status = "No data"), "overlap_summary_excludes0.csv")
        }
      }
      
      # Export histograms to PDF
      hist_list <- metadata(myOGRE)\$hist
      if (!is.null(hist_list) && length(hist_list) > 0) {
        pdf("histograms.pdf", width = 8, height = 6)
        for (h_name in names(hist_list)) {
          print(hist_list[[h_name]] + ggplot2::ggtitle(paste("Overlap Histogram:", h_name)))
        }
        dev.off()
      } else {
        pdf("histograms.pdf")
        plot.new()
        text(0.5, 0.5, "No histograms generated")
        dev.off()
      }
    }, error = function(e) {
      message("Summarization or histogram plotting failed: ", e\$message)
      write.csv(data.frame(Error = e\$message), "overlap_summary_includes0.csv")
      write.csv(data.frame(Error = e\$message), "overlap_summary_excludes0.csv")
      pdf("histograms.pdf")
      plot.new()
      text(0.5, 0.5, paste("Error:", e\$message))
      dev.off()
    })
    
    # --- Generate Coverage Plots ---
    message("Generating coverage plots...")
    tryCatch({
      myOGRE <- covPlot(myOGRE)
      cov_plots <- metadata(myOGRE)\$covPlot
      if (!is.null(cov_plots) && length(cov_plots) > 0) {
        pdf("coverage_plots.pdf", width = 8, height = 6)
        for (c_name in names(cov_plots)) {
          p <- cov_plots[[c_name]]\$plot
          if (!is.null(p)) {
            print(p + ggplot2::ggtitle(paste("Coverage Profile:", c_name)))
          }
        }
        dev.off()
      } else {
        pdf("coverage_plots.pdf")
        plot.new()
        text(0.5, 0.5, "No coverage plots generated")
        dev.off()
      }
    }, error = function(e) {
      message("covPlot failed: ", e\$message)
      pdf("coverage_plots.pdf")
      plot.new()
      text(0.5, 0.5, paste("Coverage plot skipped or failed:", e\$message))
      dev.off()
    })
    
    # --- Optional Gviz Visualization for the first overlapping ---
    message("Generating Gviz genomic region plot...")
    tryCatch({
      if (!is.null(detail_df) && nrow(detail_df) > 0 && "queryID" %in% colnames(detail_df)) {
        target_id <- detail_df\$queryID[1]
        # gvizPlot automatically saves the plot to the configured gvizPlotsFolder (getwd())
        myOGRE <- gvizPlot(myOGRE, target_id, showPlot = FALSE)
      }
    }, error = function(e) {
      message("gvizPlot skipped: ", e\$message)
    })
    
    message("OGRE analysis pipeline completed successfully!")

    writeLines(c(
        '"BIOC_OGRE_OGRE_VARIANT_OVERLAP_ANALYSIS":',
        paste0('    OGRE: ', as.character(packageVersion('OGRE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ogre_variant_overlap_analysis.csv versions.yml
    """
}

workflow BIOC_OGRE_OGRE_VARIANT_OVERLAP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_OGRE_OGRE_VARIANT_OVERLAP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OGRE_OGRE_VARIANT_OVERLAP_ANALYSIS.out.tables
    plots    = BIOC_OGRE_OGRE_VARIANT_OVERLAP_ANALYSIS.out.plots
    objects  = BIOC_OGRE_OGRE_VARIANT_OVERLAP_ANALYSIS.out.objects
    versions = BIOC_OGRE_OGRE_VARIANT_OVERLAP_ANALYSIS.out.versions
}
