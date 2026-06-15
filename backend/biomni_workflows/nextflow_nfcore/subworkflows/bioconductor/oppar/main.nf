#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oppar — cancer_outlier_profile_analysis
// Identify up- and down-regulated outlier genes in disease samples compared to normal controls and extract outlier profiles.
// Input: eset
// Container: quay.io/biocontainers/bioconductor-oppar:1.38.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GO.db, limma, oppar, org.Hs.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define group factor (normal vs case)
//  * 2. [Core Analysis] Run opa() to generate the outlier profile matrix
//  * 3. [Core Analysis] Access profile matrix and quantiles
//  * 4. [Core Analysis] Extract outlier profiles for individual samples using getSampleOutlier()
//  * 5. [Core Analysis] Extract outliers for all samples or subtypes using getSubtypeProbes()

nextflow.enable.dsl = 2

process BIOC_OPPAR_CANCER_OUTLIER_PROFILE_ANALYSIS {
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
    .bm_deps <- c("oppar", "Biobase", "org.Hs.eg.db", "limma", "GO.db")
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
        library(oppar)
        library(Biobase)
        
        # Read the user-provided ExpressionSet from the working directory
        if (file.exists("eset")) {
          eset <- readRDS("eset")
        } else if (file.exists("eset.rds")) {
          eset <- readRDS("eset.rds")
        } else {
          stop("Error: ExpressionSet file 'eset' or 'eset.rds' not found in the working directory.")
        }
        
        # Stage 1: Define group factor (normal vs case)
        # Use 'group' from phenotype data if available, otherwise split samples in half
        if ("group" %in% varLabels(eset)) {
          g <- factor(eset\$group)
        } else if ("Group" %in% varLabels(eset)) {
          g <- factor(eset\$Group)
        } else {
          num_samples <- ncol(exprs(eset))
          num_normal <- max(1, floor(num_samples / 2))
          g <- factor(c(rep(0, num_normal), rep(1, num_samples - num_normal)))
        }
        
        # Stage 2: Run opa() to generate the outlier profile matrix
        tomlins.opa <- opa(eset, group = g, lower.quantile = 0.1)
        
        # Stage 3: Access profile matrix and quantiles
        profile_matrix_subset <- tomlins.opa\$profileMatrix[seq_len(min(6, nrow(tomlins.opa\$profileMatrix))), seq_len(min(5, ncol(tomlins.opa\$profileMatrix))), drop = FALSE]
        upper_q <- tomlins.opa\$upper.quantile
        lower_q <- tomlins.opa\$lower.quantile
        
        # Stage 4: Extract outlier profiles for individual samples using getSampleOutlier()
        sample_indices <- intersect(c(1, 5), seq_len(ncol(tomlins.opa\$profileMatrix)))
        sample_outliers <- getSampleOutlier(tomlins.opa, sample_indices)
        
        # Stage 5: Extract outliers for all samples or subtypes using getSubtypeProbes()
        outlier.list <- getSubtypeProbes(tomlins.opa, seq_len(ncol(tomlins.opa\$profileMatrix)))
        
        # Write meaningful results to output files
        write.csv(tomlins.opa\$profileMatrix, "outlier_profile_matrix.csv", row.names = TRUE)
        
        quantiles_df <- data.frame(
          upper_quantile = upper_q,
          lower_quantile = lower_q
        )
        write.csv(quantiles_df, "quantiles.csv", row.names = FALSE)
        
        saveRDS(sample_outliers, "sample_outliers_1_5.rds")
        saveRDS(outlier.list, "outlier_list.rds")
        
        if (!is.null(outlier.list\$up)) {
          writeLines(outlier.list\$up, "up_regulated_outliers.txt")
        }
        if (!is.null(outlier.list\$down)) {
          writeLines(outlier.list\$down, "down_regulated_outliers.txt")
        }
        
        # Optional Downstream Gene Set Enrichment Analysis using limma::mroast
        tryCatch({
          library(org.Hs.eg.db)
          library(limma)
          library(GO.db)
        
          go2eg <- as.list(org.Hs.egGO2EG)
        
          # Check if required annotation columns exist in fData
          if ("ID" %in% colnames(fData(eset)) && "Gene.ID" %in% colnames(fData(eset))) {
            
            # Up-regulated outliers analysis
            up.mtrx <- exprs(eset)[fData(eset)\$ID %in% outlier.list[["up"]], ]
            entrez.ids.up.mtrx <- fData(eset)\$Gene.ID[fData(eset)\$ID %in% rownames(up.mtrx)]
        
            gset.idx <- lapply(go2eg, function(x) {
              match(x, entrez.ids.up.mtrx)
            })
            gset.idx <- lapply(gset.idx, function(x) {
              x[!is.na(x)]
            })
            gset.ls <- unlist(lapply(gset.idx, length))
            gset.idx <- gset.idx[which(gset.ls > 10)]
        
            design <- model.matrix(~ g)
            up.mroast <- mroast(up.mtrx, index = gset.idx, design = design)
            write.csv(up.mroast, "up_regulated_mroast.csv", row.names = TRUE)
        
            go.terms <- rownames(up.mroast[1:min(10, nrow(up.mroast)), ])
            r2tab <- select(GO.db, keys = go.terms, columns = c("GOID", "TERM"), keytype = "GOID")
            write.csv(r2tab, "up_regulated_go_terms.csv", row.names = FALSE)
        
            # Down-regulated outliers analysis
            down_mtrx <- exprs(eset)[fData(eset)\$ID %in% outlier.list[["down"]], ]
            entrez_ids_down_mtrx <- fData(eset)\$Gene.ID[fData(eset)\$ID %in% rownames(down_mtrx)]
        
            gset_idx_down <- lapply(go2eg, function(x) {
              match(x, entrez_ids_down_mtrx)
            })
            gset_idx_down <- lapply(gset_idx_down, function(x) {
              x[!is.na(x)]
            })
            gset_ls_down <- unlist(lapply(gset_idx_down, length))
            gset_idx_down <- gset_idx_down[which(gset_ls_down > 10)]
        
            down_mroast <- mroast(down_mtrx, gset_idx_down, design)
            write.csv(down_mroast, "down_regulated_mroast.csv", row.names = TRUE)
        
            go_terms_down <- rownames(down_mroast[1:min(10, nrow(down_mroast)), ])
            dr2tab <- select(GO.db, keys = go_terms_down, columns = c("GOID", "TERM"), keytype = "GOID")
            write.csv(dr2tab, "down_regulated_go_terms.csv", row.names = FALSE)
          } else {
            message("Skipping mroast analysis: 'ID' or 'Gene.ID' columns missing from fData(eset).")
          }
        }, error = function(e) {
          warning("Downstream mroast analysis could not be completed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_OPPAR_CANCER_OUTLIER_PROFILE_ANALYSIS":',
        paste0('    oppar: ', as.character(packageVersion('oppar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cancer_outlier_profile_analysis.csv versions.yml
    """
}

workflow BIOC_OPPAR_CANCER_OUTLIER_PROFILE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eset ] ]

    main:
    BIOC_OPPAR_CANCER_OUTLIER_PROFILE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OPPAR_CANCER_OUTLIER_PROFILE_ANALYSIS.out.tables
    plots    = BIOC_OPPAR_CANCER_OUTLIER_PROFILE_ANALYSIS.out.plots
    objects  = BIOC_OPPAR_CANCER_OUTLIER_PROFILE_ANALYSIS.out.objects
    versions = BIOC_OPPAR_CANCER_OUTLIER_PROFILE_ANALYSIS.out.versions
}
