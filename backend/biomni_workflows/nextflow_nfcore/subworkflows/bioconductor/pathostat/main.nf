#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PathoStat — pathostat_metagenomics_pipeline
// Perform comprehensive statistical microbiome analysis including normalization, taxonomy resolution, differential abundance testing, presence-absence analysis, a
// Input: abundance.csv, coldata.csv
// Container: 1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PathoStat
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHOSTAT_PATHOSTAT_METAGENOMICS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("PathoStat")
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
    
    # Load required libraries
    library(PathoStat)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Loading input data...")
    abundance_df <- read.csv("abundance.csv", row.names = 1, check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between abundance matrix and coldata
    common_samples <- intersect(colnames(abundance_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("No common samples found between abundance.csv and coldata.csv")
    }
    abundance_df <- abundance_df[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    group <- coldata_df\$group
    
    # ==========================================
    # --- Data Transformation & Normalization ---
    # ==========================================
    message("Performing data transformations...")
    count_matrix <- as.matrix(abundance_df)
    
    # 1. Relative Abundance
    ra_matrix <- PathoStat::findRAfromCount(count_matrix)
    write.csv(ra_matrix, "relative_abundance.csv", row.names = TRUE)
    
    # 2. Log2 CPM (Counts Per Million)
    log2cpm_matrix <- PathoStat::log2CPM(count_matrix)
    write.csv(log2cpm_matrix, "log2_cpm.csv", row.names = TRUE)
    
    # 3. Presence-Absence Matrix (PAM)
    pam_matrix <- PathoStat::GET_PAM(count_matrix)
    write.csv(pam_matrix, "presence_absence_matrix.csv", row.names = TRUE)
    
    # ==========================================
    # --- Taxonomy Resolution ---
    # ==========================================
    message("Resolving taxonomy...")
    taxon_ids <- rownames(abundance_df)
    taxonomy_df <- tryCatch({
        # Try to find taxonomy using PathoStat's findTaxonMat
        PathoStat::findTaxonMat(taxon_ids)
    }, error = function(e) {
        message("Taxonomy resolution failed or not applicable. Creating dummy taxonomy.")
        data.frame(
            taxon_id = taxon_ids,
            Kingdom = "Unknown",
            Phylum = "Unknown",
            Class = "Unknown",
            Order = "Unknown",
            Family = "Unknown",
            Genus = "Unknown",
            Species = "Unknown",
            row.names = taxon_ids
        )
    })
    write.csv(taxonomy_df, "taxonomy_matrix.csv", row.names = TRUE)
    
    # ==========================================
    # --- Statistical Association Testing ---
    # ==========================================
    message("Running statistical tests...")
    # Transpose matrices for sample-wise analysis (samples as rows, taxa as columns)
    df_taxa_log2cpm <- as.data.frame(t(log2cpm_matrix))
    df_pam <- as.data.frame(t(pam_matrix))
    
    # 1. Wilcoxon Rank-Sum Test for Differential Abundance
    wilcox_res <- tryCatch({
        PathoStat::Wilcox_Test_df(df_taxa_log2cpm, group)
    }, error = function(e) {
        message("Wilcoxon test failed: ", e\$message)
        data.frame(Taxon = colnames(df_taxa_log2cpm), Error = e\$message)
    })
    write.csv(wilcox_res, "wilcoxon_test_results.csv", row.names = TRUE)
    
    # 2. Chi-Square and Fisher's Exact Tests on Presence-Absence Matrix (PAM)
    pam_test_results <- tryCatch({
        chisq_p <- PathoStat::Chisq_Test_Pam(df_pam, group)
        fisher_p <- PathoStat::Fisher_Test_Pam(df_pam, group)
        data.frame(
            Taxon = colnames(df_pam),
            Chisq_p_value = chisq_p,
            Fisher_p_value = fisher_p
        )
    }, error = function(e) {
        message("PAM statistical tests failed: ", e\$message)
        data.frame(Taxon = colnames(df_pam), Error = e\$message)
    })
    write.csv(pam_test_results, "pam_test_results.csv", row.names = FALSE)
    
    # ==========================================
    # --- Biomarker Identification & Classification ---
    # ==========================================
    message("Running biomarker classification...")
    auc_results <- tryCatch({
        # Ensure group is a factor with exactly 2 levels for binary classification
        group_factor <- as.factor(group)
        if (length(levels(group_factor)) == 2) {
            # Run Leave-One-Out Cross-Validation (LOOCV) AUC
            auc_df <- PathoStat::LOOAUC_simple_multiple_noplot_one_df(df_taxa_log2cpm, group_factor)
            auc_df
        } else {
            data.frame(Status = "Skipped: Group factor does not have exactly 2 levels.")
        }
    }, error = function(e) {
        message("LOOCV AUC classification failed: ", e\$message)
        data.frame(Status = "Failed", Error = e\$message)
    })
    write.csv(auc_results, "classification_auc.csv", row.names = TRUE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_PATHOSTAT_PATHOSTAT_METAGENOMICS_PIPELINE":',
        paste0('    PathoStat: ', as.character(packageVersion('PathoStat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathostat_metagenomics_pipeline.csv versions.yml
    """
}

workflow BIOC_PATHOSTAT_PATHOSTAT_METAGENOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PATHOSTAT_PATHOSTAT_METAGENOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PATHOSTAT_PATHOSTAT_METAGENOMICS_PIPELINE.out.tables
    plots    = BIOC_PATHOSTAT_PATHOSTAT_METAGENOMICS_PIPELINE.out.plots
    objects  = BIOC_PATHOSTAT_PATHOSTAT_METAGENOMICS_PIPELINE.out.objects
    versions = BIOC_PATHOSTAT_PATHOSTAT_METAGENOMICS_PIPELINE.out.versions
}
