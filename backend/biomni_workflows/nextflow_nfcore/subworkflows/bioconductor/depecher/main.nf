#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DepecheR — depeche_clustering_and_group_separation
// Perform sparse K-means clustering on single-cell data, visualize clusters and marker expressions on a 2D representation, and identify which clusters statistical
// Input: testData, testDataSNE
// Container: quay.io/biocontainers/bioconductor-depecher:1.26.0--r45h617649d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DepecheR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform sparse K-means clustering using depeche
//  * 2. [Visualization & Output] Visualize cluster distribution and marker expression on 2D coordinates using dColorPlot
//  * 3. [Visualization & Output] Generate density contours using dContours and plot group-specific densities using dDensityPlot
//  * 4. [Core Analysis] Analyze group differences per cluster using dResidualPlot
//  * 5. [Core Analysis] Perform statistical group separation using dWilcox and dSplsda
//  * 6. [Visualization & Output] Visualize defining markers for significant clusters using dViolins

nextflow.enable.dsl = 2

process BIOC_DEPECHER_DEPECHE_CLUSTERING_AND_GROUP_SEPARATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("DepecheR")
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
        
        # Load required library
        library(DepecheR)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        # The pipeline expects 'testData' and 'testDataSNE' in the working directory.
        # We support both RDS and CSV formats.
        
        if (file.exists("testData.rds")) {
            testData <- readRDS("testData.rds")
        } else if (file.exists("testData.csv")) {
            testData <- read.csv("testData.csv", row.names = 1, check.names = FALSE)
        } else {
            stop("Error: 'testData' file (RDS or CSV) not found in the working directory.")
        }
        
        if (file.exists("testDataSNE.rds")) {
            testDataSNE <- readRDS("testDataSNE.rds")
        } else if (file.exists("testDataSNE.csv")) {
            testDataSNE <- read.csv("testDataSNE.csv", row.names = 1, check.names = FALSE)
        } else {
            stop("Error: 'testDataSNE' file (RDS or CSV) not found in the working directory.")
        }
        
        # Ensure testDataSNE has a 'Y' slot as expected by the documented code
        if (!is.list(testDataSNE) || is.data.frame(testDataSNE)) {
            testDataSNE <- list(Y = as.matrix(testDataSNE))
        } else if (is.list(testDataSNE) && !"Y" %in% names(testDataSNE)) {
            testDataSNE\$Y <- testDataSNE[[1]]
        }
        
        # ==========================================
        # 2. Execute Documented Workflow
        # ==========================================
        
        # Identify marker columns dynamically (excluding 'ids' and 'label')
        marker_cols <- setdiff(colnames(testData), c("ids", "label"))
        
        # Step 1: Perform sparse K-means clustering using depeche
        testDataDepeche <- depeche(testData[, marker_cols])
        
        # Step 2: Visualize cluster distribution and marker expression on 2D coordinates using dColorPlot
        dColorPlot(colorData = testDataDepeche\$clusterVector, xYData = testDataSNE\$Y, 
                   colorScale = "dark_rainbow", plotName = "Cluster")
        dColorPlot(colorData = testData[, marker_cols[1]], xYData = testDataSNE\$Y)
        
        # Step 3: Generate density contours using dContours and plot group-specific densities using dDensityPlot
        densContour <- dContours(testDataSNE\$Y)
        
        dDensityPlot(xYData = testDataSNE\$Y, plotName = 'All_events', 
                     colorScale="purple3", densContour = densContour)
        
        groups <- unique(testData\$label)
        
        # Here the data for the first group is plotted
        if (length(groups) > 0) {
            dDensityPlot(xYData = testDataSNE\$Y[testData\$label==groups[1], , drop=FALSE], plotName = paste0('Group_', groups[1]), 
                         colorScale="blue", densContour = densContour)
        }
        
        # And here comes the second group
        if (length(groups) > 1) {
            dDensityPlot(xYData = testDataSNE\$Y[testData\$label==groups[2], , drop=FALSE], plotName = paste0('Group_', groups[2]), 
                         colorScale="red", densContour = densContour)
        }
        
        # Step 4: Analyze group differences per cluster using dResidualPlot
        dResidualPlot(
            xYData = testDataSNE\$Y, groupVector = testData\$label,
            clusterVector = testDataDepeche\$clusterVector)
        
        # Step 5: Perform statistical group separation using dWilcox and dSplsda
        dWilcoxResult <- dWilcox(
            xYData = testDataSNE\$Y, idsVector = testData\$ids,
            groupVector = testData\$label, clusterVector = testDataDepeche\$clusterVector)
        
        sPLSDAObject <- dSplsda(xYData = testDataSNE\$Y, idsVector = testData\$ids,
                                groupVector = testData\$label,
                                clusterVector = testDataDepeche\$clusterVector)
        
        # Step 6: Visualize defining markers for significant clusters using dViolins
        plot_cluster <- unique(testDataDepeche\$clusterVector)[1]
        dViolins(testDataDepeche\$clusterVector, inDataFrame = testData, 
                 plotClusters = plot_cluster, plotElements = testDataDepeche\$essenceElementList)
        
        # ==========================================
        # 3. Save Outputs
        # ==========================================
        saveRDS(testDataDepeche, "testDataDepeche.rds")
        write.csv(dWilcoxResult, "dWilcoxResult.csv", row.names = FALSE)
        saveRDS(sPLSDAObject, "sPLSDAObject.rds")
        
        message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_DEPECHER_DEPECHE_CLUSTERING_AND_GROUP_SEPARATION":',
        paste0('    DepecheR: ', as.character(packageVersion('DepecheR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_depeche_clustering_and_group_separation.csv versions.yml
    """
}

workflow BIOC_DEPECHER_DEPECHE_CLUSTERING_AND_GROUP_SEPARATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testData, testDataSNE ] ]

    main:
    BIOC_DEPECHER_DEPECHE_CLUSTERING_AND_GROUP_SEPARATION(ch_input)

    emit:
    tables   = BIOC_DEPECHER_DEPECHE_CLUSTERING_AND_GROUP_SEPARATION.out.tables
    plots    = BIOC_DEPECHER_DEPECHE_CLUSTERING_AND_GROUP_SEPARATION.out.plots
    objects  = BIOC_DEPECHER_DEPECHE_CLUSTERING_AND_GROUP_SEPARATION.out.objects
    versions = BIOC_DEPECHER_DEPECHE_CLUSTERING_AND_GROUP_SEPARATION.out.versions
}
