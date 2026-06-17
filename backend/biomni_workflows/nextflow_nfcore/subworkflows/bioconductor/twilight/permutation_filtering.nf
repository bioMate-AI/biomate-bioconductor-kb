#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: twilight — permutation_filtering
// Filter for a set of permutations whose p-value distributions fit a uniform distribution to improve significance analysis.
// Input: expression_matrix.csv, phenotype_labels.csv
// Container: quay.io/biocontainers/bioconductor-twilight:1.86.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: twilight
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run permutation filtering using twilight.filtering to obtain a matrix of filtered permutations
//  * 2. [Core Analysis] Remove the original labeling from the first row of the filtered permutation matrix
//  * 3. [Core Analysis] Compute p-values using twilight.pval with the filtered permutation matrix passed to yperm
//  * 4. [Visualization & Output] Plot a histogram of the resulting p-values to verify uniformity

nextflow.enable.dsl = 2

process BIOC_TWILIGHT_PERMUTATION_FILTERING {
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
    .bm_deps <- c("twilight")
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
    library(twilight)
    
    # Read user input files
    # expression_matrix.csv: normalized gene expression matrix (genes as rows, samples as columns)
    golubNorm <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # phenotype_labels.csv: binary condition labels (numeric and dichotomous, e.g., 1 and 2)
    id <- as.numeric(read.csv("phenotype_labels.csv")[, 1])
    
    # 1. Run permutation filtering using twilight.filtering to obtain a matrix of filtered permutations
    yperm <- twilight.filtering(golubNorm,id,method="fc",num.perm=50,num.take=10)
    
    # 2. Remove the original labeling from the first row of the filtered permutation matrix
    yperm <- yperm[-1,]
    
    # 3. Compute p-values using twilight.pval with the filtered permutation matrix passed to yperm
    b <- twilight.pval(golubNorm,yperm[1,],method="fc",yperm=yperm)
    
    # 4. Plot a histogram of the resulting p-values to verify uniformity and save to PDF
    pdf("pvalue_histogram.pdf", width = 6, height = 4.5)
    hist(b\$result\$pvalue,col="gray",br=20)
    dev.off()
    
    # Save meaningful results
    # Save the p-value and q-value table
    write.csv(b\$result, "twilight_pval_results.csv", row.names = TRUE)
    
    # Save the filtered permutation matrix
    write.csv(yperm, "filtered_permutations.csv", row.names = FALSE)
    
    # Save the complete twilight object
    saveRDS(b, "twilight_pval_object.rds")

    writeLines(c(
        '"BIOC_TWILIGHT_PERMUTATION_FILTERING":',
        paste0('    twilight: ', as.character(packageVersion('twilight')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_permutation_filtering.csv versions.yml
    """
}

workflow BIOC_TWILIGHT_PERMUTATION_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_labels.csv ] ]

    main:
    BIOC_TWILIGHT_PERMUTATION_FILTERING(ch_input)

    emit:
    tables   = BIOC_TWILIGHT_PERMUTATION_FILTERING.out.tables
    plots    = BIOC_TWILIGHT_PERMUTATION_FILTERING.out.plots
    objects  = BIOC_TWILIGHT_PERMUTATION_FILTERING.out.objects
    versions = BIOC_TWILIGHT_PERMUTATION_FILTERING.out.versions
}
