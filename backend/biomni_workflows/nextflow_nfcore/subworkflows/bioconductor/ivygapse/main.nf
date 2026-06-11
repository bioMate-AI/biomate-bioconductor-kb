#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ivygapSE — ivygap_glioblastoma_analysis
// Perform a comprehensive glioblastoma transcriptomic analysis using ivygapSE metadata structures, limma differential expression, and random forest classification
// Input: counts.csv, coldata.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ivygapSE, limma, randomForest
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IVYGAPSE_IVYGAP_GLIOBLASTOMA_ANALYSIS {
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
    library(ivygapSE)
    library(limma)
    library(randomForest)
    
    # ==========================================
    # --- Read and Align User Input Files ---
    # ==========================================
    
    # Read the gene-by-sample expression matrix (counts or normalized values)
    counts <- read.csv("counts.csv", row.names=1, check.names=FALSE)
    
    # Read the sample metadata
    coldata <- read.csv("coldata.csv", check.names=FALSE)
    
    # Align counts and coldata based on sample identifiers
    if ("sample" %in% colnames(coldata)) {
      common_samples <- intersect(colnames(counts), coldata\$sample)
      counts <- counts[, common_samples, drop=FALSE]
      coldata <- coldata[match(common_samples, coldata\$sample), , drop=FALSE]
      rownames(coldata) <- coldata\$sample
    } else {
      common_samples <- intersect(colnames(counts), rownames(coldata))
      counts <- counts[, common_samples, drop=FALSE]
      coldata <- coldata[common_samples, , drop=FALSE]
      coldata\$sample <- rownames(coldata)
    }
    
    # ==========================================
    # --- Construct Compatible SummarizedExperiment ---
    # ==========================================
    
    # To leverage ivygapSE's metadata extraction and modeling workflows,
    # we map the user's 'condition' to structural and molecular subtype variables.
    coldata\$structure_acronym <- paste0(coldata\$condition, "-reference-histology")
    
    # Create mock tumor IDs to allow duplicate correlation grouping (e.g., 2 samples per tumor)
    n_samples <- nrow(coldata)
    coldata\$tumor_id <- paste0("Tumor_", rep(1:ceiling(n_samples/2), each=2)[1:n_samples])
    coldata\$tumor_name <- coldata\$tumor_id
    
    # Build the SummarizedExperiment object (using 'fpkm' as the assay name to match ivySE)
    se <- SummarizedExperiment(
      assays = list(fpkm = as.matrix(counts)),
      colData = as(coldata, "DataFrame")
    )
    
    # Populate metadata slots to ensure compatibility with tumorDetails() and subBlockDetails()
    unique_tumors <- unique(coldata\$tumor_name)
    tumor_subtypes <- coldata\$condition[match(unique_tumors, coldata\$tumor_name)]
    tumor_det <- data.frame(
      tumor_name = unique_tumors,
      molecular_subtype = tumor_subtypes,
      donor_id = unique_tumors,
      stringsAsFactors = FALSE
    )
    metadata(se)\$tumorDetails <- tumor_det
    
    sub_det <- data.frame(
      study_name = rep("Anatomic Structures RNA Seq", nrow(coldata)),
      stringsAsFactors = FALSE
    )
    metadata(se)\$subBlockDetails <- sub_det
    
    # ==========================================
    # --- Extract Metadata & Generate Design Plots ---
    # ==========================================
    
    # Generate design overview and nomenclature plots
    pdf("design_and_nomenclature.pdf", width=10, height=8)
    tryCatch({
      designOverview()
    }, error = function(e) {
      grid::grid.newpage()
      grid::grid.text("designOverview() plot unavailable")
    })
    tryCatch({
      nomenclat()
    }, error = function(e) {
      grid::grid.newpage()
      grid::grid.text("nomenclat() plot unavailable")
    })
    dev.off()
    
    # Extract and save tumor and sub-block details using package functions
    tum_details <- tumorDetails(se)
    write.csv(tum_details, "tumor_details.csv", row.names=FALSE)
    
    sub_details <- subBlockDetails(se)
    write.csv(sub_details, "subblock_details.csv", row.names=FALSE)
    
    # ==========================================
    # --- Differential Expression by Molecular Subtype ---
    # ==========================================
    
    # Bind molecular subtype information to the expression sample annotation
    moltype <- tumorDetails(se)\$molecular_subtype
    names(moltype) <- tumorDetails(se)\$tumor_name
    moltype[nchar(moltype) == 0] <- "missing"
    se\$moltype <- factor(moltype[se\$tumor_name])
    
    # Confine attention to samples annotated as "reference histology"
    refex <- se[, grep("reference", se\$structure_acronym)]
    refmat <- assay(refex)
    
    # Build design matrix
    tydes <- model.matrix(~moltype, data=as.data.frame(colData(refex)))
    ok_cols <- which(apply(tydes, 2, sum) > 0)
    tydes <- tydes[, ok_cols, drop=FALSE]
    
    block <- factor(refex\$tumor_id)
    
    # Compute duplicate correlation and fit linear model (with robust fallback)
    ef2 <- tryCatch({
      dd <- duplicateCorrelation(refmat, tydes, block=block)
      f2 <- lmFit(refmat, tydes, correlation=dd\$consensus)
      eBayes(f2)
    }, error = function(e) {
      warning("duplicateCorrelation failed; falling back to standard lmFit: ", e\$message)
      f2 <- lmFit(refmat, tydes)
      eBayes(f2)
    })
    
    # Extract top differentially expressed genes
    coef_to_test <- if(ncol(tydes) > 1) 2 else 1
    de_table <- topTable(ef2, coef=coef_to_test, number=Inf)
    write.csv(de_table, "limma_molecular_subtype_de.csv")
    
    # ==========================================
    # --- Classification of Structural Character ---
    # ==========================================
    
    refex\$struc <- factor(refex\$structure_acronym)
    
    # Filter features by Interquartile Range (IQR) exceeding the median IQR
    iqrs <- apply(assay(refex), 1, IQR)
    inds <- which(iqrs > quantile(iqrs, 0.5))
    
    if (length(inds) > 0 && length(unique(refex\$struc)) > 1) {
      set.seed(1234)
      tryCatch({
        mtry_val <- min(30, length(inds))
        rf1 <- randomForest(
          x = t(assay(refex[inds, , drop=FALSE])),
          y = refex\$struc,
          mtry = mtry_val,
          importance = TRUE
        )
        
        # Save confusion matrix
        write.csv(rf1\$confusion, "rf_confusion_matrix.csv")
        
        # Save variable importance plot
        pdf("rf_variable_importance.pdf", width=8, height=6)
        varImpPlot(rf1)
        dev.off()
      }, error = function(e) {
        warning("Random Forest classification failed: ", e\$message)
        write.csv(data.frame(Error = e\$message), "rf_confusion_matrix.csv")
        pdf("rf_variable_importance.pdf")
        grid::grid.newpage()
        grid::grid.text(paste("RF failed:", e\$message))
        dev.off()
      })
    } else {
      write.csv(data.frame(Message = "Insufficient classes or genes for RF"), "rf_confusion_matrix.csv")
      pdf("rf_variable_importance.pdf")
      grid::grid.newpage()
      grid::grid.text("Insufficient classes or genes for RF")
      dev.off()
    }
    
    # ==========================================
    # --- Run Package's Built-in Reference Limma ---
    # ==========================================
    
    tryCatch({
      ebout <- getRefLimma()
      ref_de <- topTable(ebout, coef=2, number=100)
      write.csv(ref_de, "package_ref_limma.csv")
    }, error = function(e) {
      write.csv(data.frame(Error = e\$message), "package_ref_limma.csv")
    })

    writeLines(c(
        '"BIOC_IVYGAPSE_IVYGAP_GLIOBLASTOMA_ANALYSIS":',
        paste0('    ivygapSE: ', as.character(packageVersion('ivygapSE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ivygap_glioblastoma_analysis.csv versions.yml
    """
}

workflow BIOC_IVYGAPSE_IVYGAP_GLIOBLASTOMA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_IVYGAPSE_IVYGAP_GLIOBLASTOMA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_IVYGAPSE_IVYGAP_GLIOBLASTOMA_ANALYSIS.out.tables
    plots    = BIOC_IVYGAPSE_IVYGAP_GLIOBLASTOMA_ANALYSIS.out.plots
    objects  = BIOC_IVYGAPSE_IVYGAP_GLIOBLASTOMA_ANALYSIS.out.objects
    versions = BIOC_IVYGAPSE_IVYGAP_GLIOBLASTOMA_ANALYSIS.out.versions
}
