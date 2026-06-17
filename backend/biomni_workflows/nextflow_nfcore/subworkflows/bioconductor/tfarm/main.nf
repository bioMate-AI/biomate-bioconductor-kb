#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TFARM — tf_association_rule_mining
// Extract association rules for a target transcription factor, compute the Importance Index for candidate co-regulators (individually and in pairs), and visualize
// Input: matrix_of_presences.RData
// Container: quay.io/biocontainers/bioconductor-tfarm:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, TFARM, plyr
// Visualizations: PCA plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the genomic regions dataset (GRanges object)
//  * 2. [Core Analysis] Generate association rules for a target transcription factor using rulesGen
//  * 3. [Core Analysis] Identify candidate co-regulators (present/absent TFs in rules) using presAbs
//  * 4. [Core Analysis] Extract rules containing a specific TF using rulesTF
//  * 5. [Core Analysis] Generate corresponding rules without the specific TF using rulesTF0
//  * 6. [Core Analysis] Compute the Importance Index distribution for the TF using IComp
//  * 7. [Core Analysis] Perform Principal Component Analysis (PCA) on the variations of support and confidence using IPCA
//  * 8. [Visualization & Output] Visualize the Importance Index distributions using distribViz
//  * 9. [Core Analysis] Compute pair-wise Importance Indices for combinations of TFs
//  * 10. [Visualization & Output] Visualize pair-wise importances using a heatmap with heatI

nextflow.enable.dsl = 2

process BIOC_TFARM_TF_ASSOCIATION_RULE_MINING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "TFARM", "plyr")
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
    library(GenomicRanges)
    library(TFARM)
    library(plyr)
    
    # ==========================================
    # 1. Load the genomic regions dataset
    # ==========================================
    # Read the user input file from the working directory
    env <- new.env()
    load("matrix_of_presences.RData", envir = env)
    # Retrieve the GRanges object dynamically
    MCF7_chr1 <- env[[ls(env)[1]]]
    
    # Print basic info
    length(MCF7_chr1)
    print(MCF7_chr1)
    
    # ==========================================
    # 2. Generate association rules for a target TF
    # ==========================================
    c_names <- names(mcols(MCF7_chr1))
    target_TF <- paste0(c_names[length(c_names)], "=1")
    
    r_target <- rulesGen(MCF7_chr1, target_TF, 0.005, 0.62, TRUE)
    dim(r_target)
    head(r_target)
    write.csv(r_target, "r_target.csv", row.names = FALSE)
    
    # ==========================================
    # 3. Identify candidate co-regulators
    # ==========================================
    c <- names(mcols(MCF7_chr1))
    lc <- length(c)
    
    names(presAbs(c, r_target, TRUE))
    
    p_TFs <- presAbs(c, r_target, TRUE)\$pres
    print(p_TFs)
    
    a <- presAbs(c[1:lc], r_target, TRUE)\$abs
    print(a)
    
    # Dynamically select TFs for downstream analysis to avoid hardcoding
    spec_TF1 <- if (length(p_TFs) >= 1) p_TFs[1] else paste0(c[1], "=1")
    spec_TF2 <- if (length(p_TFs) >= 2) p_TFs[2] else paste0(c[2], "=1")
    spec_TF3 <- if (length(p_TFs) >= 3) p_TFs[3] else paste0(c[3], "=1")
    
    # ==========================================
    # 4. Extract rules containing a specific TF
    # ==========================================
    r_spec1 <- rulesTF(TFi  = spec_TF1, rules =  r_target, verbose = TRUE)
    head(r_spec1)
    dim(r_spec1)[1]
    write.csv(r_spec1, "r_spec1.csv", row.names = FALSE)
    
    r_spec2 <- rulesTF(TFi = spec_TF2, rules = r_target, verbose = TRUE)
    
    # ==========================================
    # 5. Generate corresponding rules without the specific TF
    # ==========================================
    r_nospec1 <- rulesTF0(spec_TF1, r_spec1, r_target, MCF7_chr1, target_TF)
    
    row.names(r_spec1) <- match(r_spec1\$lhs, r_target\$lhs)
    row.names(r_nospec1) <- match(r_spec1\$lhs, r_target\$lhs)
    head(r_nospec1)
    write.csv(r_nospec1, "r_nospec1.csv", row.names = FALSE)
    
    # ==========================================
    # 6. Compute the Importance Index distribution
    # ==========================================
    pdf("spec1_importance_plots.pdf", width = 12, height = 5)
    imp_spec1 <- IComp(spec_TF1, r_spec1, r_nospec1, figures=TRUE)
    dev.off()
    
    names(imp_spec1)
    print(imp_spec1\$imp)
    head(imp_spec1\$delta)
    head(imp_spec1\$rwi)
    head(imp_spec1\$rwo)
    saveRDS(imp_spec1, "imp_spec1.rds")
    
    # Initialize lists for the loop
    DELTA_mean_supp <- vector("list", length(p_TFs))
    DELTA_mean_conf <- vector("list", length(p_TFs))
    IMP_Z <- vector("list", length(p_TFs))
    
    all <- lapply(p_TFs, function(pi) {
        A <- rulesTF(pi, r_target, FALSE)
        B <- rulesTF0(pi, A, r_target, MCF7_chr1, target_TF)
        IComp(pi, A, B, figures=FALSE)
    })
    
    for (i in 1:length(p_TFs)) {
        IMP_Z[[i]] <- all[[i]]\$imp
        DELTA_mean_supp[[i]] <- apply(all[[i]]\$delta[1], 2, mean)
        DELTA_mean_conf[[i]] <- apply(all[[i]]\$delta[2], 2, mean)
    }
    
    IMP <- data.frame(
        TF = p_TFs,
        imp = sapply(IMP_Z, mean),
        sd = sapply(IMP_Z, sd),
        delta_support = as.numeric(DELTA_mean_supp),
        delta_confidence = as.numeric(DELTA_mean_conf),
        nrules = sapply(IMP_Z, length),
        stringsAsFactors=FALSE
    )
    
    IMP.ord <- arrange(IMP, desc(imp))
    print(IMP.ord)
    write.csv(IMP.ord, "IMP_ordered.csv", row.names = FALSE)
    
    # ==========================================
    # 7. Perform Principal Component Analysis (PCA)
    # ==========================================
    colnames(IMP)
    TF_Imp <- data.frame(IMP\$TF, IMP\$imp, IMP\$nrules)
    
    # Construct DELTA matrix from the delta outputs of all TFs
    DELTA <- do.call(rbind, lapply(all, function(x) x\$delta))
    
    pdf("pca_plots.pdf", width = 9, height = 7.5)
    i.pc <- IPCA(DELTA, TF_Imp)
    dev.off()
    
    names(i.pc)
    print(i.pc\$summary)
    head(i.pc\$loadings)
    head(i.pc\$scores)
    
    saveRDS(i.pc, "pca_results.rds")
    sink("pca_summary.txt")
    print(i.pc\$summary)
    cat("\nLoadings:\n")
    print(i.pc\$loadings)
    sink()
    
    # ==========================================
    # 8. Visualize the Importance Index distributions
    # ==========================================
    pdf("distribViz_plot.pdf", width = 10, height = 6)
    distribViz(IMP_Z, p_TFs)
    dev.off()
    
    # Robust extraction of spec_TF3 outlier rules
    tryCatch({
        spec3_index <- which(p_TFs == spec_TF3)
        if (length(spec3_index) > 0) {
            o <- IMP_Z[[spec3_index]] > 0
            if (any(o)) {
                rule_o <- all[[spec3_index]]\$rwi[o,]
                if (nrow(rule_o) >= 6) {
                    print(rule_o[6,])
                } else {
                    print(head(rule_o))
                }
                
                all_outliers <- all[[spec3_index]]\$rwo[o,]
                if (nrow(all_outliers) >= 6) {
                    print(all_outliers[6,])
                } else {
                    print(head(all_outliers))
                }
            }
        }
    }, error = function(e) {
        message("Outlier analysis skipped: ", e\$message)
    })
    
    # ==========================================
    # 9. Compute pair-wise Importance Indices
    # ==========================================
    couples_0 <- combn(p_TFs, 2)
    couples <- paste(couples_0[1,], couples_0[2,], sep=',')
    head(couples)
    
    IMP_c <- lapply(couples, function(ci) {
        A_c <- rulesTF(ci, r_target, FALSE)
        if (all(!is.na(A_c[[1]][1]))){
            B_c <- rulesTF0(ci, A_c, r_target, MCF7_chr1, target_TF)
            IComp(ci, A_c, B_c, figures=FALSE)\$imp
        }
    })
    
    I_c <- matrix(0, length(couples), 2)
    I_c <- data.frame(I_c)
    I_c[,1] <- paste(couples)
    
    null.indexes <- vapply(IMP_c, is.null, logical(1))
    IMP_c <- IMP_c[!null.indexes]
    I_c <- I_c[!null.indexes,]
    
    if (nrow(I_c) > 0) {
        I_c[,2] <- vapply(IMP_c, mean, numeric(1))
        colnames(I_c) <- colnames(IMP[,1:2])
        I_c <- I_c[!is.na(I_c[,2]),]
        I_c_ord <- arrange(I_c, desc(imp))
    } else {
        I_c_ord <- data.frame(TF = character(), imp = numeric())
    }
    
    head(I_c_ord)
    write.csv(I_c_ord, "I_c_ordered.csv", row.names = FALSE)
    
    # ==========================================
    # 10. Visualize pair-wise importances (Heatmap)
    # ==========================================
    I_c_2 <- arrange(rbind(IMP[,1:2], I_c_ord), desc(imp))
    p_TFs <- sub("=1", "", p_TFs)
    I_c_2\$TF <- sub("=1", "", I_c_2\$TF)
    
    pdf("heatmap_plot.pdf", width = 15, height = 15)
    i.heat <- heatI(p_TFs, I_c_2)
    dev.off()

    writeLines(c(
        '"BIOC_TFARM_TF_ASSOCIATION_RULE_MINING":',
        paste0('    TFARM: ', as.character(packageVersion('TFARM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tf_association_rule_mining.csv versions.yml
    """
}

workflow BIOC_TFARM_TF_ASSOCIATION_RULE_MINING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matrix_of_presences.RData ] ]

    main:
    BIOC_TFARM_TF_ASSOCIATION_RULE_MINING(ch_input)

    emit:
    tables   = BIOC_TFARM_TF_ASSOCIATION_RULE_MINING.out.tables
    plots    = BIOC_TFARM_TF_ASSOCIATION_RULE_MINING.out.plots
    objects  = BIOC_TFARM_TF_ASSOCIATION_RULE_MINING.out.objects
    versions = BIOC_TFARM_TF_ASSOCIATION_RULE_MINING.out.versions
}
