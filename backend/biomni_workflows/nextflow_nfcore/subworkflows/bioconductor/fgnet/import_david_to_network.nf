#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FGNet — import_david_to_network
// Import Functional Annotation Clustering results from the DAVID website and build a functional network.
// Input: "http://david.abcc.ncifcrf.gov/data/download/90128.txt", genesYeastExpr
// Container: quay.io/biocontainers/bioconductor-fgnet:3.44.0--r45hdfd78af_0
// R packages: FGNet, org.Sc.sgd.db
// Bioconductor: 3.20 | R: 4.4
// Requires: FGNet, org.Sc.sgd.db
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import results using format_david()
//  * 2. [Visualization & Output] Generate an HTML report using FGNet_report()
//  * 3. [Core Analysis] Convert results to incidence matrices using fea2incidMat()
//  * 4. [Visualization & Output] Plot the network using functionalNetwork()

nextflow.enable.dsl = 2

process BIOC_FGNET_IMPORT_DAVID_TO_NETWORK {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("FGNet", "org.Sc.sgd.db")
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
    library(FGNet)
    
    # 1. Handle input for genesYeastExpr
    # Check if user provided genesYeastExpr as an RDS or CSV file in the working directory.
    # If not, reconstruct it using the standard org.Sc.sgd.db annotation package.
    if (file.exists("genesYeastExpr.rds")) {
      genesYeastExpr <- readRDS("genesYeastExpr.rds")
    } else if (file.exists("genesYeastExpr.csv")) {
      expr_df <- read.csv("genesYeastExpr.csv", row.names = 1)
      genesYeastExpr <- setNames(expr_df[[1]], rownames(expr_df))
    } else {
      library(org.Sc.sgd.db)
      genesYeast <- c("ADA2", "APC1", "APC11", "APC2", "APC4", "APC5", "APC9", "CDC16", 
                      "CDC23", "CDC26", "CDC27", "CFT1", "CFT2", "DCP1", "DOC1", "FIP1", 
                      "GCN5", "GLC7", "HFI1", "KEM1", "LSM1", "LSM2", "LSM3", "LSM4", 
                      "LSM5", "LSM6", "LSM7", "LSM8", "MPE1", "NGG1", "PAP1", "PAT1", 
                      "PFS2", "PTA1", "PTI1", "REF2", "RNA14", "RPN1", "RPN10", "RPN11", 
                      "RPN13", "RPN2", "RPN3", "RPN5", "RPN6", "RPN8", "RPT1", "RPT3", 
                      "RPT6", "SGF11", "SGF29", "SGF73", "SPT20", "SPT3", "SPT7", "SPT8", 
                      "TRA1", "YSH1", "YTH1")
      geneLabels <- unlist(as.list(org.Sc.sgdGENENAME))
      genesYeast <- sort(geneLabels[which(geneLabels %in% genesYeast)])
      genesYeastExpr <- setNames(c(rep(1, 28), rep(-1, 30)), genesYeast)
    }
    
    # 2. Import Functional Annotation Clustering results from DAVID
    feaResults_David <- format_david("http://david.abcc.ncifcrf.gov/data/download/90128.txt")
    saveRDS(feaResults_David, "feaResults_David.rds")
    
    # 3. Generate HTML report
    FGNet_report(feaResults_David, geneExpr=genesYeastExpr)
    
    # 4. Convert results to incidence matrices
    incidMat <- fea2incidMat(feaResults_David)
    saveRDS(incidMat, "incidMat.rds")
    
    # Save incidence matrices as CSV files for downstream analysis
    if (!is.null(incidMat\$clustersMatrix)) {
      write.csv(as.matrix(incidMat\$clustersMatrix), "clusters_matrix.csv", row.names = TRUE)
    }
    if (!is.null(incidMat\$gtSetsMatrix)) {
      write.csv(as.matrix(incidMat\$gtSetsMatrix), "gtsets_matrix.csv", row.names = TRUE)
    }
    
    # 5. Plot the functional network and save to PDF
    pdf("functional_network.pdf", width = 12, height = 12)
    functionalNetwork(incidMat)
    dev.off()

    writeLines(c(
        '"BIOC_FGNET_IMPORT_DAVID_TO_NETWORK":',
        paste0('    FGNet: ', as.character(packageVersion('FGNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_david_to_network.csv versions.yml
    """
}

workflow BIOC_FGNET_IMPORT_DAVID_TO_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ "http://david.abcc.ncifcrf.gov/data/download/90128.txt", genesYeastExpr ] ]

    main:
    BIOC_FGNET_IMPORT_DAVID_TO_NETWORK(ch_input)

    emit:
    tables   = BIOC_FGNET_IMPORT_DAVID_TO_NETWORK.out.tables
    plots    = BIOC_FGNET_IMPORT_DAVID_TO_NETWORK.out.plots
    objects  = BIOC_FGNET_IMPORT_DAVID_TO_NETWORK.out.objects
    versions = BIOC_FGNET_IMPORT_DAVID_TO_NETWORK.out.versions
}
