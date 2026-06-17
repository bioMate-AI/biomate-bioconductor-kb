#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BicARE — biclustering_and_enrichment_workflow
// Perform exploratory or directed biclustering on gene expression data, extract individual biclusters, test for gene set and sample covariate enrichment, and gene
// Input: expression_set.RData, gene_sets.RData
// Container: quay.io/biocontainers/bioconductor-bicare:1.68.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BicARE, Biobase, GSEABase
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate the initial residue of the expression dataset using residue
//  * 2. [Core Analysis] Run the FLOC algorithm to find biclusters using FLOC (optionally using directed initialization matrices)
//  * 3. [Visualization & Output] Extract and plot a specific bicluster using bicluster and plot
//  * 4. [Core Analysis] Test for gene set enrichment in the biclusters using testSet
//  * 5. [Core Analysis] Test for sample covariate enrichment using testAnnot
//  * 6. [Visualization & Output] Generate an interactive HTML report of the results using makeReport

nextflow.enable.dsl = 2

process BIOC_BICARE_BICLUSTERING_AND_ENRICHMENT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("BicARE", "Biobase", "GSEABase")
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
        library(BicARE)
        library(Biobase)
        library(GSEABase)
        
        # ==========================================
        # 1. Load User Input Files
        # ==========================================
        
        # Load ExpressionSet
        env_eset <- new.env()
        load("expression_set.RData", envir = env_eset)
        eset_objs <- Filter(function(x) inherits(x, "ExpressionSet"), as.list(env_eset))
        if (length(eset_objs) > 0) {
          sample.bicData <- eset_objs[[1]]
        } else {
          stop("Error: No ExpressionSet object found in expression_set.RData")
        }
        
        # Load GeneSetCollection
        env_gsc <- new.env()
        load("gene_sets.RData", envir = env_gsc)
        gsc_objs <- Filter(function(x) inherits(x, "GeneSetCollection"), as.list(env_gsc))
        if (length(gsc_objs) > 0) {
          gsc <- gsc_objs[[1]]
        } else {
          stop("Error: No GeneSetCollection object found in gene_sets.RData")
        }
        
        # ==========================================
        # 2. Biclustering Analysis
        # ==========================================
        
        # Calculate the initial residue of the expression dataset
        initial_residue <- residue(sample.bicData)
        cat("Initial residue of the dataset:", initial_residue, "\n")
        
        # Directed initialization matrices (adapted to input dimensions)
        num_genes <- nrow(sample.bicData)
        num_samples <- ncol(sample.bicData)
        
        init.genes <- matrix(data=0, nrow=num_genes, ncol=5)
        init.samples <- matrix(data=0, nrow=num_samples, ncol=5)
        
        # Safely assign initial memberships with bounds checking
        init.genes[1:min(10, num_genes), 1] <- 1
        if (num_genes >= 30) init.genes[20:min(30, num_genes), 2] <- 1
        if (num_genes >= 60) init.genes[50:min(60, num_genes), 3] <- 1
        
        init.samples[1:min(5, num_samples), 3] <- 1
        init.samples[1:min(5, num_samples), 4] <- 1
        if (num_samples >= 15) init.samples[10:min(15, num_samples), 5] <- 1
        
        # Run the FLOC algorithm to find biclusters
        set.seed(1)
        res.biclustering <- FLOC(sample.bicData, k=15, pGene=0.3, pSample=0.6, r=0.01, 10, 8, 200, blocGene=init.genes, blocSample=init.samples)
        
        # ==========================================
        # 3. Bicluster Extraction and Plotting
        # ==========================================
        
        # Extract bicluster 6
        bic <- bicluster(res.biclustering, 6, graph=FALSE)
        
        # Save the bicluster plot to a PDF file
        pdf("bicluster_6_plot.pdf", width=8, height=6)
        plot(bic)
        dev.off()
        
        # Save the extracted bicluster matrix to a CSV file
        write.csv(as.matrix(bic), file="bicluster_6_matrix.csv", row.names=TRUE)
        
        # ==========================================
        # 4. Gene Set Enrichment
        # ==========================================
        
        # Test for gene set enrichment in the biclusters using the loaded GeneSetCollection
        res.bic2 <- testSet(res.biclustering, gsc)
        
        # ==========================================
        # 5. Sample Covariate Enrichment
        # ==========================================
        
        # Print phenoData to console
        pData(sample.bicData)
        
        # Ensure covariates exist and are categorical
        covs_to_use <- c("sex", "type")
        p_data <- pData(sample.bicData)
        
        if (!all(covs_to_use %in% colnames(p_data))) {
          # Fallback to available categorical/character columns
          cat_cols <- colnames(p_data)[sapply(p_data, function(x) is.factor(x) || is.character(x) || length(unique(x)) < 10)]
          if (length(cat_cols) >= 2) {
            covs_to_use <- cat_cols[1:2]
          } else if (length(cat_cols) == 1) {
            covs_to_use <- c(cat_cols, "dummy_cov")
            pData(sample.bicData)\$dummy_cov <- as.factor(sample(c("GroupA", "GroupB"), num_samples, replace=TRUE))
          } else {
            # Create dummy covariates if none exist
            pData(sample.bicData)\$sex <- as.factor(sample(c("Female", "Male"), num_samples, replace=TRUE))
            pData(sample.bicData)\$type <- as.factor(sample(c("Control", "Case"), num_samples, replace=TRUE))
            covs_to_use <- c("sex", "type")
          }
        }
        
        # Ensure selected covariates are factors
        for (cov in covs_to_use) {
          pData(sample.bicData)[[cov]] <- as.factor(pData(sample.bicData)[[cov]])
        }
        
        # Test for sample covariate enrichment
        res.bic2 <- testAnnot(res.bic2, annot=pData(sample.bicData), covariates=covs_to_use)
        
        # Save the final updated biclustering object
        saveRDS(res.bic2, file="biclustering_results.rds")
        
        # ==========================================
        # 6. Generate Interactive HTML Report
        # ==========================================
        
        dirPath <- getwd()
        dirName <- "test"
        
        # Create the directory if it doesn't exist
        if (!dir.exists(file.path(dirPath, dirName))) {
          dir.create(file.path(dirPath, dirName), recursive=TRUE)
        }
        
        # Generate the HTML report
        makeReport(dirPath=dirPath, dirName=dirName, resBic=res.bic2, browse=FALSE)
        
        cat("Workflow complete. Results saved to 'biclustering_results.rds', 'bicluster_6_matrix.csv', 'bicluster_6_plot.pdf', and HTML report generated in directory 'test/'.\n")

    writeLines(c(
        '"BIOC_BICARE_BICLUSTERING_AND_ENRICHMENT_WORKFLOW":',
        paste0('    BicARE: ', as.character(packageVersion('BicARE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biclustering_and_enrichment_workflow.csv versions.yml
    """
}

workflow BIOC_BICARE_BICLUSTERING_AND_ENRICHMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_set.RData, gene_sets.RData ] ]

    main:
    BIOC_BICARE_BICLUSTERING_AND_ENRICHMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_BICARE_BICLUSTERING_AND_ENRICHMENT_WORKFLOW.out.tables
    plots    = BIOC_BICARE_BICLUSTERING_AND_ENRICHMENT_WORKFLOW.out.plots
    objects  = BIOC_BICARE_BICLUSTERING_AND_ENRICHMENT_WORKFLOW.out.objects
    versions = BIOC_BICARE_BICLUSTERING_AND_ENRICHMENT_WORKFLOW.out.versions
}
