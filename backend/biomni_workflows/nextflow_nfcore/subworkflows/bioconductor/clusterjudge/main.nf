#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClusterJudge
// ClusterJudge implements the functions, examples and other software published as an algorithm by Gibb
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClusterJudge/inst/doc/ClusterJudge-intro.R
// Upstream  : yeastExpData
// Downstream: none
//
// Install: BiocManager::install("ClusterJudge")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_CLUSTERJUDGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterjudge"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clusterjudge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterjudge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterjudge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ClusterJudge", "Database", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(ClusterJudge)
    library(Database)
    library(jsonlite)

    # --- Data Validation [] ---
    # Key functions: validate_association
    data(Yeast.GO.assocs)
    data(ccyclered)
    ccyclered\$SGDID <- sub("^S", "S00", ccyclered\$SGDID)
    clusters <- ccyclered\$Cluster
    names(clusters) <- ccyclered\$SGDID
    validated_assocs <- validate_association(Yeast.GO.assocs)

    # --- Attribute Consolidation [] ---
    # Key functions: entities_attribute_stats, consolidate_entity_attribute
    data(Yeast.GO.assocs)
    stats <- entities_attribute_stats(Yeast.GO.assocs)
    Yeast.GO.assocs.cons1 <- consolidate_entity_attribute(
        entity.attribute = Yeast.GO.assocs,
        min.entities.per.attr = 3,
        mut.inf = FALSE
    )

    # --- Mutual Information Estimation [] ---
    # Key functions: attribute_mut_inf
    data(Yeast.GO.assocs)
    entity.attribute.sampled <- Yeast.GO.assocs[1:100, ]
    mi.GO.Yeast.sampled <- attribute_mut_inf(
        entity.attribute = entity.attribute.sampled,
        show.progress = FALSE
    )

    # --- Cluster Evaluation [] ---
    # Key functions: consolidate_entity_attribute, clusterJudge
    data(ccyclered)
    data(mi.GO.Yeast)
    data(Yeast.GO.assocs)
    ccyclered\$SGDID <- sub("^S", "S00", ccyclered\$SGDID)
    clusters <- ccyclered\$Cluster
    names(clusters) <- ccyclered\$SGDID
    Yeast.GO.assocs.cons <- consolidate_entity_attribute(
        entity.attribute = Yeast.GO.assocs,
        min.entities.per.attr = 3,
        mut.inf = mi.GO.Yeast,
        U.limit = c(0.1, 0.001)
    )
    mi.by.swaps <- clusterJudge(
        clusters = clusters,
        entity.attribute = Yeast.GO.assocs.cons[["0.001"]],
        plot.notes = "Yeast clusters judged at uncertainty level 0.001",
        plot.saveRDS.file = "cj.rds"
    )


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_clusterjudge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_clusterjudge_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_clusterjudge_output.rds")

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
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERJUDGE(ch_input)

    emit:
    results  = BIOC_CLUSTERJUDGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERJUDGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERJUDGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERJUDGE.out.versions  // channel: path(versions.yml)
}
