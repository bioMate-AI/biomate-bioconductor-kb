#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AMARETTO — amaretto_multi_omics_pipeline
// Download TCGA multi-omics data, preprocess it, run the AMARETTO algorithm to identify driver-connected co-expressed gene modules, evaluate the model, and genera
// Input: CancerSite, BatchData, gmt_file
// Container: quay.io/biocontainers/bioconductor-amaretto:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AMARETTO
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download TCGA data using AMARETTO_Download
//  * 2. [Core Analysis] Preprocess the downloaded data using AMARETTO_Preprocess
//  * 3. [Core Analysis] Initialize the AMARETTO algorithm using AMARETTO_Initialize
//  * 4. [Core Analysis] Run the AMARETTO algorithm using AMARETTO_Run
//  * 5. [Core Analysis] Evaluate the model on a test set using AMARETTO_EvaluateTestSet
//  * 6. [Visualization & Output] Visualize specific modules using AMARETTO_VisualizeModule
//  * 7. [Visualization & Output] Generate an HTML report with gene set enrichment using AMARETTO_HTMLreport

nextflow.enable.dsl = 2

process BIOC_AMARETTO_AMARETTO_MULTI_OMICS_PIPELINE {
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
    .bm_deps <- c("AMARETTO")
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
    
    library(AMARETTO)
    
    # 1. Read User Inputs
    cancer_site_file <- "CancerSite"
    if (!file.exists(cancer_site_file)) {
      cancer_site_file <- "CancerSite.txt"
    }
    if (file.exists(cancer_site_file)) {
      CancerSite <- trimws(readLines(cancer_site_file, n = 1))
    } else {
      stop("Error: CancerSite file not found in the working directory.")
    }
    
    batch_data_file <- "BatchData"
    if (!file.exists(batch_data_file)) {
      batch_data_file <- "BatchData.Rda"
    }
    if (!file.exists(batch_data_file)) {
      batch_data_file <- "BatchData.rda"
    }
    if (file.exists(batch_data_file)) {
      env <- new.env()
      load(batch_data_file, envir = env)
      obj_names <- ls(env)
      if ("BatchData" %in% obj_names) {
        BatchData <- env\$BatchData
      } else if (length(obj_names) > 0) {
        BatchData <- env[[obj_names[1]]]
      } else {
        stop("Error: No objects found in BatchData Rda file.")
      }
    } else {
      stop("Error: BatchData file not found in the working directory.")
    }
    
    gmt_file_path <- "gmt_file"
    if (!file.exists(gmt_file_path)) {
      gmt_file_path <- "gmt_file.gmt"
    }
    if (file.exists(gmt_file_path)) {
      gmt_file <- gmt_file_path
    } else {
      stop("Error: gmt_file not found in the working directory.")
    }
    
    # 2. Download TCGA Data
    TargetDirectory <- tempfile()
    DataSetDirectories <- AMARETTO_Download(CancerSite = CancerSite,
                                            TargetDirectory = TargetDirectory)
    
    # 3. Preprocess Data
    ProcessedData <- AMARETTO_Preprocess(DataSetDirectories = DataSetDirectories,
                                         BatchData = BatchData)
    
    # 4. Initialize AMARETTO
    AMARETTOinit <- AMARETTO_Initialize(ProcessedData = ProcessedData,
                                        NrModules = 2, VarPercentage = 50)
    
    # 5. Run AMARETTO
    AMARETTOresults <- AMARETTO_Run(AMARETTOinit = AMARETTOinit)
    
    # 6. Evaluate Model
    AMARETTOtestReport <- AMARETTO_EvaluateTestSet(
                          AMARETTOresults = AMARETTOresults,
                          MA_Data_TestSet = AMARETTOinit\$MA_matrix_Var,
                          RegulatorData_TestSet = AMARETTOinit\$RegulatorData
                          )
    
    # 7. Visualize Module
    ModuleNr <- 1
    pdf("AMARETTO_Module_1_Heatmap.pdf", width = 10, height = 8)
    AMARETTO_VisualizeModule(AMARETTOinit = AMARETTOinit, 
                             AMARETTOresults = AMARETTOresults,
                             ProcessedData = ProcessedData, 
                             ModuleNr = ModuleNr)
    dev.off()
    
    # 8. Generate HTML Report
    AMARETTO_HTMLreport(AMARETTOinit = AMARETTOinit,
                        AMARETTOresults = AMARETTOresults,
                        ProcessedData = ProcessedData,
                        hyper_geo_test_bool = TRUE,
                        hyper_geo_reference = gmt_file,
                        MSIGDB=TRUE)
    
    # 9. Save Outputs
    saveRDS(ProcessedData, "ProcessedData.rds")
    saveRDS(AMARETTOinit, "AMARETTOinit.rds")
    saveRDS(AMARETTOresults, "AMARETTOresults.rds")
    saveRDS(AMARETTOtestReport, "AMARETTOtestReport.rds")

    writeLines(c(
        '"BIOC_AMARETTO_AMARETTO_MULTI_OMICS_PIPELINE":',
        paste0('    AMARETTO: ', as.character(packageVersion('AMARETTO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_amaretto_multi_omics_pipeline.csv versions.yml
    """
}

workflow BIOC_AMARETTO_AMARETTO_MULTI_OMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CancerSite, BatchData, gmt_file ] ]

    main:
    BIOC_AMARETTO_AMARETTO_MULTI_OMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_AMARETTO_AMARETTO_MULTI_OMICS_PIPELINE.out.tables
    plots    = BIOC_AMARETTO_AMARETTO_MULTI_OMICS_PIPELINE.out.plots
    objects  = BIOC_AMARETTO_AMARETTO_MULTI_OMICS_PIPELINE.out.objects
    versions = BIOC_AMARETTO_AMARETTO_MULTI_OMICS_PIPELINE.out.versions
}
