#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HIBAG — custom_model_training_validation
// Train a custom HIBAG model using a reference panel of known HLA and SNP genotypes, validate its accuracy, and export a clean model for release.
// Input: HLA_Type_Table, HapMap_CEU_Geno
// Container: quay.io/biocontainers/bioconductor-hibag:1.46.0--r45ha27e39d_0
// R packages: HIBAG
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIBAG_CUSTOM_MODEL_TRAINING_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hibag:1.46.0--r45ha27e39d_0"

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
    .bm_deps <- c("HIBAG")
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
    library(HIBAG)
    library(parallel)
    
    # Helper function to load user inputs robustly from the working directory
    load_input <- function(filename) {
      if (file.exists(filename)) {
        # Try reading as RDS
        obj <- tryCatch(readRDS(filename), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
        
        # Try loading as RData
        env <- new.env()
        tryCatch({
          load(filename, envir = env)
          vars <- ls(env)
          if (length(vars) > 0) return(get(vars[1], envir = env))
        }, error = function(e) NULL)
      }
      
      # Try with common extensions if the exact name wasn't found or failed
      for (ext in c(".rds", ".RData", ".rdata", ".Rda")) {
        fn <- paste0(filename, ext)
        if (file.exists(fn)) {
          if (tolower(ext) == ".rds") {
            return(readRDS(fn))
          } else {
            env <- new.env()
            load(fn, envir = env)
            vars <- ls(env)
            if (length(vars) > 0) return(get(vars[1], envir = env))
          }
        }
      }
      stop(paste("Could not find or read input file:", filename))
    }
    
    # Read user inputs
    HLA_Type_Table <- load_input("HLA_Type_Table")
    HapMap_CEU_Geno <- load_input("HapMap_CEU_Geno")
    
    # --- Format reference HLA alleles ---
    hla.id <- "A"
    train.HLA <- hlaAllele (HLA_Type_Table \$ sample.id, H1 = HLA_Type_Table[, paste (hla.id, ".1" , sep= "" )], H2 = HLA_Type_Table[, paste (hla.id, ".2" , sep= "" )], locus= hla.id, assembly= "hg19" )
    
    # --- Define flanking SNP regions and subset genotypes ---
    region <- 500
    train.geno <- hlaGenoSubsetFlank (HapMap_CEU_Geno, hla.id, region * 1000 , assembly= "hg19" )
    summary (train.geno)
    
    # --- Train the HIBAG model sequentially ---
    set.seed ( 100 )
    model <- hlaAttrBagging (train.HLA, train.geno, nclassifier= 100 )
    summary (model)
    
    # --- Train the HIBAG model in parallel ---
    cl <- 2
    set.seed ( 1000 )
    hlaParallelAttrBagging (cl, train.HLA, train.geno, nclassifier= 100 , auto.save= "AutoSaveModel.RData" )
    model.obj <- get ( load ( "AutoSaveModel.RData" ))
    model <- hlaModelFromObj (model.obj)
    summary (model)
    
    # Define placeholders for prediction and splitting as per documented workflow
    yourgeno <- train.geno
    hla <- train.HLA
    
    # Predict HLA alleles on training/test data
    pred.guess <- hlaPredict (model, yourgeno, type= "response+prob" , cl= cl)
    
    # --- Split reference data into training and validation sets ---
    hlatab <- hlaSplitAllele (hla, train.prop= 0.5 )
    snpid <- hlaFlankingSNP (HapMap_CEU_Geno \$ snp.id, HapMap_CEU_Geno \$ snp.position, hla.id, region * 1000 , assembly= "hg19" )
    train.geno <- hlaGenoSubset (HapMap_CEU_Geno, snp.sel = match (snpid, HapMap_CEU_Geno \$ snp.id), samp.sel = match (hlatab \$ training \$ value \$ sample.id, HapMap_CEU_Geno \$ sample.id))
    test.geno <- hlaGenoSubset (HapMap_CEU_Geno, samp.sel= match ( hlatab \$ validation \$ value \$ sample.id, HapMap_CEU_Geno \$ sample.id))
    
    # Train model on split training set
    model <- hlaAttrBagging (hlatab \$ training, train.geno, nclassifier= 100 )
    
    # Predict HLA alleles on validation data
    pred <- hlaPredict (model, test.geno)
    
    # Save predictions to RDS
    saveRDS(pred, file = "HIBAG_validation_predictions.rds")
    
    # --- Evaluate accuracy and generate diagnostic plots/reports ---
    comp <- hlaCompareAllele (hlatab \$ validation, pred, allele.limit= model, call.threshold= 0 )
    comp \$ overall
    
    # Write overall accuracy to CSV
    write.csv(comp\$overall, file = "HIBAG_overall_accuracy.csv", row.names = FALSE)
    
    # Generate hierarchical clustering and diagnostic plots
    d <- hlaDistance (model)
    p <- hclust ( as.dist (d))
    
    pdf("HIBAG_diagnostic_plots.pdf", width = 8, height = 6)
    plot (p, xlab= "HLA alleles" )
    hlaReportPlot (pred, model= model, fig= "matching" )
    hlaReportPlot (pred, hlatab \$ validation, fig= "call.rate" )
    hlaReportPlot (pred, hlatab \$ validation, fig= "call.threshold" )
    dev.off()
    
    # Generate reports in different formats
    sink("HIBAG_report.txt")
    hlaReport (comp, type= "txt" )
    sink()
    
    sink("HIBAG_report.md")
    hlaReport (comp, type= "markdown" )
    sink()
    
    sink("HIBAG_report.tex")
    hlaReport (comp, type= "tex" , header= FALSE )
    sink()
    
    # --- Publish and anonymize the model for public release ---
    mobj <- hlaPublish (model, platform = "Illumina 1M Duo" , information = "Training set -- HapMap Phase II" , warning = NULL , rm.unused.snp= TRUE , anonymize= TRUE )
    save (mobj, file= "Your_HIBAG_Model.RData" )

    writeLines(c(
        '"BIOC_HIBAG_CUSTOM_MODEL_TRAINING_VALIDATION":',
        paste0('        HIBAG: ', as.character(packageVersion("HIBAG")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_model_training_validation.csv versions.yml
    """
}

workflow BIOC_HIBAG_CUSTOM_MODEL_TRAINING_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HLA_Type_Table, HapMap_CEU_Geno ] ]

    main:
    BIOC_HIBAG_CUSTOM_MODEL_TRAINING_VALIDATION(ch_input)

    emit:
    tables   = BIOC_HIBAG_CUSTOM_MODEL_TRAINING_VALIDATION.out.tables
    plots    = BIOC_HIBAG_CUSTOM_MODEL_TRAINING_VALIDATION.out.plots
    objects  = BIOC_HIBAG_CUSTOM_MODEL_TRAINING_VALIDATION.out.objects
    versions = BIOC_HIBAG_CUSTOM_MODEL_TRAINING_VALIDATION.out.versions
}
