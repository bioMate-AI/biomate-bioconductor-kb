#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowyourcg — feature_aggregation_and_annotation
// Aggregate CpG-level beta values into database-level summary statistics (e.g., mean) for downstream modeling, or annotate an arbitrary probe set.
// Input: betas, query
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: SummarizedExperiment, knowYourCG, sesameData, wheatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0"

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
    .bm_deps <- c("SummarizedExperiment", "knowYourCG", "sesameData", "wheatmap")
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
    library(knowYourCG)
    library(sesameData)
    library(SummarizedExperiment)
    
    # -------------------------------------------------------------------------
    # 1. Read User Input Files
    # -------------------------------------------------------------------------
    
    # Read betas matrix
    if (file.exists("betas.rds")) {
      betas <- readRDS("betas.rds")
    } else if (file.exists("betas.csv")) {
      betas <- as.matrix(read.csv("betas.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("betas.tsv")) {
      betas <- as.matrix(read.delim("betas.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: betas file (betas.rds, betas.csv, or betas.tsv) not found in the working directory.")
    }
    
    # Ensure betas is a numeric matrix
    if (!is.matrix(betas)) {
      betas <- as.matrix(betas)
    }
    storage.mode(betas) <- "numeric"
    
    # Read query probe IDs
    if (file.exists("query.rds")) {
      query <- readRDS("query.rds")
    } else if (file.exists("query.txt")) {
      query <- readLines("query.txt")
    } else if (file.exists("query.csv")) {
      query_df <- read.csv("query.csv", header = FALSE)
      query <- as.character(query_df[[1]])
    } else {
      stop("Error: query file (query.rds, query.txt, or query.csv) not found in the working directory.")
    }
    
    # Ensure query is a character vector
    query <- as.character(query)
    
    # -------------------------------------------------------------------------
    # 2. Feature Aggregation (dbStats)
    # -------------------------------------------------------------------------
    # Calculate summary statistics (e.g., mean) across database sets
    stats <- dbStats(betas, 'MM285.chromHMM')
    
    # Save the aggregated statistics
    write.csv(stats, "db_stats.csv", row.names = TRUE)
    saveRDS(stats, "db_stats.rds")
    
    # -------------------------------------------------------------------------
    # 3. Feature Annotation (annoProbes)
    # -------------------------------------------------------------------------
    # Annotate the arbitrary probe set
    anno <- annoProbes(query, "designGroup", silent = TRUE)
    
    # Save the annotations
    anno_df <- data.frame(Probe_ID = names(anno), Annotation = as.character(anno), row.names = NULL)
    write.csv(anno_df, "probe_annotations.csv", row.names = FALSE)
    saveRDS(anno, "probe_annotations.rds")
    
    # -------------------------------------------------------------------------
    # 4. Visualization (Optional Heatmap of dbStats)
    # -------------------------------------------------------------------------
    pdf("db_stats_heatmap.pdf", width = 10, height = 8)
    tryCatch({
      library(wheatmap)
      WHeatmap(both.cluster(stats)\$mat, xticklabels = TRUE, cmp = CMPar(stop.points = c("blue", "yellow")))
    }, error = function(e) {
      # Fallback to base R heatmap if wheatmap is not fully configured or fails
      heatmap(as.matrix(stats), Colv = NA, scale = "none", margins = c(10, 5))
    })
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION":
        knowyourcg: \$(Rscript -e 'cat(as.character(packageVersion("knowyourcg")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_aggregation_and_annotation.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ betas, query ] ]

    main:
    BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION.out.tables
    plots    = BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION.out.plots
    objects  = BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION.out.objects
    versions = BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION.out.versions
}
