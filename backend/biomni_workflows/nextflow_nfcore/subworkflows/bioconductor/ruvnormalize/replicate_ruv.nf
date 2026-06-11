#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RUVnormalize — replicate_ruv
// Remove unwanted variation from gene expression data using both negative control genes and replicate samples.
// Input: expression_matrix.csv, negative_controls.txt, replicates_mapping.csv
// Container: quay.io/biocontainers/bioconductor-ruvnormalize:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RUVnormalize
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files
//  * 2. [Visualization & Output] Center the gene expression matrix
//  * 3. [Visualization & Output] Run replicate-based RUV correction using naiveReplicateRUV
//  * 4. [Visualization & Output] Prepare visualization parameters
//  * 5. [Visualization & Output] Visualize the corrected data using SVD/PCA plotting
//  * 6. [Visualization & Output] Save outputs

nextflow.enable.dsl = 2

process BIOC_RUVNORMALIZE_REPLICATE_RUV {
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
        library(RUVnormalize)
        
        # --- Read user input files ---
        # Read expression matrix (samples as rows, genes as columns)
        Y <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Read negative control genes (indices or names)
        neg_ctrls <- readLines("negative_controls.txt")
        # Convert to numeric indices if possible, otherwise match names
        cIdx <- suppressWarnings(as.integer(neg_ctrls))
        if (any(is.na(cIdx))) {
          cIdx <- which(colnames(Y) %in% neg_ctrls)
        }
        
        # Read replicates mapping matrix (padded with -1)
        scIdx <- as.matrix(read.csv("replicates_mapping.csv", header = FALSE))
        storage.mode(scIdx) <- "integer"
        
        # --- Center the gene expression matrix ---
        Y <- scale(Y, scale=FALSE)
        
        # --- Run replicate-based RUV correction using naiveReplicateRUV ---
        sRes <- naiveReplicateRUV(Y, cIdx, scIdx, k=20)
        
        # --- Prepare visualization parameters ---
        # Determine nKeep (number of genes to keep based on variance)
        nKeep <- min(1260, ncol(Y))
        
        # Sort genes by their standard deviation in the corrected data
        sdY <- apply(sRes\$cY, 2, sd)
        ssd <- sort(sdY, decreasing=TRUE, index.return=TRUE)\$ix
        
        # Construct annotations and labels for plotting
        rny <- rownames(Y)
        if (is.null(rny)) {
          rny <- paste0("Sample_", seq_len(nrow(Y)))
          rownames(Y) <- rny
          rownames(sRes\$cY) <- rny
        }
        
        # Try to extract region and lab if rownames match the vignette format (e.g., "ID_region_lab")
        parts <- strsplit(rny, "_")
        if (all(sapply(parts, length) >= 3)) {
          lregions <- sapply(rny, function(s) strsplit(s, '_')[[1]][2])
          llabs <- sapply(rny, function(s) strsplit(s, '_')[[1]][3])
          lab.and.region <- apply(rbind(lregions, llabs), 2, function(v) paste(v, collapse='_'))
        } else {
          lab.and.region <- rny
        }
        
        # Create dummy binary annotation for plotting (since X is not provided)
        dummy_X <- rep(c(1, -1), length.out = nrow(Y))
        annot <- cbind(as.character(dummy_X))
        colnames(annot) <- 'gender'
        
        plAnnots <- list('gender'='categorical')
        gender.col <- c('-1' = "deeppink3", '1' = "blue")
        
        # --- Visualize the corrected data using SVD/PCA plotting ---
        pdf("svd_plot.pdf")
        svdResRep <- svdPlot(sRes\$cY[, ssd[1:nKeep], drop=FALSE], 
                             annot=annot, 
                             labels=lab.and.region, 
                             svdRes=NULL, 
                             plAnnots=plAnnots,                     
                             kColors=gender.col, file=NULL)
        dev.off()
        
        # --- Save outputs ---
        write.csv(sRes\$cY, "corrected_expression_matrix.csv", row.names = TRUE)
        saveRDS(sRes, "ruv_results.rds")
        saveRDS(svdResRep, "svd_results.rds")

    writeLines(c(
        '"BIOC_RUVNORMALIZE_REPLICATE_RUV":',
        paste0('    RUVnormalize: ', as.character(packageVersion('RUVnormalize')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_replicate_ruv.csv versions.yml
    """
}

workflow BIOC_RUVNORMALIZE_REPLICATE_RUV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, negative_controls.txt, replicates_mapping.csv ] ]

    main:
    BIOC_RUVNORMALIZE_REPLICATE_RUV(ch_input)

    emit:
    tables   = BIOC_RUVNORMALIZE_REPLICATE_RUV.out.tables
    plots    = BIOC_RUVNORMALIZE_REPLICATE_RUV.out.plots
    objects  = BIOC_RUVNORMALIZE_REPLICATE_RUV.out.objects
    versions = BIOC_RUVNORMALIZE_REPLICATE_RUV.out.versions
}
