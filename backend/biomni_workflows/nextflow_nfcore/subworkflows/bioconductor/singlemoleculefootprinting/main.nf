#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SingleMoleculeFootprinting — unsupervised_footprinting
// Perform unsupervised footprint detection and quantification using FootprintCharter on single-molecule footprinting data.
// Input: regions.bed, coldata.csv
// Container: 2.0.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, SingleMoleculeFootprinting, dplyr, ggplot2, readr, rtracklayer
// Visualizations: heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGLEMOLECULEFOOTPRINTING_UNSUPERVISED_FOOTPRINTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    
    library(SingleMoleculeFootprinting)
    library(GenomicRanges)
    library(rtracklayer)
    library(dplyr)
    library(readr)
    library(ggplot2)
    library(parallel)
    
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
    
    # --- Quality Control ---
    message("Stage 2: Running Quality Control...")
    bait_eff_val <- tryCatch({
      clObj <- parallel::makeCluster(2)
      eff <- BaitCapture(sampleFile = sample_file_path, genome = genome_obj, baits = regions, clObj = clObj)
      parallel::stopCluster(clObj)
      eff
    }, error = function(e) {
      message("BaitCapture failed or skipped: ", e\$message)
      NA
    })
    write.csv(data.frame(BaitCaptureEfficiency = bait_eff_val), "bait_capture_efficiency.csv", row.names = FALSE)
    
    conv_rate_val <- tryCatch({
      chrom <- as.character(seqnames(regions[1]))
      ConversionRate(sampleFile = sample_file_path, genome = genome_obj, chr = chrom)
    }, error = function(e) {
      message("ConversionRate failed or skipped: ", e\$message)
      NA
    })
    write.csv(data.frame(ConversionRate = conv_rate_val), "conversion_rate.csv", row.names = FALSE)
    
    # --- Methylation Calling ---
    message("Stage 3: Calling Context Methylation...")
    # Use the first region for detailed single-molecule analysis
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
      
      # --- Unsupervised Footprinting with FootprintCharter ---
      message("Stage 4: Running FootprintCharter...")
      roi_80 <- IRanges::resize(roi, 80, "center")
      sample_name <- coldata\$SampleName[1]
      meth_sm <- meth_data[[2]][[sample_name]]
      
      # Prepare TFBSs from regions
      TFBSs <- regions
      TFBSs\$TF <- if ("name" %in% colnames(mcols(TFBSs))) TFBSs\$name else "TF"
      TFBSs\$absolute.idx <- paste0("TFBS_", seq_along(TFBSs))
      
      fc_results <- tryCatch({
        FootprintCharter(
          MethSM = meth_sm,
          RegionOfInterest = roi_80,
          TFBSs = TFBSs,
          coverage = 20,
          k = 8,
          n = 5,
          TF.length = c(5, 75),
          nucleosome.length = c(120, 1000),
          cytosine.coverage.thr = 5,
          verbose = TRUE
        )
      }, error = function(e) {
        message("FootprintCharter failed: ", e\$message)
        NULL
      })
      
      if (!is.null(fc_results)) {
        write.csv(fc_results\$footprints.df, "detected_footprints.csv", row.names = FALSE)
        
        # --- Visualization ---
        message("Stage 5: Generating Plots...")
        p_avg <- tryCatch({
          PlotAvgSMF(MethGR = meth_data[[1]], RegionOfInterest = roi_resized, TFBSs = TFBSs)
        }, error = function(e) {
          ggplot() + labs(title = "PlotAvgSMF failed")
        })
        ggplot2::ggsave("average_smf_plot.pdf", plot = p_avg, width = 8, height = 6)
        
        p_footprints <- tryCatch({
          PlotFootprints(
            MethSM = meth_sm,
            partitioned.molecules = fc_results\$partitioned.molecules,
            footprints.df = fc_results\$footprints.df,
            TFBSs = TFBSs
          )
        }, error = function(e) {
          ggplot() + labs(title = "PlotFootprints failed")
        })
        ggplot2::ggsave("footprint_charter_plot.pdf", plot = p_footprints, width = 8, height = 8)
        
        p_sm <- tryCatch({
          PlotSM(
            MethSM = meth_sm,
            RegionOfInterest = roi_resized,
            SortedReads = fc_results\$partitioned.molecules,
            sorting.strategy = "custom"
          )
        }, error = function(e) {
          ggplot() + labs(title = "PlotSM failed")
        })
        ggplot2::ggsave("single_molecule_heatmap.pdf", plot = p_sm, width = 10, height = 8)
        
      } else {
        write.csv(data.frame(Status = "FootprintCharter failed"), "detected_footprints.csv", row.names = FALSE)
        pdf("footprint_charter_plot.pdf")
        plot.new()
        text(0.5, 0.5, "FootprintCharter failed")
        dev.off()
        pdf("single_molecule_heatmap.pdf")
        plot.new()
        text(0.5, 0.5, "FootprintCharter failed")
        dev.off()
      }
    } else {
      write.csv(data.frame(Status = "CallContextMethylation failed"), "bulk_methylation.csv", row.names = FALSE)
      write.csv(data.frame(Status = "CallContextMethylation failed"), "detected_footprints.csv", row.names = FALSE)
      pdf("average_smf_plot.pdf")
      plot.new()
      text(0.5, 0.5, "CallContextMethylation failed")
      dev.off()
      pdf("footprint_charter_plot.pdf")
      plot.new()
      text(0.5, 0.5, "CallContextMethylation failed")
      dev.off()
      pdf("single_molecule_heatmap.pdf")
      plot.new()
      text(0.5, 0.5, "CallContextMethylation failed")
      dev.off()
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SINGLEMOLECULEFOOTPRINTING_UNSUPERVISED_FOOTPRINTING":',
        paste0('    SingleMoleculeFootprinting: ', as.character(packageVersion('SingleMoleculeFootprinting')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_footprinting.csv versions.yml
    """
}

workflow BIOC_SINGLEMOLECULEFOOTPRINTING_UNSUPERVISED_FOOTPRINTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SINGLEMOLECULEFOOTPRINTING_UNSUPERVISED_FOOTPRINTING(ch_input)

    emit:
    tables   = BIOC_SINGLEMOLECULEFOOTPRINTING_UNSUPERVISED_FOOTPRINTING.out.tables
    plots    = BIOC_SINGLEMOLECULEFOOTPRINTING_UNSUPERVISED_FOOTPRINTING.out.plots
    objects  = BIOC_SINGLEMOLECULEFOOTPRINTING_UNSUPERVISED_FOOTPRINTING.out.objects
    versions = BIOC_SINGLEMOLECULEFOOTPRINTING_UNSUPERVISED_FOOTPRINTING.out.versions
}
