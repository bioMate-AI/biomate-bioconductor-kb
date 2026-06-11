#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ProteoMM — multi_dataset_proteomm_pipeline
// Perform peptide-level normalization, imputation, and differential expression analysis across multiple proteomics datasets.
// Input: dataset1_peptides.csv, dataset2_peptides.csv
// Container: quay.io/biocontainers/bioconductor-proteomm:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ProteoMM
// Visualizations: bar plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Log2 transform and replace zeros with NAs using make_intencities and convert_log2
//  * 2. [Core Analysis] Extract metadata using make_meta
//  * 3. [Core Analysis] Identify bias trends using eig_norm1
//  * 4. [Core Analysis] Perform EigenMS normalization using eig_norm2
//  * 5. [Core Analysis] Impute missing values using MBimpute
//  * 6. [Core Analysis] Subset common and unique proteins using subset_proteins
//  * 7. [Core Analysis] Perform combined model-based differential expression using prot_level_multi_part
//  * 8. [Core Analysis] Perform single-dataset differential expression for unique proteins using peptideLevel_DE
//  * 9. [Core Analysis] Identify presence/absence proteins using get_presAbs_prots
//  * 10. [Core Analysis] Perform combined presence/absence analysis using prot_level_multiMat_PresAbs
//  * 11. [Core Analysis] Perform single-dataset presence/absence analysis using peptideLevel_PresAbsDE

nextflow.enable.dsl = 2

process BIOC_PROTEOMM_MULTI_DATASET_PROTEOMM_PIPELINE {
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
    
    # Load required library
    library(ProteoMM)
    
    # Set seed for reproducibility
    set.seed(12131)
    
    # ----------------------------------------------------------------------
    # Stage 1: Read User Input Files
    # ----------------------------------------------------------------------
    # Read the declared user input files from the working directory
    hs_peptides <- read.csv("dataset1_peptides.csv", header = TRUE, stringsAsFactors = FALSE)
    mm_peptides <- read.csv("dataset2_peptides.csv", header = TRUE, stringsAsFactors = FALSE)
    
    # Define treatment groups (identical across both datasets)
    grps <- as.factor(c('CG', 'CG', 'CG', 'mCG', 'mCG', 'mCG'))
    
    # Set up PDF output for plots
    pdf("proteomm_pipeline_plots.pdf", width = 11, height = 8.5)
    
    # ----------------------------------------------------------------------
    # Stage 2: Dataset 1 (Human) Processing
    # ----------------------------------------------------------------------
    intsCols <- 8:13
    m_logInts <- make_intencities(hs_peptides, intsCols)
    m_logInts <- convert_log2(m_logInts)
    
    metaCols <- 1:7
    m_prot.info <- make_meta(hs_peptides, metaCols)
    
    # Plot missing values for Dataset 1
    tryCatch({
      barplot(colSums(is.na(m_logInts)), 
              main = "Numbers of missing values in Dataset 1 (group order)")
    }, error = function(e) {
      warning("Could not plot missing values for Dataset 1: ", e\$message)
    })
    
    # Identify bias trends and perform EigenMS normalization
    hs_m_ints_eig1 <- eig_norm1(m = m_logInts, treatment = grps, prot.info = m_prot.info)
    hs_m_ints_eig1\$h.c <- 2
    hs_m_ints_norm <- eig_norm2(rv = hs_m_ints_eig1)
    
    # ----------------------------------------------------------------------
    # Stage 3: Dataset 2 (Mouse) Processing
    # ----------------------------------------------------------------------
    intsCols <- 8:13
    m_logInts <- make_intencities(mm_peptides, intsCols)
    m_logInts <- convert_log2(m_logInts)
    
    metaCols <- 1:7
    m_prot.info <- make_meta(mm_peptides, metaCols)
    
    # Plot missing values for Dataset 2
    tryCatch({
      barplot(colSums(is.na(m_logInts)), 
              main = "Numbers of missing values in Dataset 2 (group order)")
    }, error = function(e) {
      warning("Could not plot missing values for Dataset 2: ", e\$message)
    })
    
    # Identify bias trends and perform EigenMS normalization
    mm_m_ints_eig1 <- eig_norm1(m = m_logInts, treatment = grps, prot.info = m_prot.info)
    mm_m_ints_eig1\$h.c <- 2
    mm_m_ints_norm <- eig_norm2(rv = mm_m_ints_eig1)
    
    # ----------------------------------------------------------------------
    # Stage 4: Model-Based Imputation
    # ----------------------------------------------------------------------
    # Impute Dataset 1 (Human)
    hs_prot.info <- hs_m_ints_norm\$normalized[, metaCols]
    hs_norm_m <- hs_m_ints_norm\$normalized[, intsCols]
    imp_hs <- MBimpute(hs_norm_m, grps, prot.info = hs_prot.info, pr_ppos = 3, my.pi = 0.05, compute_pi = FALSE)
    
    # Impute Dataset 2 (Mouse)
    mm_prot.info <- mm_m_ints_norm\$normalized[, 1:7]
    mm_norm_m <- mm_m_ints_norm\$normalized[, 8:13]
    set.seed(12131)
    imp_mm <- MBimpute(mm_norm_m, grps, prot.info = mm_prot.info, pr_ppos = 3, my.pi = 0.05, compute_pi = FALSE)
    
    # Plot peptide trends for a dynamically selected protein
    tryCatch({
      prot_to_plot <- hs_prot.info\$ProtID[1]
      gene_to_plot <- hs_prot.info\$GeneID[1]
      mylabs <- c('CG', 'CG', 'CG', 'mCG', 'mCG', 'mCG')
      plot_3_pep_trends_NOfile(
        as.matrix(hs_m_ints_eig1\$m), 
        hs_m_ints_eig1\$prot.info, 
        as.matrix(hs_norm_m), 
        hs_prot.info, 
        imp_hs\$y_imputed, 
        imp_hs\$imp_prot.info, 
        prot_to_plot, 
        3, 
        gene_to_plot, 
        4, 
        mylabs
      )
    }, error = function(e) {
      warning("Could not plot peptide trends: ", e\$message)
    })
    
    # ----------------------------------------------------------------------
    # Stage 5: Subset Common and Unique Proteins
    # ----------------------------------------------------------------------
    mms <- list()
    treats <- list()
    protinfos <- list()
    mms[[1]] <- imp_mm\$y_imputed
    mms[[2]] <- imp_hs\$y_imputed 
    treats[[1]] <- grps
    treats[[2]] <- grps
    protinfos[[1]] <- imp_mm\$imp_prot.info 
    protinfos[[2]] <- imp_hs\$imp_prot.info
    
    subset_data <- subset_proteins(mm_list = mms, prot.info = protinfos, 'MatchedID')
    
    # ----------------------------------------------------------------------
    # Stage 6: Combined Model-Based Differential Expression (MBDE)
    # ----------------------------------------------------------------------
    nperm <- 50
    comb_MBDE <- prot_level_multi_part(
      mm_list = mms, 
      treat = treats, 
      prot.info = protinfos, 
      prot_col_name = 'ProtID', 
      nperm = nperm, 
      dataset_suffix = c('MM', 'HS')
    )
    
    # Plot combined MBDE volcano
    tryCatch({
      plot_volcano_wLab(comb_MBDE\$FC, comb_MBDE\$BH_P_val, comb_MBDE\$GeneID, FC_cutoff = 1.2, PV_cutoff = .05, 'CG vs mCG')
    }, error = function(e) {
      warning("Could not plot combined MBDE volcano: ", e\$message)
    })
    
    # ----------------------------------------------------------------------
    # Stage 7: Single-Dataset DE for Unique Proteins
    # ----------------------------------------------------------------------
    mms_mm_dd <- subset_data\$sub_unique_mm_list[[1]]
    protinfos_mm_dd <- subset_data\$sub_unique_prot.info[[1]] 
    DE_mCG_CG_mm_dd <- peptideLevel_DE(mms_mm_dd, grps, prot.info = protinfos_mm_dd, pr_ppos = 2)
    
    # Plot single-dataset DE volcano
    tryCatch({
      plot_volcano_wLab(DE_mCG_CG_mm_dd\$FC, DE_mCG_CG_mm_dd\$BH_P_val, DE_mCG_CG_mm_dd\$GeneID, FC_cutoff = 1.2, PV_cutoff = .05, 'Mouse specific - CG vs mCG')
    }, error = function(e) {
      warning("Could not plot mouse specific volcano: ", e\$message)
    })
    
    # ----------------------------------------------------------------------
    # Stage 8: Presence/Absence Analysis
    # ----------------------------------------------------------------------
    raw_list <- list()
    norm_imp_prot.info_list <- list()
    raw_list[[1]] <- mm_m_ints_eig1\$m
    raw_list[[2]] <- hs_m_ints_eig1\$m
    norm_imp_prot.info_list[[1]] <- mm_m_ints_eig1\$prot.info
    norm_imp_prot.info_list[[2]] <- hs_m_ints_eig1\$prot.info
    
    protnames_norm_list <- list()
    protnames_norm_list[[1]] <- unique(mm_m_ints_norm\$normalized\$MatchedID)
    protnames_norm_list[[2]] <- unique(hs_m_ints_norm\$normalized\$MatchedID) 
    
    presAbs_dd <- get_presAbs_prots(
      mm_list = raw_list, 
      prot.info = norm_imp_prot.info_list, 
      protnames_norm = protnames_norm_list, 
      prot_col_name = 2
    )
    
    ints_presAbs <- list()
    protmeta_presAbs <- list()
    ints_presAbs[[1]] <- presAbs_dd[[1]][[1]]
    ints_presAbs[[2]] <- presAbs_dd[[1]][[2]]
    protmeta_presAbs[[1]] <- presAbs_dd[[2]][[1]] 
    protmeta_presAbs[[2]] <- presAbs_dd[[2]][[2]]
    
    subset_presAbs <- subset_proteins(mm_list = ints_presAbs, prot.info = protmeta_presAbs, 'MatchedID') 
    
    # Combined Presence/Absence Analysis
    presAbs_comb <- prot_level_multiMat_PresAbs(
      mm_list = subset_presAbs\$sub_mm_list, 
      treat = treats, 
      prot.info = subset_presAbs\$sub_prot.info, 
      prot_col_name = 'MatchedID', 
      nperm = nperm, 
      dataset_suffix = c('MM', 'HS')
    )
    
    tryCatch({
      plot_volcano_wLab(presAbs_comb\$FC, presAbs_comb\$BH_P_val, presAbs_comb\$GeneID, FC_cutoff = .5, PV_cutoff = .05, 'Combined Pres/Abs CG vs mCG')
    }, error = function(e) {
      warning("Could not plot combined Pres/Abs volcano: ", e\$message)
    })
    
    # Single-Dataset Presence/Absence Analysis
    mm_presAbs <- peptideLevel_PresAbsDE(subset_presAbs\$sub_unique_mm_list[[1]], treats[[1]], subset_presAbs\$sub_unique_prot.info[[1]], pr_ppos = 3)
    hs_presAbs <- peptideLevel_PresAbsDE(subset_presAbs\$sub_unique_mm_list[[2]], treats[[2]], subset_presAbs\$sub_unique_prot.info[[2]], pr_ppos = 3)
    
    tryCatch({
      plot_volcano_wLab(mm_presAbs\$FC, mm_presAbs\$BH_P_val, mm_presAbs\$GeneID, FC_cutoff = .5, PV_cutoff = .05, 'MM Pres/Abs CG vs mCG')
    }, error = function(e) {
      warning("Could not plot MM Pres/Abs volcano: ", e\$message)
    })
    
    tryCatch({
      plot_volcano_wLab(hs_presAbs\$FC, hs_presAbs\$BH_P_val, hs_presAbs\$GeneID, FC_cutoff = .5, PV_cutoff = .05, 'HS Pres/Abs CG vs mCG')
    }, error = function(e) {
      warning("Could not plot HS Pres/Abs volcano: ", e\$message)
    })
    
    # Close PDF device
    dev.off()
    
    # ----------------------------------------------------------------------
    # Stage 9: Write Output Files
    # ----------------------------------------------------------------------
    # Save tabular results
    write.csv(comb_MBDE, "comb_MBDE_results.csv", row.names = FALSE)
    write.csv(DE_mCG_CG_mm_dd, "DE_mouse_specific_results.csv", row.names = FALSE)
    write.csv(presAbs_comb, "presAbs_comb_results.csv", row.names = FALSE)
    write.csv(mm_presAbs, "mm_presAbs_results.csv", row.names = FALSE)
    write.csv(hs_presAbs, "hs_presAbs_results.csv", row.names = FALSE)
    
    # Save RDS objects of imputed datasets
    saveRDS(imp_hs, "imputed_human.rds")
    saveRDS(imp_mm, "imputed_mouse.rds")
    
    # Print completion message
    cat("Pipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_PROTEOMM_MULTI_DATASET_PROTEOMM_PIPELINE":',
        paste0('    ProteoMM: ', as.character(packageVersion('ProteoMM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_dataset_proteomm_pipeline.csv versions.yml
    """
}

workflow BIOC_PROTEOMM_MULTI_DATASET_PROTEOMM_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset1_peptides.csv, dataset2_peptides.csv ] ]

    main:
    BIOC_PROTEOMM_MULTI_DATASET_PROTEOMM_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PROTEOMM_MULTI_DATASET_PROTEOMM_PIPELINE.out.tables
    plots    = BIOC_PROTEOMM_MULTI_DATASET_PROTEOMM_PIPELINE.out.plots
    objects  = BIOC_PROTEOMM_MULTI_DATASET_PROTEOMM_PIPELINE.out.objects
    versions = BIOC_PROTEOMM_MULTI_DATASET_PROTEOMM_PIPELINE.out.versions
}
