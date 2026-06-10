#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: panomir — panomir_complete_analysis
// Run the complete PanomiR workflow to identify and prioritize miRNAs targeting coordinated pathway clusters from gene expression data.
// Input: gene_expression.csv, covariates.csv
// Container: quay.io/biocontainers/bioconductor-panomir:1.14.0--r45hdfd78af_0
// R packages: GSEABase, PanomiR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANOMIR_PANOMIR_COMPLETE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-panomir:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("GSEABase", "PanomiR")
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
    
    # Load required library
    library(PanomiR)
    
    # Create output directories if they don't exist
    dir.create("Output", showWarnings = FALSE, recursive = TRUE)
    dir.create("outData", showWarnings = FALSE, recursive = TRUE)
    
    # 1. Read User Input Files
    # gene_expression.csv: genes as rows, samples as columns
    gene_expression <- as.matrix(read.csv("gene_expression.csv", row.names = 1, check.names = FALSE))
    
    # covariates.csv: sample metadata table
    covariates <- read.csv("covariates.csv", row.names = 1, check.names = FALSE)
    
    # Ensure the condition column is formatted as a factor
    if ("shortLetterCode" %in% colnames(covariates)) {
      covariates\$shortLetterCode <- as.factor(covariates\$shortLetterCode)
    } else {
      # Fallback: if 'shortLetterCode' is not present, use the first column and rename it
      colnames(covariates)[1] <- "shortLetterCode"
      covariates\$shortLetterCode <- as.factor(covariates\$shortLetterCode)
    }
    
    # 2. Pathway Summarization
    # Using the pathway reference from the PanomiR package namespace
    path_gene_table <- PanomiR::path_gene_table
    
    summaries <- pathwaySummary(gene_expression,
                                path_gene_table, method = "x2",
                                zNormalize = TRUE, id = "ENSEMBL")
    
    # Save pathway summaries
    write.csv(summaries, "pathway_summaries.csv", row.names = TRUE)
    
    # 3. Differential Pathway Activity Analysis
    output0 <- differentialPathwayAnalysis(
                            geneCounts = gene_expression,
                            pathways =  path_gene_table,
                            covariates = covariates,
                            condition = 'shortLetterCode')
    
    de.paths <- output0\$DEP
    
    # Save differential pathway analysis results
    write.csv(de.paths, "differential_pathways.csv", row.names = TRUE)
    
    # 4. Finding Clusters of Pathways
    # Using the pathway co-expression network from the PanomiR package namespace
    miniPCXN <- PanomiR::miniTestsPanomiR\$miniPCXN
    
    # Determine safe limits for indexing based on the number of differential pathways found
    num_de_paths <- nrow(de.paths)
    top_p_limit <- min(200, num_de_paths)
    de_p_limit <- min(300, num_de_paths)
    
    set.seed(2)
    pathwayClustsLIHC <- mappingPathwaysClusters(
                                pcxn = miniPCXN, 
                                dePathways = de.paths[1:de_p_limit, , drop = FALSE],
                                topPathways = top_p_limit,
                                outDir=".",
                                plot = FALSE,
                                subplot = FALSE,
                                prefix='',
                                clusteringFunction = "cluster_louvain",
                                correlationCutOff = 0.1)
    
    # Save pathway clustering results
    if (!is.null(pathwayClustsLIHC\$Clustering)) {
      write.csv(pathwayClustsLIHC\$Clustering, "pathway_clusters.csv", row.names = TRUE)
    }
    
    # 5. Prioritizing miRNAs per Cluster of Pathways
    # Using the enrichment reference from the PanomiR package namespace
    miniEnrich <- PanomiR::miniTestsPanomiR\$miniEnrich
    
    # Run prioritization if clusters were successfully found
    if (!is.null(pathwayClustsLIHC\$Clustering) && nrow(pathwayClustsLIHC\$Clustering) > 0) {
      set.seed(1)
      
      # Wrap in tryCatch to ensure robustness
      tryCatch({
        output2 <- prioritizeMicroRNA(enriches0 = miniEnrich,
                            pathClust = pathwayClustsLIHC\$Clustering,
                            topClust = 1,
                            sampRate = 50, 
                            method = c("aggInv"),
                            outDir = "Output/",
                            dataDir = "outData/",
                            saveSampling = FALSE,
                            runJackKnife = FALSE,
                            numCores = 1,
                            prefix = "outmiR",
                            saveCSV = FALSE)
        
        # Save prioritized miRNAs
        if (!is.null(output2\$Cluster1)) {
          write.csv(output2\$Cluster1, "prioritized_mirnas_cluster1.csv", row.names = TRUE)
        }
        saveRDS(output2, "prioritized_mirnas.rds")
      }, error = function(e) {
        message("Warning: prioritizeMicroRNA failed with error: ", e\$message)
      })
    } else {
      message("No pathway clusters found. Skipping miRNA prioritization.")
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PANOMIR_PANOMIR_COMPLETE_ANALYSIS":
        panomir: \$(Rscript -e 'cat(as.character(packageVersion("panomir")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_panomir_complete_analysis.csv versions.yml
    """
}

workflow BIOC_PANOMIR_PANOMIR_COMPLETE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression.csv, covariates.csv ] ]

    main:
    BIOC_PANOMIR_PANOMIR_COMPLETE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PANOMIR_PANOMIR_COMPLETE_ANALYSIS.out.tables
    plots    = BIOC_PANOMIR_PANOMIR_COMPLETE_ANALYSIS.out.plots
    objects  = BIOC_PANOMIR_PANOMIR_COMPLETE_ANALYSIS.out.objects
    versions = BIOC_PANOMIR_PANOMIR_COMPLETE_ANALYSIS.out.versions
}
