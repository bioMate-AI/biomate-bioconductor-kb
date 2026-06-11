#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: netsam — stepwise_correlation_network_analysis
// Manually construct a correlation network (or consensus network), identify modules, and perform feature and GO association analyses step-by-step.
// Input: expression.cct
// Container: quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0
// R packages: NetSAM
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETSAM_STEPWISE_CORRELATION_NETWORK_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("NetSAM")
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
    
    # Load the required library
    library("NetSAM")
    
    # Define input file paths
    expression_file <- "expression.cct"
    sample_ann_file <- "sample_annotation.tsi"
    
    # Verify that the required user input files exist in the working directory
    if (!file.exists(expression_file)) {
      stop(paste("Required input file missing:", expression_file))
    }
    if (!file.exists(sample_ann_file)) {
      stop(paste("Required input file missing:", sample_ann_file))
    }
    
    # ==========================================
    # Step 1: Construct Correlation Networks
    # ==========================================
    
    # 1a. Construct correlation network using MatNet
    message("Constructing correlation network using MatNet...")
    matNetwork <- MatNet(
      inputMat = expression_file, 
      collapse_mode = "maxSD", 
      naPer = 0.7, 
      meanPer = 0.8, 
      varPer = 0.8,
      corrType = "spearman", 
      matNetMethod = "rank", 
      valueThr = 0.6, 
      rankBest = 0.003, 
      networkType = "signed",
      netFDRMethod = "BH", 
      netFDRThr = 0.05, 
      idNumThr = (-1), 
      nThreads = 3
    )
    
    # Save MatNet network output
    write.csv(matNetwork, "matNetwork.csv", row.names = FALSE)
    message("MatNet network saved to 'matNetwork.csv'.")
    
    # 1b. Construct consensus network using consensusNet
    message("Constructing consensus network using consensusNet...")
    expression_data <- read.table(expression_file, header = TRUE, row.names = 1, stringsAsFactors = FALSE)
    net <- consensusNet(
      data = expression_data, 
      organism = "hsapiens", 
      bootstrapNum = 10, 
      naPer = 0.5, 
      meanPer = 0.8, 
      varPer = 0.8, 
      method = "rank_unsig", 
      value = 3/1000, 
      pth = 1e-6, 
      nMatNet = 2, 
      nThreads = 4
    )
    
    # Save consensusNet network output
    write.csv(net, "consensusNet.csv", row.names = FALSE)
    message("Consensus network saved to 'consensusNet.csv'.")
    
    
    # ==========================================
    # Step 2: Run NetSAM on the Constructed Network
    # ==========================================
    message("Running NetSAM on the constructed MatNet network...")
    netsam_output_file <- paste(getwd(), "/NetSAM_output", sep = "")
    netsam_output <- NetSAM(
      inputNetwork = matNetwork, 
      outputFileName = netsam_output_file, 
      outputFormat = "none",
      edgeType = "unweighted", 
      map_to_genesymbol = FALSE, 
      organism = "hsapiens", 
      idType = "auto", 
      minModule = 0.003,
      stepIte = FALSE, 
      maxStep = 4, 
      moduleSigMethod = "cutoff", 
      modularityThr = 0.2, 
      ZRanNum = 10,
      PerRanNum = 100, 
      ranSig = 0.05, 
      edgeThr = (-1), 
      nodeThr = (-1), 
      nThreads = 3
    )
    
    # Save NetSAM output object
    saveRDS(netsam_output, "netsam_output.rds")
    message("NetSAM output object saved to 'netsam_output.rds'.")
    
    
    # ==========================================
    # Step 3: Calculate Feature Associations
    # ==========================================
    message("Calculating associations between sample features and modules...")
    outputHtmlFile_feat <- paste(getwd(), "/featureAsso_HTML", sep = "")
    featureAsso <- featureAssociation(
      inputMat = expression_file, 
      sampleAnn = sample_ann_file, 
      NetSAMOutput = netsam_output, 
      outputHtmlFile = outputHtmlFile_feat, 
      CONMethod = "spearman", 
      CATMethod = "kruskal", 
      BINMethod = "ranktest", 
      fdrmethod = "BH", 
      pth = 0.05, 
      collapse_mode = "maxSD"
    )
    
    # Save feature association results
    write.csv(featureAsso, "featureAsso.csv", row.names = FALSE)
    message("Feature association results saved to 'featureAsso.csv' and HTML report generated at 'featureAsso_HTML'.")
    
    
    # ==========================================
    # Step 4: Identify Associated GO Terms
    # ==========================================
    message("Identifying associated GO terms for modules...")
    outputHtmlFile_go <- paste(getwd(), "/GOAsso_HTML", sep = "")
    GOAsso <- GOAssociation(
      NetSAMOutput = netsam_output, 
      outputHtmlFile = outputHtmlFile_go, 
      organism = "hsapiens", 
      fdrmethod = "BH", 
      fdrth = 0.05, 
      topNum = 5
    )
    
    # Save GO association results
    write.csv(GOAsso, "GOAsso.csv", row.names = FALSE)
    message("GO association results saved to 'GOAsso.csv' and HTML report generated at 'GOAsso_HTML'.")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_NETSAM_STEPWISE_CORRELATION_NETWORK_ANALYSIS":',
        paste0('        netsam: ', as.character(packageVersion("netsam")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stepwise_correlation_network_analysis.csv versions.yml
    """
}

workflow BIOC_NETSAM_STEPWISE_CORRELATION_NETWORK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression.cct ] ]

    main:
    BIOC_NETSAM_STEPWISE_CORRELATION_NETWORK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NETSAM_STEPWISE_CORRELATION_NETWORK_ANALYSIS.out.tables
    plots    = BIOC_NETSAM_STEPWISE_CORRELATION_NETWORK_ANALYSIS.out.plots
    objects  = BIOC_NETSAM_STEPWISE_CORRELATION_NETWORK_ANALYSIS.out.objects
    versions = BIOC_NETSAM_STEPWISE_CORRELATION_NETWORK_ANALYSIS.out.versions
}
