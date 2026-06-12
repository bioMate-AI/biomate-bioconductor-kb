#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SingleMoleculeFootprinting — supervised_tf_sorting
// Perform supervised single-molecule sorting and state quantification based on prior TF binding site annotations.
// Input: regions.bed, coldata.csv
// Container: 2.0.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, SingleMoleculeFootprinting, dplyr, ggplot2, readr, rtracklayer
// Visualizations: heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGLEMOLECULEFOOTPRINTING_SUPERVISED_TF_SORTING {
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
    .bm_deps <- c("SingleMoleculeFootprinting", "GenomicRanges", "rtracklayer", "dplyr", "readr", "ggplot2", "genome_name")
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
    
    library(SingleMoleculeFootprinting)
    library(GenomicRanges)
    library(rtracklayer)
    library(dplyr)
    library(readr)
    library(ggplot2)
    
    # --- Load Inputs ---
    message("Stage 1: Loading inputs...")
    regions <- rtracklayer::import("regions.bed")
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Determine genome
    genome_name <- if ("Genome" %in% colnames(coldata)) coldata\$Genome[1] else "BSgenome.Mmusculus.UCSC.mm10"
    message(paste("Using genome:", genome_name))
    if (!requireNamespace(genome_name, quietly = TRUE)) {
      stop(paste("Required genome package", genome_name, "is not installed."))
    }
    library(genome_name, character.only = TRUE)
    genome_obj <- get(genome_name)
    
    # Create QuasR sample file
    sample_file_path <- "sample_file.txt"
    write.table(coldata[, c("FileName", "SampleName")], file = sample_file_path, sep = "\t", row.names = FALSE, quote = FALSE)
    
    # --- Call Context Methylation ---
    message("Stage 2: Calling Context Methylation...")
    # Use the first region as the TF binding site of interest
    roi <- regions[1]
    roi_resized <- IRanges::resize(roi, 500, "center")
    
    meth_data <- tryCatch({
      CallContextMethylation(
        sampleFile = sample_file_path,
        samples = coldata\$SampleName,
        genome = genome_obj,
        RegionOfInterest = roi_resized,
        coverage = 20,
        returnSM = TRUE,
        verbose = TRUE,
        clObj = NULL
      )
    }, error = function(e) {
      message("CallContextMethylation failed: ", e\$message)
      NULL
    })
    
    if (!is.null(meth_data)) {
      # Save bulk methylation
      bulk_meth_df <- as.data.frame(meth_data[[1]])
      write.csv(bulk_meth_df, "bulk_methylation.csv", row.names = FALSE)
      
      # --- Supervised Sorting by Single TF ---
      message("Stage 3: Sorting reads by single TF...")
      # Prepare TFBS
      TFBS <- roi
      TFBS\$TF <- if ("name" %in% colnames(mcols(TFBS))) TFBS\$name else "TF"
      
      meth_sm <- meth_data[[2]] # List of matrices for all samples
      
      sorted_reads <- tryCatch({
        SortReadsBySingleTF(
          MethSM = meth_sm,
          TFBS = TFBS
        )
      }, error = function(e) {
        message("SortReadsBySingleTF failed: ", e\$message)
        NULL
      })
      
      if (!is.null(sorted_reads)) {
        # --- State Quantification ---
        message("Stage 4: Quantifying states...")
        states <- SingleTFStates()
        quant_df <- tryCatch({
          StateQuantification(SortedReads = sorted_reads, states = states)
        }, error = function(e) {
          message("StateQuantification failed: ", e\$message)
          NULL
        })
        
        if (!is.null(quant_df)) {
          write.csv(quant_df, "state_quantification.csv", row.names = FALSE)
        } else {
          write.csv(data.frame(Status = "StateQuantification failed"), "state_quantification.csv", row.names = FALSE)
        }
        
        # Save sorted reads summary (lengths of each pattern)
        summary_list <- lapply(sorted_reads, function(sample_reads) {
          data.frame(Pattern = names(sample_reads), Count = sapply(sample_reads, length))
        })
        summary_df <- dplyr::bind_rows(summary_list, .id = "Sample")
        write.csv(summary_df, "sorted_reads_summary.csv", row.names = FALSE)
        
        # --- Visualization ---
        message("Stage 5: Generating Plots...")
        p_sm <- tryCatch({
          PlotSM(
            MethSM = meth_sm,
            RegionOfInterest = roi_resized,
            sorting.strategy = "classical",
            SortedReads = sorted_reads
          )
        }, error = function(e) {
          ggplot() + labs(title = "PlotSM failed")
        })
        ggplot2::ggsave("single_molecule_sorted_heatmap.pdf", plot = p_sm, width = 10, height = 8)
        
        p_quant <- tryCatch({
          StateQuantificationPlot(SortedReads = sorted_reads, states = states)
        }, error = function(e) {
          ggplot() + labs(title = "StateQuantificationPlot failed")
        })
        ggplot2::ggsave("state_quantification_plot.pdf", plot = p_quant, width = 8, height = 6)
        
      } else {
        write.csv(data.frame(Status = "SortReadsBySingleTF failed"), "state_quantification.csv", row.names = FALSE)
        write.csv(data.frame(Status = "SortReadsBySingleTF failed"), "sorted_reads_summary.csv", row.names = FALSE)
        pdf("single_molecule_sorted_heatmap.pdf")
        plot.new()
        text(0.5, 0.5, "SortReadsBySingleTF failed")
        dev.off()
        pdf("state_quantification_plot.pdf")
        plot.new()
        text(0.5, 0.5, "SortReadsBySingleTF failed")
        dev.off()
      }
    } else {
      write.csv(data.frame(Status = "CallContextMethylation failed"), "bulk_methylation.csv", row.names = FALSE)
      write.csv(data.frame(Status = "CallContextMethylation failed"), "state_quantification.csv", row.names = FALSE)
      write.csv(data.frame(Status = "CallContextMethylation failed"), "sorted_reads_summary.csv", row.names = FALSE)
      pdf("single_molecule_sorted_heatmap.pdf")
      plot.new()
      text(0.5, 0.5, "CallContextMethylation failed")
      dev.off()
      pdf("state_quantification_plot.pdf")
      plot.new()
      text(0.5, 0.5, "CallContextMethylation failed")
      dev.off()
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SINGLEMOLECULEFOOTPRINTING_SUPERVISED_TF_SORTING":',
        paste0('    SingleMoleculeFootprinting: ', as.character(packageVersion('SingleMoleculeFootprinting')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_tf_sorting.csv versions.yml
    """
}

workflow BIOC_SINGLEMOLECULEFOOTPRINTING_SUPERVISED_TF_SORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SINGLEMOLECULEFOOTPRINTING_SUPERVISED_TF_SORTING(ch_input)

    emit:
    tables   = BIOC_SINGLEMOLECULEFOOTPRINTING_SUPERVISED_TF_SORTING.out.tables
    plots    = BIOC_SINGLEMOLECULEFOOTPRINTING_SUPERVISED_TF_SORTING.out.plots
    objects  = BIOC_SINGLEMOLECULEFOOTPRINTING_SUPERVISED_TF_SORTING.out.objects
    versions = BIOC_SINGLEMOLECULEFOOTPRINTING_SUPERVISED_TF_SORTING.out.versions
}
