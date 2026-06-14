#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathifier — pathway_deregulation_analysis
// Quantify pathway deregulation scores for tumor samples using expression data and pathway gene sets.
// Input: expression_matrix.csv, gene_identifiers.txt, pathway_database.rds, sample_annotations.csv
// Container: quay.io/biocontainers/bioconductor-pathifier:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pathifier
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the pathifier library and input datasets
//  * 2. [Core Analysis] Calculate pathway deregulation scores using quantify_pathways_deregulation
//  * 3. [Core Analysis] Compare scores between normal and tumor samples using boxplots
//  * 4. [Core Analysis] Identify highly deregulated samples by filtering based on score thresholds

nextflow.enable.dsl = 2

process BIOC_PATHIFIER_PATHWAY_DEREGULATION_ANALYSIS {
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
    .bm_deps <- c("pathifier")
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
        
    # 1. Load the pathifier library and input datasets
    library(pathifier)
    
    # Read expression matrix (genes as rows, samples as columns)
    expression_matrix <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Read gene identifiers corresponding to the matrix rows
    gene_identifiers <- as.character(readLines("gene_identifiers.txt"))
    
    # Read pathway database (list of pathways with constituent gene identifiers)
    pathway_list <- readRDS("pathway_database.rds")
    if (is.null(names(pathway_list))) {
      names(pathway_list) <- paste0("Pathway_", seq_along(pathway_list))
    }
    
    # Read sample annotations (metadata indicating which samples are normal controls)
    annotations <- read.csv("sample_annotations.csv", stringsAsFactors = FALSE)
    
    # Construct sheffer and kegg objects to match the documented code structure
    sheffer <- list()
    sheffer\$data <- expression_matrix
    sheffer\$allgenes <- gene_identifiers
    sheffer\$samples <- colnames(expression_matrix)
    
    # Match annotations to expression matrix columns to get normals logical vector
    if (!all(c("sample_id", "is_normal") %in% colnames(annotations))) {
      stop("sample_annotations.csv must contain 'sample_id' and 'is_normal' columns.")
    }
    matched_idx <- match(sheffer\$samples, annotations\$sample_id)
    sheffer\$normals <- as.logical(annotations\$is_normal[matched_idx])
    
    # Set min_exp and min_std from annotations if available, otherwise use defaults
    sheffer\$minexp <- if ("minexp" %in% colnames(annotations)) annotations\$minexp[1] else 4
    sheffer\$minstd <- if ("minstd" %in% colnames(annotations)) annotations\$minstd[1] else 0.2254005
    
    kegg <- list()
    kegg\$gs <- pathway_list
    kegg\$pathwaynames <- names(pathway_list)
    
    # 2. Calculate pathway deregulation scores using quantify_pathways_deregulation
    PDS<-quantify_pathways_deregulation(sheffer\$data, sheffer\$allgenes,
      kegg\$gs, kegg\$pathwaynames, sheffer\$normals, attempts = 100,
      min_exp=sheffer\$minexp, min_std=sheffer\$minstd)
    
    # 3. Compare scores between normal and tumor samples using boxplots
    pdf("pathway_deregulation_plots.pdf")
    first_pathway <- names(PDS\$scores)[1]
    x<-list()
    x\$normals<-PDS\$scores[[first_pathway]][sheffer\$normals]
    x\$tumors<-PDS\$scores[[first_pathway]][!sheffer\$normals]
    boxplot(x)
    boxplot(x,ylab="score")
    dev.off()
    
    # 4. Identify highly deregulated samples by filtering based on score thresholds
    second_pathway <- if (length(PDS\$scores) >= 2) names(PDS\$scores)[2] else names(PDS\$scores)[1]
    deregulated_samples <- as.character(sheffer\$samples[PDS\$scores[[second_pathway]]>0.8])
    
    # Save meaningful results to output files
    saveRDS(PDS, "pathway_deregulation_scores.rds")
    
    # Convert scores list to a data frame and save as CSV
    scores_df <- do.call(rbind, PDS\$scores)
    write.csv(scores_df, "pathway_scores.csv", row.names = TRUE)
    
    # Save highly deregulated samples to a text file
    writeLines(deregulated_samples, "highly_deregulated_samples.txt")

    writeLines(c(
        '"BIOC_PATHIFIER_PATHWAY_DEREGULATION_ANALYSIS":',
        paste0('    pathifier: ', as.character(packageVersion('pathifier')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_deregulation_analysis.csv versions.yml
    """
}

workflow BIOC_PATHIFIER_PATHWAY_DEREGULATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, gene_identifiers.txt, pathway_database.rds, sample_annotations.csv ] ]

    main:
    BIOC_PATHIFIER_PATHWAY_DEREGULATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PATHIFIER_PATHWAY_DEREGULATION_ANALYSIS.out.tables
    plots    = BIOC_PATHIFIER_PATHWAY_DEREGULATION_ANALYSIS.out.plots
    objects  = BIOC_PATHIFIER_PATHWAY_DEREGULATION_ANALYSIS.out.objects
    versions = BIOC_PATHIFIER_PATHWAY_DEREGULATION_ANALYSIS.out.versions
}
