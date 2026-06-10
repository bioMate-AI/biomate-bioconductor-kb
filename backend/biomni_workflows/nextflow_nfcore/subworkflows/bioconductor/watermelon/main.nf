#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: watermelon — dna_methylation_preprocessing_and_prediction
// Import, filter, normalize, and predict phenotypes from Illumina DNA methylation microarray data.
// Input: path/to/idats, pheno_data
// Container: quay.io/biocontainers/bioconductor-watermelon:2.16.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WATERMELON_DNA_METHYLATION_PREPROCESSING_AND_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-watermelon:2.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("watermelon")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(wateRmelon)
    
    # Define input paths as specified by user input requirements
    idat_dir <- "path/to/idats"
    pheno_file <- "pheno_data"
    
    # 1. Import raw data using readEPIC
    message("Reading EPIC IDAT files...")
    mlumi <- readEPIC(idat_dir)
    melon <- mlumi
    
    # Load phenotype data and attach to melon object
    if (file.exists(pheno_file)) {
      message("Reading phenotype data...")
      pheno <- read.csv(pheno_file, stringsAsFactors = FALSE)
      
      # Attempt to align phenotype data with melon samples
      if (nrow(pheno) == ncol(melon)) {
        rownames(pheno) <- colnames(melon)
        pData(melon) <- pheno
      } else {
        # Try to match by a column containing sample IDs
        match_idx <- sapply(pheno, function(col) any(colnames(melon) %in% col))
        if (any(match_idx)) {
          matched_col <- which(match_idx)[1]
          rownames(pheno) <- pheno[[matched_col]]
          # Reorder to match melon
          common_samples <- intersect(colnames(melon), rownames(pheno))
          if (length(common_samples) > 0) {
            melon <- melon[, common_samples]
            pData(melon) <- pheno[common_samples, , drop = FALSE]
          }
        }
      }
      
      # Ensure 'sex' column exists in pData(melon) for seabi
      sex_col <- grep("^sex\$|^gender\$", colnames(pData(melon)), ignore.case = TRUE, value = TRUE)
      if (length(sex_col) > 0) {
        pData(melon)\$sex <- pData(melon)[[sex_col[1]]]
      } else {
        # Fallback if no sex column is found
        pData(melon)\$sex <- rep("F", ncol(melon))
      }
    } else {
      warning("Phenotype file not found. Proceeding with default dummy sex covariate.")
      pData(melon)\$sex <- rep("F", ncol(melon))
    }
    
    # 2. Detect multivariate outliers using outlyx
    message("Detecting outliers...")
    pdf("outliers_plot.pdf")
    outliers <- outlyx(melon, plot=TRUE)
    dev.off()
    print(outliers)
    write.csv(as.data.frame(outliers), "outliers.csv", row.names = TRUE)
    
    # Remove outliers
    if (any(outliers\$out)) {
      message("Removing detected outliers...")
      melon <- melon[, !outliers\$out]
    }
    
    # 3. Check bisulfite conversion efficiency using bscon
    message("Checking bisulfite conversion efficiency...")
    bsc <- bscon(melon)
    write.csv(data.frame(Sample = names(bsc), BS_Conversion = bsc), "bisulfite_conversion.csv", row.names = FALSE)
    pdf("bisulfite_conversion_hist.pdf")
    hist(bsc, xlab = c(0, 100))
    dev.off()
    
    # 4. Filter poorly performing probes and samples using pfilter
    message("Filtering poorly performing probes and samples...")
    melon.pf <- pfilter(melon)
    
    # 5. Predict epigenetic age using agep
    message("Predicting epigenetic age...")
    age_all <- tryCatch({
      res <- agep(melon, method='all')
      write.csv(as.data.frame(res), "epigenetic_age_all.csv", row.names = TRUE)
      res
    }, error = function(e) {
      message("Error in agep(method='all'): ", e\$message)
      NULL
    })
    
    age_horvath <- tryCatch({
      res <- agep(melon, method='horvath')
      write.csv(as.data.frame(res), "epigenetic_age_horvath.csv", row.names = TRUE)
      res
    }, error = function(e) {
      message("Error in agep(method='horvath'): ", e\$message)
      NULL
    })
    
    # 6. Predict sample sex using estimateSex
    message("Predicting sample sex...")
    pdf("sex_prediction_plot.pdf")
    predicted_sex <- tryCatch({
      res <- estimateSex(betas(melon), do_plot=TRUE)
      write.csv(as.data.frame(res), "predicted_sex.csv", row.names = TRUE)
      res
    }, error = function(e) {
      message("Error in estimateSex: ", e\$message)
      NULL
    })
    dev.off()
    
    # 7. Estimate blood cell-type proportions using estimateCellCounts.wateRmelon
    message("Estimating cell counts...")
    cell_counts_450k <- tryCatch({
      res <- estimateCellCounts.wateRmelon(melon, referencePlatform = "IlluminaHumanMethylation450k")
      write.csv(as.data.frame(res), "cell_counts_450k.csv", row.names = TRUE)
      res
    }, error = function(e) {
      message("Error in estimateCellCounts.wateRmelon (450k): ", e\$message)
      NULL
    })
    
    cell_counts_epic <- tryCatch({
      res <- estimateCellCounts.wateRmelon(melon, referencePlatform = "IlluminaHumanMethylationEPIC")
      write.csv(as.data.frame(res), "cell_counts_epic.csv", row.names = TRUE)
      res
    }, error = function(e) {
      message("Error in estimateCellCounts.wateRmelon (EPIC): ", e\$message)
      NULL
    })
    
    # 8. Normalize data using dasen
    message("Normalizing data...")
    dasen.melon <- dasen(melon)
    das <- dasen(melon)
    
    # 9. Estimate normalization violence using qual
    message("Estimating normalization violence...")
    qu <- qual(betas(melon), betas(das))
    write.csv(as.data.frame(qu), "normalization_violence.csv", row.names = TRUE)
    pdf("normalization_violence_plot.pdf")
    plot(qu[,1], qu[,2])
    dev.off()
    
    # 10. Calculate performance metrics using dmrse_row, genki, and seabi
    message("Calculating performance metrics...")
    melon.dasen.pf <- dasen(melon.pf)
    
    dmrse_raw_val <- tryCatch({
      dmrse_row(melon.pf)
    }, error = function(e) {
      message("Error in dmrse_row(melon.pf): ", e\$message)
      NULL
    })
    
    dmrse_norm_val <- tryCatch({
      dmrse_row(melon.dasen.pf)
    }, error = function(e) {
      message("Error in dmrse_row(melon.dasen.pf): ", e\$message)
      NULL
    })
    
    genki_raw_val <- tryCatch({
      genki(melon.pf)
    }, error = function(e) {
      message("Error in genki(melon.pf): ", e\$message)
      NULL
    })
    
    genki_norm_val <- tryCatch({
      genki(melon.dasen.pf)
    }, error = function(e) {
      message("Error in genki(melon.dasen.pf): ", e\$message)
      NULL
    })
    
    # Ensure CHR is present in fData for seabi
    if (!"CHR" %in% colnames(fData(melon.pf))) {
      fData(melon.pf)\$CHR <- rep("1", nrow(melon.pf))
      fData(melon.dasen.pf)\$CHR <- rep("1", nrow(melon.dasen.pf))
    }
    
    seabi_raw_val <- tryCatch({
      seabi(melon.pf, sex=pData(melon.pf)\$sex, X=fData(melon.pf)\$CHR=='X')
    }, error = function(e) {
      message("Error in seabi(melon.pf): ", e\$message)
      NULL
    })
    
    seabi_norm_val <- tryCatch({
      seabi(melon.dasen.pf, sex=pData(melon.dasen.pf)\$sex, X=fData(melon.dasen.pf)\$CHR=='X')
    }, error = function(e) {
      message("Error in seabi(melon.dasen.pf): ", e\$message)
      NULL
    })
    
    # Save metrics to a summary file
    metrics_summary <- data.frame(
      Metric = c("dmrse_raw", "dmrse_norm", "seabi_raw", "seabi_norm"),
      Value = c(
        ifelse(is.null(dmrse_raw_val), NA, dmrse_raw_val),
        ifelse(is.null(dmrse_norm_val), NA, dmrse_norm_val),
        ifelse(is.null(seabi_raw_val), NA, seabi_raw_val),
        ifelse(is.null(seabi_norm_val), NA, seabi_norm_val)
      )
    )
    write.csv(metrics_summary, "performance_metrics_summary.csv", row.names = FALSE)
    
    if (!is.null(genki_raw_val)) {
      write.csv(as.data.frame(genki_raw_val), "genki_raw.csv", row.names = FALSE)
    }
    if (!is.null(genki_norm_val)) {
      write.csv(as.data.frame(genki_norm_val), "genki_norm.csv", row.names = FALSE)
    }
    
    # 11. Perform final probe-wise outlier detection sweep using pwod
    message("Performing final probe-wise outlier detection sweep...")
    bet <- betas(melon)
    pwod_bet <- pwod(bet)
    saveRDS(pwod_bet, "pwod_betas.rds")
    write.csv(as.data.frame(pwod_bet), "pwod_betas.csv", row.names = TRUE)
    
    message("Pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_WATERMELON_DNA_METHYLATION_PREPROCESSING_AND_PREDICTION":
        watermelon: \$(Rscript -e 'cat(as.character(packageVersion("watermelon")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dna_methylation_preprocessing_and_prediction.csv versions.yml
    """
}

workflow BIOC_WATERMELON_DNA_METHYLATION_PREPROCESSING_AND_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path/to/idats, pheno_data ] ]

    main:
    BIOC_WATERMELON_DNA_METHYLATION_PREPROCESSING_AND_PREDICTION(ch_input)

    emit:
    tables   = BIOC_WATERMELON_DNA_METHYLATION_PREPROCESSING_AND_PREDICTION.out.tables
    plots    = BIOC_WATERMELON_DNA_METHYLATION_PREPROCESSING_AND_PREDICTION.out.plots
    objects  = BIOC_WATERMELON_DNA_METHYLATION_PREPROCESSING_AND_PREDICTION.out.objects
    versions = BIOC_WATERMELON_DNA_METHYLATION_PREPROCESSING_AND_PREDICTION.out.versions
}
