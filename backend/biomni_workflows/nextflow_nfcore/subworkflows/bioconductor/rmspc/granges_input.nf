#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmspc — granges_input
// Run MSPC peak calling using GRanges objects loaded in the R environment.
// Input: GR1, GR2
// Container: quay.io/biocontainers/bioconductor-rmspc:1.16.0--r45hdfd78af_0
// Requires: GenomicRanges, rmspc, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load rmspc, GenomicRanges, and rtracklayer packages
//  * 2. [Input & Preparation] Import BED files as GRanges objects
//  * 3. [Core Analysis] Combine GRanges objects into a GRangesList
//  * 4. [Visualization & Output] Run the mspc function with the GRangesList as input, specifying thresholds, replicate type, and output options
//  * 5. [Core Analysis] Access the exit status and resulting GRanges objects

nextflow.enable.dsl = 2

process BIOC_RMSPC_GRANGES_INPUT {
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
    .bm_deps <- c("GenomicRanges", "rmspc", "rtracklayer")
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
    
    # 1. Load rmspc, GenomicRanges, and rtracklayer packages
    library(rmspc)
    library(GenomicRanges)
    library(rtracklayer)
    
    # Helper function to robustly load the input files (either as RDS GRanges or BED files)
    load_input <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Required input file not found:", filepath))
      }
      
      # Try reading as RDS first
      obj <- tryCatch({
        readRDS(filepath)
      }, error = function(e) {
        NULL
      })
      
      if (!is.null(obj) && inherits(obj, "GRanges")) {
        return(obj)
      }
      
      # If not an RDS GRanges object, import as BED
      obj <- tryCatch({
        rtracklayer::import(con = filepath, format = "bed")
      }, error = function(e) {
        stop(paste("Failed to load", filepath, "as RDS or BED file. Error:", e\$message))
      })
      
      return(obj)
    }
    
    # Determine the exact filenames in the working directory
    file1 <- if (file.exists("GR1")) "GR1" else if (file.exists("GR1.rds")) "GR1.rds" else "GR1"
    file2 <- if (file.exists("GR2")) "GR2" else if (file.exists("GR2.rds")) "GR2.rds" else "GR2"
    
    # 2. Import files as GRanges objects
    GR1 <- load_input(file1)
    GR2 <- load_input(file2)
    
    # 3. Combine GRanges objects into a GRangesList
    GR <- GenomicRanges::GRangesList("GR1" = GR1, "GR2" = GR2)
    
    # 4. Run the mspc function with the GRangesList as input, specifying thresholds, replicate type, and output options
    results <- mspc(
        input = GR, replicateType = "Biological",
        stringencyThreshold = 1e-8, weakThreshold = 1e-4,
        gamma =  1e-8, GRanges = TRUE, keep = FALSE,
        multipleIntersections = "Highest",
        c = 2,alpha = 0.05)
    
    # 5. Access the exit status and resulting GRanges objects
    status <- results\$status
    gr_objects <- results\$GRangesObjects
    
    print("MSPC Execution Status:")
    print(status)
    
    print("Tail of resulting GRanges Objects:")
    print(tail(gr_objects))
    
    # Write named output files for the meaningful results
    writeLines(as.character(status), "mspc_status.txt")
    saveRDS(results, "mspc_results.rds")
    
    if (!is.null(gr_objects)) {
      saveRDS(gr_objects, "mspc_granges_objects.rds")
      
      # Export Consensus Peaks if they exist in the output
      if ("ConsensusPeaks" %in% names(gr_objects)) {
        consensus <- gr_objects\$ConsensusPeaks
        rtracklayer::export(consensus, con = "consensus_peaks.bed", format = "bed")
        
        consensus_df <- as.data.frame(consensus)
        write.csv(consensus_df, "consensus_peaks.csv", row.names = FALSE)
      }
    }

    writeLines(c(
        '"BIOC_RMSPC_GRANGES_INPUT":',
        paste0('    rmspc: ', as.character(packageVersion('rmspc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_granges_input.csv versions.yml
    """
}

workflow BIOC_RMSPC_GRANGES_INPUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GR1, GR2 ] ]

    main:
    BIOC_RMSPC_GRANGES_INPUT(ch_input)

    emit:
    tables   = BIOC_RMSPC_GRANGES_INPUT.out.tables
    plots    = BIOC_RMSPC_GRANGES_INPUT.out.plots
    objects  = BIOC_RMSPC_GRANGES_INPUT.out.objects
    versions = BIOC_RMSPC_GRANGES_INPUT.out.versions
}
