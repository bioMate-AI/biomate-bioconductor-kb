#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: maskBAD — standard_masking_and_rma
// Identify BAD probes in standard Affymetrix 3' IVT arrays, evaluate cutoffs, generate a masked AffyBatch, and estimate expression values using RMA.
// Input: raw_array_data.affybatch, external_sequence_mask.rda
// Container: quay.io/biocontainers/bioconductor-maskbad:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, maskBAD
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run mask() to calculate probe quality scores based on correlation differences between groups
//  * 2. [Visualization & Output] Determine a quality score cutoff using quantiles, manual inspection with plotProbe(), or comparison with external sequence data us
//  * 3. [Core Analysis] Generate a masked AffyBatch and custom CDF environment using prepareMaskedAffybatch()
//  * 4. [Core Analysis] Assign the custom CDF environment to the workspace
//  * 5. [Core Analysis] Perform background correction, normalization, and expression estimation using rma()

nextflow.enable.dsl = 2

process BIOC_MASKBAD_STANDARD_MASKING_AND_RMA {
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
    .bm_deps <- c("maskBAD", "affy")
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
    library(maskBAD)
    library(affy)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read raw_array_data.affybatch
    newAffyBatch <- tryCatch({
      readRDS("raw_array_data.affybatch")
    }, error = function(e) {
      env <- new.env()
      load("raw_array_data.affybatch", envir = env)
      objs <- ls(env)
      affy_objs <- objs[sapply(objs, function(x) inherits(env[[x]], "AffyBatch"))]
      if (length(affy_objs) > 0) {
        env[[affy_objs[1]]]
      } else {
        stop("No AffyBatch object found in raw_array_data.affybatch")
      }
    })
    
    # Run mask() to calculate probe quality scores
    n_samples <- length(sampleNames(newAffyBatch))
    ind <- rep(1:2, length.out = n_samples)
    exmask <- mask(newAffyBatch, ind = ind, verbose = FALSE, useExpr = FALSE)
    
    # Read external_sequence_mask.rda if provided
    sequenceMask <- NULL
    if (file.exists("external_sequence_mask.rda")) {
      seq_env <- new.env()
      load("external_sequence_mask.rda", envir = seq_env)
      objs <- ls(seq_env)
      for (o in objs) {
        if (inherits(seq_env[[o]], "data.frame")) {
          sequenceMask <- seq_env[[o]]
          break
        }
      }
    }
    
    # Evaluate the mask with the external sequence mask if available
    if (!is.null(sequenceMask)) {
      if (all(c("x", "y", "match") %in% colnames(sequenceMask))) {
        rownames(sequenceMask) <- paste(sequenceMask\$x, sequenceMask\$y, sep="_")
        rownames(exmask\$probes) <- paste(exmask\$probes\$x, exmask\$probes\$y, sep="_")
        
        overlapExSeq <- overlapExprExtMasks(
          exmask\$probes[, c("x", "y", "quality.score")],
          sequenceMask[, c("x", "y", "match")], 
          verbose = FALSE,
          cutoffs = quantile(exmask\$probes\$quality.score, seq(0, 1, 0.05), na.rm = TRUE)
        )
      }
    }
    
    # ==========================================
    # 2. PREPARE MASKED AFFYBATCH
    # ==========================================
    
    # Mask the AffyBatch object using the quality score cutoff
    affyBatchAfterMasking <- prepareMaskedAffybatch(
      affy = newAffyBatch,
      exmask = exmask\$probes,
      cutoff = quantile(exmask[[1]]\$quality.score, 0.22, na.rm = TRUE)
    )
    
    # Assign the newly generated CDF environment to the workspace
    # matching the cdfName slot of the masked AffyBatch
    new_cdf <- affyBatchAfterMasking[[2]]
    assign(cdfName(affyBatchAfterMasking[[1]]), new_cdf, envir = .GlobalEnv)
    
    # ==========================================
    # 3. DOCUMENTED WORKFLOW: rma_masking
    # ==========================================
    
    # Estimate expression values using rma
    rma_results <- rma(affyBatchAfterMasking[[1]])
    head(exprs(rma_results))
    
    # ==========================================
    # 4. WRITE OUTPUTS
    # ==========================================
    
    # Save expression matrix as CSV
    write.csv(exprs(rma_results), "rma_masked_expression.csv", row.names = TRUE)
    
    # Save ExpressionSet object as RDS
    saveRDS(rma_results, "rma_masked_expressionset.rds")
    
    # Generate diagnostic density plot
    pdf("rma_expression_density.pdf")
    plotDensity(exprs(rma_results), main="Density Plot of RMA Masked Expression", xlab="Log2 Intensity")
    dev.off()

    writeLines(c(
        '"BIOC_MASKBAD_STANDARD_MASKING_AND_RMA":',
        paste0('    maskBAD: ', as.character(packageVersion('maskBAD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_masking_and_rma.csv versions.yml
    """
}

workflow BIOC_MASKBAD_STANDARD_MASKING_AND_RMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_array_data.affybatch, external_sequence_mask.rda ] ]

    main:
    BIOC_MASKBAD_STANDARD_MASKING_AND_RMA(ch_input)

    emit:
    tables   = BIOC_MASKBAD_STANDARD_MASKING_AND_RMA.out.tables
    plots    = BIOC_MASKBAD_STANDARD_MASKING_AND_RMA.out.plots
    objects  = BIOC_MASKBAD_STANDARD_MASKING_AND_RMA.out.objects
    versions = BIOC_MASKBAD_STANDARD_MASKING_AND_RMA.out.versions
}
