#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqvartools — iterative_variant_processing
// Use block, range, window, or list iterators to process large genomic datasets in memory-efficient chunks.
// Input: file.gds
// Container: quay.io/biocontainers/bioconductor-seqvartools:1.48.0--r45hdfd78af_0
// R packages: GenomicRanges, SeqVarTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQVARTOOLS_ITERATIVE_VARIANT_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqvartools:1.48.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "SeqVarTools")
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
    library(SeqVarTools)
    library(GenomicRanges)
    
    # Verify input file exists
    gds_file <- "file.gds"
    if (!file.exists(gds_file)) {
        stop(paste("Required input file", gds_file, "not found in the working directory."))
    }
    
    # 1. Open GDS file and wrap it in a SeqVarData object
    gds <- seqOpen(gds_file)
    seqData <- SeqVarData(gds)
    
    # ==========================================
    # Stage 2 & 3: Block Iterator
    # ==========================================
    iterator <- SeqVarBlockIterator(seqData, variantBlock=500)
    var.info.block <- list(variantInfo(iterator))
    i <- 2
    while(iterateFilter(iterator)) {
        var.info.block[[i]] <- variantInfo(iterator)
        i <- i + 1
    }
    lapply(var.info.block, head)
    saveRDS(var.info.block, "block_iterator_results.rds")
    
    seqResetFilter(seqData)
    
    # Block Iterator with pre-filtering
    seqSetFilter(seqData, variant.sel=1:100)
    iterator <- SeqVarBlockIterator(seqData, variantBlock=500)
    var.info.filtered <- variantInfo(iterator)
    nrow(var.info.filtered)
    iterateFilter(iterator)
    saveRDS(var.info.filtered, "filtered_block_iterator_results.rds")
    
    seqResetFilter(seqData)
    
    # ==========================================
    # Stage 2 & 3: Range Iterator
    # ==========================================
    gr <- GRanges(seqnames=rep(1,3), 
                  ranges=IRanges(start=c(1e6, 2e6, 3e6), width=1e6))
    iterator <- SeqVarRangeIterator(seqData, variantRanges=gr)
    var.info.range <- list(variantInfo(iterator))
    i <- 2
    while(iterateFilter(iterator)) {
        var.info.range[[i]] <- variantInfo(iterator)
        i <- i + 1
    }
    lapply(var.info.range, head)
    saveRDS(var.info.range, "range_iterator_results.rds")
    
    seqResetFilter(seqData)
    
    # ==========================================
    # Stage 2 & 3: Window Iterator
    # ==========================================
    # Note: We attempt to filter for chromosome 22. If chromosome 22 is not present
    # in the input GDS, we fall back to the first available chromosome to ensure robustness.
    available_chroms <- seqGetFilter(seqData)\$chromosome
    target_chrom <- "22"
    if (!(target_chrom %in% available_chroms) && length(available_chroms) > 0) {
        target_chrom <- available_chroms[1]
    }
    
    seqSetFilterChrom(seqData, include=target_chrom)
    iterator <- SeqVarWindowIterator(seqData, windowSize=10000, 
                                     windowShift=5000)
    var.info.window <- list(variantInfo(iterator))
    i <- 2
    while(iterateFilter(iterator)) {
        var.info.window[[i]] <- variantInfo(iterator)
        i <- i + 1
    }
    lapply(var.info.window, head)
    saveRDS(var.info.window, "window_iterator_results.rds")
    
    seqResetFilter(seqData)
    
    # ==========================================
    # Stage 2 & 3: List Iterator
    # ==========================================
    gr_list <- GRangesList(
      GRanges(seqnames=rep(target_chrom, 2), 
              ranges=IRanges(start=c(16e6, 17e6), width=1e6)),
      GRanges(seqnames=rep(target_chrom, 2), 
              ranges=IRanges(start=c(18e6, 20e6), width=1e6)))
    iterator <- SeqVarListIterator(seqData, variantRanges=gr_list)
    var.info.list <- list(variantInfo(iterator))
    i <- 2
    while(iterateFilter(iterator)) {
        var.info.list[[i]] <- variantInfo(iterator)
        i <- i + 1
    }
    lapply(var.info.list, head)
    saveRDS(var.info.list, "list_iterator_results.rds")
    
    # ==========================================
    # Stage 4: Reset Iterator
    # ==========================================
    var.info.post <- variantInfo(iterator)
    resetIterator(iterator)
    var.info.reset <- variantInfo(iterator)
    
    # Save the reset verification results
    reset_verification <- list(
        post_iteration = var.info.post,
        post_reset = var.info.reset
    )
    saveRDS(reset_verification, "iterator_reset_verification.rds")
    
    # Close the GDS file
    seqClose(gds)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SEQVARTOOLS_ITERATIVE_VARIANT_PROCESSING":
        seqvartools: \$(Rscript -e 'cat(as.character(packageVersion("seqvartools")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iterative_variant_processing.csv versions.yml
    """
}

workflow BIOC_SEQVARTOOLS_ITERATIVE_VARIANT_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.gds ] ]

    main:
    BIOC_SEQVARTOOLS_ITERATIVE_VARIANT_PROCESSING(ch_input)

    emit:
    tables   = BIOC_SEQVARTOOLS_ITERATIVE_VARIANT_PROCESSING.out.tables
    plots    = BIOC_SEQVARTOOLS_ITERATIVE_VARIANT_PROCESSING.out.plots
    objects  = BIOC_SEQVARTOOLS_ITERATIVE_VARIANT_PROCESSING.out.objects
    versions = BIOC_SEQVARTOOLS_ITERATIVE_VARIANT_PROCESSING.out.versions
}
