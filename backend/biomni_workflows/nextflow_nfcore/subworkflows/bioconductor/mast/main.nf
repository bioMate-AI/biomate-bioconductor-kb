#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAST — qpcr_fluidigm_workflow
// Import qPCR cycle threshold (Ct) data from a flat data frame, convert to expression thresholds, filter outliers, and perform differential expression testing usi
// Input: qpcr_data.csv
// Container: quay.io/biocontainers/bioconductor-mast:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MAST, data.table, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Compute expression threshold (Et) from cycle threshold (Ct) using computeEtFromCt. 2. Import flat data frame into a FluidigmAssay 

nextflow.enable.dsl = 2

process BIOC_MAST_QPCR_FLUIDIGM_WORKFLOW {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(MAST)
    library(ggplot2)
    library(data.table)
    
    # 1. Read the user input file
    if (!file.exists("qpcr_data.csv")) {
      stop("Error: 'qpcr_data.csv' not found in the working directory.")
    }
    vbeta <- read.csv("qpcr_data.csv", stringsAsFactors = TRUE)
    
    # 2. Compute expression threshold (Et) from cycle threshold (Ct)
    vbeta <- computeEtFromCt(vbeta)
    
    # Dynamically identify columns to avoid hardcoding vignette-specific names
    cols <- colnames(vbeta)
    gene_col <- grep("gene|primer", cols, ignore.case = TRUE, value = TRUE)[1]
    if (is.na(gene_col)) gene_col <- cols[1]
    
    meta_cols <- setdiff(cols, c(gene_col, "Ct", "Et"))
    if (length(meta_cols) == 0) {
      stop("Error: No metadata columns found in the input data.")
    }
    first_meta <- meta_cols[1]
    
    # 3. Import flat data frame into a FluidigmAssay object
    vbeta.fa <- FromFlatDF(vbeta, 
                           idvars = meta_cols,
                           primerid = gene_col, 
                           measurement = 'Et', 
                           geneid = gene_col,  
                           cellvars = meta_cols,
                           phenovars = meta_cols, 
                           id = 'vbeta all', 
                           class = 'FluidigmAssay')
    
    # Save the imported assay object
    saveRDS(vbeta.fa, "vbeta_assay.rds")
    
    # 4. Subset and split the assay by cell metadata
    sub1 <- vbeta.fa[, 1:min(10, ncol(vbeta.fa))]
    
    first_level <- as.character(unique(colData(vbeta.fa)[[first_meta]])[1])
    sub2 <- vbeta.fa[, colData(vbeta.fa)[[first_meta]] == first_level]
    
    sub3 <- vbeta.fa[1:min(5, nrow(vbeta.fa)), 1:min(10, ncol(vbeta.fa))]
    
    sp1 <- split(vbeta.fa, first_meta)
    if (length(sp1) >= 2) {
      cbind(sp1[[1]], sp1[[2]])
    } else {
      sp1[[1]]
    }
    
    vbeta.split <- split(vbeta.fa, first_meta)
    
    # 5. Filter low-quality wells and plot concordance
    pdf("concordance_plot.pdf", width=8, height=6)
    if (length(vbeta.split) >= 2) {
      plotSCAConcordance(vbeta.split[[1]], vbeta.split[[2]],
                         filterCriteria=list(nOutlier = 1, sigmaContinuous = 9,
                             sigmaProportion = 9))
    } else {
      plot.new()
      text(0.5, 0.5, "Not enough groups to plot concordance")
    }
    dev.off()
    
    vbeta.filtered <- mast_filter(vbeta.fa, groups=first_meta)
    saveRDS(vbeta.filtered, "vbeta_filtered.rds")
    
    was.filtered <- mast_filter(vbeta.fa, apply_filter=FALSE)
    write.csv(as.data.frame(was.filtered), "was_filtered.csv", row.names=TRUE)
    
    pdf("burden_of_filtering.pdf", width=8, height=6)
    burdenOfFiltering(vbeta.fa, first_meta, byGroup=TRUE)
    dev.off()
    
    # 6. Fit a Hurdle model and perform differential expression testing
    vbeta.1 <- vbeta.fa[1:min(20, nrow(vbeta.fa)), ]
    
    valid_covariates <- Filter(function(x) length(unique(colData(vbeta.1)[[x]])) > 1, meta_cols)
    
    if (length(valid_covariates) > 0) {
      test_var <- valid_covariates[1]
      model_vars <- valid_covariates[1:min(2, length(valid_covariates))]
      fmla <- as.formula(paste("~", paste(model_vars, collapse = " + ")))
    } else {
      test_var <- meta_cols[1]
      fmla <- ~ 1
    }
    
    zlm.output <- zlm(fmla, vbeta.1)
    saveRDS(zlm.output, "zlm_output.rds")
    
    coefAndCI <- summary(zlm.output, logFC=FALSE)\$datatable
    write.csv(coefAndCI, "coef_and_ci.csv", row.names=FALSE)
    
    if (length(valid_covariates) > 0) {
      zlm.lr <- lrTest(zlm.output, test_var)
      saveRDS(zlm.lr, "zlm_lr_test.rds")
      
      # Two-sample Likelihood Ratio Test
      ref_level <- as.character(unique(colData(vbeta.1)[[test_var]])[1])
      two.sample <- tryCatch({
        LRT(vbeta.1, test_var, referent=ref_level)
      }, error = function(e) {
        warning("LRT failed: ", e\$message)
        NULL
      })
      
      if (!is.null(two.sample)) {
        write.csv(two.sample, "two_sample_lrt.csv", row.names=FALSE)
      }
    }

    writeLines(c(
        '"BIOC_MAST_QPCR_FLUIDIGM_WORKFLOW":',
        paste0('    MAST: ', as.character(packageVersion('MAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qpcr_fluidigm_workflow.csv versions.yml
    """
}

workflow BIOC_MAST_QPCR_FLUIDIGM_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ qpcr_data.csv ] ]

    main:
    BIOC_MAST_QPCR_FLUIDIGM_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MAST_QPCR_FLUIDIGM_WORKFLOW.out.tables
    plots    = BIOC_MAST_QPCR_FLUIDIGM_WORKFLOW.out.plots
    objects  = BIOC_MAST_QPCR_FLUIDIGM_WORKFLOW.out.objects
    versions = BIOC_MAST_QPCR_FLUIDIGM_WORKFLOW.out.versions
}
