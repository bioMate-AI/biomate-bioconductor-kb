#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DExMA — standard_meta_analysis
// Perform a complete gene expression meta-analysis workflow including data preparation, annotation harmonization, log transformation, heterogeneity testing, optio
// Input: listMatrixEX, listPhenodatas
// Container: quay.io/biocontainers/bioconductor-dexma:1.18.0--r45hdfd78af_0
// R packages: Biobase, DExMA, swamp
// Bioconductor: 3.20 | R: 4.4
// Requires: DExMA
// Visualizations: heatmap
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create meta-analysis object
//  * 2. [Core Analysis] Harmonize gene IDs
//  * 3. [Core Analysis] Log-transform data
//  * 4. [Core Analysis] Test for heterogeneity
//  * 5. [Core Analysis] Impute missing genes (optional)
//  * 6. [Core Analysis] Perform meta-analysis
//  * 7. [Visualization & Output] Visualize results via heatmap

nextflow.enable.dsl = 2

process BIOC_DEXMA_STANDARD_META_ANALYSIS {
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
    .bm_deps <- c("Biobase", "DExMA", "swamp")
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
    library(DExMA)
    
    # Read user input files from the working directory
    if (file.exists("listMatrixEX.rds")) {
      listMatrixEX <- readRDS("listMatrixEX.rds")
    } else if (file.exists("listMatrixEX.RData")) {
      load("listMatrixEX.RData")
    } else {
      stop("Error: listMatrixEX file (RDS or RData) not found in the working directory.")
    }
    
    if (file.exists("listPhenodatas.rds")) {
      listPhenodatas <- readRDS("listPhenodatas.rds")
    } else if (file.exists("listPhenodatas.RData")) {
      load("listPhenodatas.RData")
    } else {
      stop("Error: listPhenodatas file (RDS or RData) not found in the working directory.")
    }
    
    # 1. Create meta-analysis object
    num_studies <- length(listPhenodatas)
    phenoGroups <- rep(1, num_studies)
    phenoCases <- rep(1, num_studies)
    phenoControls <- rep(2, num_studies)
    
    newObjectMA <- createObjectMA(listEX=listMatrixEX,
                                    listPheno = listPhenodatas,
                                    namePheno=phenoGroups,
                                    expGroups=phenoCases, 
                                    refGroups = phenoControls)
    
    # 2. Harmonize gene IDs
    newObjectMA <- allSameID(newObjectMA, finalID="GeneSymbol", organism = "Homo sapiens")
    
    # 3. Log-transform data
    newObjectMA <- dataLog(newObjectMA)
    
    # 4. Test for heterogeneity
    pdf("heterogeneity_test.pdf")
    heterogeneityTest(newObjectMA)
    dev.off()
    
    # 5. Impute missing genes (optional)
    maObject <- newObjectMA
    tryCatch({
      imputation <- missGenesImput(maObject, k = 7)
      maObject_imput <- imputation\$objectMA
      saveRDS(maObject_imput, "imputed_ma_object.rds")
    }, error = function(e) {
      message("Optional imputation step skipped or failed: ", e\$message)
    })
    
    # 6. Perform meta-analysis
    resultsMA <- metaAnalysisDE(newObjectMA, typeMethod="REM",
                                missAllow=0.3, proportionData=0.50)
    write.csv(resultsMA, "results_meta_analysis.csv", row.names = TRUE)
    
    # 7. Visualize results via heatmap
    pdf("heatmap.pdf", width = 10, height = 10)
    makeHeatmap(objectMA=newObjectMA, resMA=resultsMA, scaling = "zscor", 
                regulation = "all", numSig=40,
                fdrSig = 0.05, logFCSig = 1.5, show_rownames = TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_DEXMA_STANDARD_META_ANALYSIS":',
        paste0('    DExMA: ', as.character(packageVersion('DExMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_meta_analysis.csv versions.yml
    """
}

workflow BIOC_DEXMA_STANDARD_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ listMatrixEX, listPhenodatas ] ]

    main:
    BIOC_DEXMA_STANDARD_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DEXMA_STANDARD_META_ANALYSIS.out.tables
    plots    = BIOC_DEXMA_STANDARD_META_ANALYSIS.out.plots
    objects  = BIOC_DEXMA_STANDARD_META_ANALYSIS.out.objects
    versions = BIOC_DEXMA_STANDARD_META_ANALYSIS.out.versions
}
