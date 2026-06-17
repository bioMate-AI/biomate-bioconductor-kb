#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClusterJudge
// Judge the quality of a clustering against an external system of
// entity attributes (e.g. gene clusters vs GO annotations) using the
// total mutual information between the clustering and the attributes.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClusterJudge/inst/doc/ClusterJudge-intro.R
//
// Input: clusters.csv, associations.csv
//   clusters.csv: two columns (entity, cluster); associations.csv: two columns (entity, attribute)
// R packages: ClusterJudge
// Document-derived real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2


process BIOC_CLUSTERJUDGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterjudge"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(clusters_csv), path(associations_csv)

    output:
    tuple val(meta), path("${meta.id}_clusterjudge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterjudge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterjudge_plot.pdf"),     emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ClusterJudge")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(ClusterJudge)

    # --- Read user inputs ---
    # clusters.csv: two columns (entity, cluster) -> ClusterJudge needs a named
    # integer/character vector entity -> clusterID with no ambiguity and no NA.
    clus_df <- read.csv("${clusters_csv}", stringsAsFactors = FALSE)
    stopifnot(ncol(clus_df) >= 2)
    clus_df <- clus_df[!is.na(clus_df[[1]]) & !is.na(clus_df[[2]]), ]
    clus_df <- clus_df[!duplicated(clus_df[[1]]), ]            # one cluster per entity
    clusters <- clus_df[[2]]
    names(clusters) <- as.character(clus_df[[1]])

    # associations.csv: two columns (entity, attribute)
    assoc <- read.csv("${associations_csv}", stringsAsFactors = FALSE)
    stopifnot(ncol(assoc) >= 2)
    assoc <- assoc[, 1:2]
    colnames(assoc) <- c("entity", "attribute")
    assoc <- unique(assoc[!is.na(assoc[[1]]) & !is.na(assoc[[2]]), ])

    # Restrict associations to entities that are actually clustered
    assoc <- assoc[assoc[["entity"]] %in% names(clusters), ]

    # --- Validate associations ---
    validated <- validate_association(assoc)

    # --- Distribution of entities per attribute ---
    stats <- entities_attribute_stats(assoc)

    # --- Consolidate: drop attributes assigned to too few entities ---
    assoc.cons <- consolidate_entity_attribute(
        entity.attribute = assoc,
        min.entities.per.attr = 2,
        mut.inf = FALSE
    )

    # --- Mutual information among attributes (computed from THIS data) ---
    mi <- attribute_mut_inf(entity.attribute = assoc.cons, show.progress = FALSE)

    # --- Judge the clustering vs the entity-attribute associations ---
    # clusterJudge writes a saved plot object; render it to PDF as well.
    mi.by.swaps <- clusterJudge(
        clusters = clusters,
        entity.attribute = assoc.cons,
        plot.notes = "Clustering judged against entity-attribute associations",
        plot.saveRDS.file = "cj.rds"
    )

    if (file.exists("cj.rds")) {
        p <- readRDS("cj.rds")
        pdf("${prefix}_clusterjudge_plot.pdf"); print(plot(p)); dev.off()
    }

    # --- Save results table: total mutual information per number of swaps ---
    res_df <- data.frame(
        n_swaps = as.numeric(names(mi.by.swaps)),
        total_mutual_information = as.numeric(mi.by.swaps)
    )
    res_df <- res_df[order(res_df\$n_swaps), ]
    write.csv(res_df, "${prefix}_clusterjudge_results.csv", row.names = FALSE)

    saveRDS(list(clusters = clusters,
                 associations = assoc,
                 consolidated = assoc.cons,
                 mutual_information = mi,
                 mi_by_swaps = mi.by.swaps),
            "${prefix}_clusterjudge_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERJUDGE:", paste0("    clusterjudge: ", as.character(packageVersion("ClusterJudge")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clusterjudge_results.csv
    touch ${prefix}_clusterjudge_output.rds
    echo "BIOC_CLUSTERJUDGE:" > versions.yml
    echo "    clusterjudge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERJUDGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(clusters_csv), path(associations_csv) ]

    main:
    BIOC_CLUSTERJUDGE(ch_input)

    emit:
    results  = BIOC_CLUSTERJUDGE.out.results
    rds      = BIOC_CLUSTERJUDGE.out.rds
    plots    = BIOC_CLUSTERJUDGE.out.plots
    versions = BIOC_CLUSTERJUDGE.out.versions
}
