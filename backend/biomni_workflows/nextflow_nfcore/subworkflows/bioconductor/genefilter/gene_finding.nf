#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genefilter — gene_finding
// Find genes with expression profiles most similar to a set of target genes of interest.
// Input: sample.ExpressionSet
// Container: quay.io/biocontainers/bioconductor-genefilter:1.92.0--r45h9e4a190_0
// R packages: Biobase, genefilter
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, genefilter
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the indices of the target genes of interest
//  * 2. [Core Analysis] Run genefinder to identify the nearest neighbor genes using a specified distance metric and scaling method
//  * 3. [Core Analysis] Extract the indices and distances of the nearest genes
//  * 4. [Core Analysis] Retrieve the feature names of the identified neighbor genes

nextflow.enable.dsl = 2

process BIOC_GENEFILTER_GENE_FINDING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "genefilter")
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
        library("Biobase")
        library("genefilter")
        
        # 1. Read the user input ExpressionSet file from the working directory
        # The pipeline expects 'sample.ExpressionSet' to be an RDS file containing the ExpressionSet object.
        sample.ExpressionSet <- readRDS("sample.ExpressionSet")
        
        # 2. Define the indices of the target genes of interest
        # Ensure indices do not exceed the number of features in the ExpressionSet
        igenes <- c(300, 333, 355, 419)
        igenes <- igenes[igenes <= nrow(sample.ExpressionSet)]
        if (length(igenes) == 0) {
          igenes <- seq_len(min(4, nrow(sample.ExpressionSet)))
        }
        
        # 3. Run genefinder to identify the nearest neighbor genes using a specified distance metric and scaling method
        closeg <- genefinder(sample.ExpressionSet, igenes, 10, method="euc", scale="none")
        
        # 4. Extract the indices and distances of the nearest genes
        names(closeg)
        first_target <- names(closeg)[1]
        closeg[[first_target]]
        
        # 5. Retrieve the feature names of the identified neighbor genes
        Nms1 <- featureNames(sample.ExpressionSet)[closeg[[first_target]]\$indices]
        Nms1
        
        # 6. Save the meaningful results to output files
        # Save the raw list object
        saveRDS(closeg, "closeg_results.rds")
        
        # Save Nms1 feature names to a text file
        writeLines(Nms1, "Nms1_feature_names.txt")
        
        # Create a comprehensive data frame of all nearest neighbors for all target genes and save as CSV
        results_list <- lapply(names(closeg), function(target_gene) {
          indices <- closeg[[target_gene]]\$indices
          distances <- closeg[[target_gene]]\$dists
          neighbor_names <- featureNames(sample.ExpressionSet)[indices]
          
          data.frame(
            Target_Gene = target_gene,
            Rank = seq_along(indices),
            Neighbor_Index = indices,
            Neighbor_FeatureName = neighbor_names,
            Distance = distances,
            stringsAsFactors = FALSE
          )
        })
        
        results_df <- do.call(rbind, results_list)
        write.csv(results_df, "nearest_genes_profiles.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GENEFILTER_GENE_FINDING":',
        paste0('    genefilter: ', as.character(packageVersion('genefilter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_finding.csv versions.yml
    """
}

workflow BIOC_GENEFILTER_GENE_FINDING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.ExpressionSet ] ]

    main:
    BIOC_GENEFILTER_GENE_FINDING(ch_input)

    emit:
    tables   = BIOC_GENEFILTER_GENE_FINDING.out.tables
    plots    = BIOC_GENEFILTER_GENE_FINDING.out.plots
    objects  = BIOC_GENEFILTER_GENE_FINDING.out.objects
    versions = BIOC_GENEFILTER_GENE_FINDING.out.versions
}
