#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SeqVarTools — variant_iteration
// Iterate over large genomic datasets using block, range, window, or list iterators to apply functions to subsets of variants.
// Input: gdsfile.gds
// Container: quay.io/biocontainers/bioconductor-seqvartools:1.48.0--r45hdfd78af_0
// R packages: GenomicRanges, SeqVarTools
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, SeqVarTools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Open GDS file and create a SeqVarData object
//  * 2. [Core Analysis] Use SeqVarBlockIterator to iterate through variants in consecutive blocks
//  * 3. [Core Analysis] Use SeqVarRangeIterator to iterate through variants within specified genomic ranges
//  * 4. [Core Analysis] Use SeqVarWindowIterator to iterate through variants in sliding genomic windows
//  * 5. [Core Analysis] Use SeqVarListIterator to iterate through custom lists of genomic ranges
//  * 6. [Core Analysis] Reset iterators back to the beginning using resetIterator

nextflow.enable.dsl = 2

process BIOC_SEQVARTOOLS_VARIANT_ITERATION {
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
        
        library(SeqVarTools)
        library(GenomicRanges)
        
        # Stage 1: Open GDS file and create a SeqVarData object
        # Read the user input file "gdsfile.gds" from the working directory
        gds <- seqOpen("gdsfile.gds")
        seqData <- SeqVarData(gds)
        
        # Stage 2: Use SeqVarBlockIterator to iterate through variants in consecutive blocks
        iterator <- SeqVarBlockIterator(seqData, variantBlock=500)
        var.info <- list(variantInfo(iterator))
        i <- 2
        while(iterateFilter(iterator)) {
            var.info[[i]] <- variantInfo(iterator)
            i <- i + 1
        }
        lapply(var.info, head)
        saveRDS(var.info, "block_iterator_var_info.rds")
        
        seqResetFilter(seqData)
        
        n_vars <- length(seqGetData(gds, "variant.id"))
        seqSetFilter(seqData, variant.sel=seq_len(min(100, n_vars)))
        iterator <- SeqVarBlockIterator(seqData, variantBlock=500)
        var.info_block2 <- variantInfo(iterator)
        nrow(var.info_block2)
        iterateFilter(iterator)
        saveRDS(var.info_block2, "block_iterator_subset_var_info.rds")
        
        seqResetFilter(seqData)
        
        chroms <- unique(seqGetData(gds, "chromosome"))
        chr1 <- chroms[1]
        chr2 <- chroms[min(2, length(chroms))]
        
        # Stage 3: Use SeqVarRangeIterator to iterate through variants within specified genomic ranges
        gr <- GRanges(seqnames=rep(chr1,3), 
                      ranges=IRanges(start=c(1e6, 2e6, 3e6), width=1e6))
        iterator <- SeqVarRangeIterator(seqData, variantRanges=gr)
        var.info <- list(variantInfo(iterator))
        i <- 2
        while(iterateFilter(iterator)) {
            var.info[[i]] <- variantInfo(iterator)
            i <- i + 1
        }
        lapply(var.info, head)
        saveRDS(var.info, "range_iterator_var_info.rds")
        
        seqResetFilter(seqData)
        
        # Stage 4: Use SeqVarWindowIterator to iterate through variants in sliding genomic windows
        seqSetFilterChrom(seqData, include=chr2)
        iterator <- SeqVarWindowIterator(seqData, windowSize=10000, 
                                         windowShift=5000)
        var.info <- list(variantInfo(iterator))
        i <- 2
        while(iterateFilter(iterator)) {
            var.info[[i]] <- variantInfo(iterator)
            i <- i + 1
        }
        lapply(var.info, head)
        saveRDS(var.info, "window_iterator_var_info.rds")
        
        seqResetFilter(seqData)
        
        # Stage 5: Use SeqVarListIterator to iterate through custom lists of genomic ranges
        gr <- GRangesList(
          GRanges(seqnames=rep(chr2,2), 
                  ranges=IRanges(start=c(16e6, 17e6), width=1e6)),
          GRanges(seqnames=rep(chr2,2), 
                  ranges=IRanges(start=c(18e6, 20e6), width=1e6)))
        iterator <- SeqVarListIterator(seqData, variantRanges=gr)
        var.info <- list(variantInfo(iterator))
        i <- 2
        while(iterateFilter(iterator)) {
            var.info[[i]] <- variantInfo(iterator)
            i <- i + 1
        }
        lapply(var.info, head)
        saveRDS(var.info, "list_iterator_var_info.rds")
        
        # Stage 6: Reset iterators back to the beginning using resetIterator
        var_info_before_reset <- variantInfo(iterator)
        resetIterator(iterator)
        var_info_after_reset <- variantInfo(iterator)
        
        saveRDS(list(before_reset = var_info_before_reset, after_reset = var_info_after_reset), "iterator_reset_comparison.rds")
        
        seqClose(gds)

    writeLines(c(
        '"BIOC_SEQVARTOOLS_VARIANT_ITERATION":',
        paste0('    SeqVarTools: ', as.character(packageVersion('SeqVarTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variant_iteration.csv versions.yml
    """
}

workflow BIOC_SEQVARTOOLS_VARIANT_ITERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gdsfile.gds ] ]

    main:
    BIOC_SEQVARTOOLS_VARIANT_ITERATION(ch_input)

    emit:
    tables   = BIOC_SEQVARTOOLS_VARIANT_ITERATION.out.tables
    plots    = BIOC_SEQVARTOOLS_VARIANT_ITERATION.out.plots
    objects  = BIOC_SEQVARTOOLS_VARIANT_ITERATION.out.objects
    versions = BIOC_SEQVARTOOLS_VARIANT_ITERATION.out.versions
}
