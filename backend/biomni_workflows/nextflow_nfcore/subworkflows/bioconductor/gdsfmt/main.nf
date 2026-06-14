#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gdsfmt
// Provides a high-level R interface to CoreArray Genomic Data Structure (GDS) data files. GDS is porta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gdsfmt/inst/doc/gdsfmt.R
// Upstream  : none
// Downstream: bigmelon, GDSArray, RAIDS, SAIGEgds, SCArray
//
// Install: BiocManager::install("gdsfmt")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_GDSFMT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gdsfmt"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gdsfmt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gdsfmt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gdsfmt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("gdsfmt", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(gdsfmt)
    library(jsonlite)

    # --- Initialize Genomic Data Structure [] ---
    # Key functions: createfn.gds, add.gdsn, addfolder.gdsn, closefn.gds
    gfile <- createfn.gds("genomic_data.gds")
    add.gdsn(gfile, "sample.id", val=paste0("Sample_", 1:100))
    add.gdsn(gfile, "chromosome", val=rep(1:22, each=5))
    folder <- addfolder.gdsn(gfile, "genotypes")
    add.gdsn(folder, "data", val=matrix(1:1100, nrow=11))
    closefn.gds(gfile)

    # --- Write and Append Genomic Features [] ---
    # Key functions: openfn.gds, index.gdsn, write.gdsn, append.gdsn, closefn.gds
    gfile <- openfn.gds("genomic_data.gds", readonly=FALSE)
    node <- index.gdsn(gfile, "genotypes/data")
    write.gdsn(node, rep(0, 10), start=c(1, 1), count=c(1, 10))
    append.gdsn(node, 1101:1110)
    closefn.gds(gfile)

    # --- Compressed Genomic Data Storage [] ---
    # Key functions: createfn.gds, add.gdsn, append.gdsn, readmode.gdsn, closefn.gds
    gfile <- createfn.gds("compressed_data.gds")
    node <- add.gdsn(gfile, "intensity", storage="float",
        valdim=c(100, 0), compress="ZIP")
    for (i in 1:10) {
        append.gdsn(node, seq(0.1, 10, length.out=100))
    }
    readmode.gdsn(node)
    closefn.gds(gfile)

    # --- Retrieve and Subset Genomic Data [] ---
    # Key functions: openfn.gds, index.gdsn, read.gdsn, readex.gdsn, closefn.gds
    gfile <- openfn.gds("genomic_data.gds")
    node <- index.gdsn(gfile, "genotypes/data")
    sub_data <- read.gdsn(node, start=c(1, 1), count=c(5, 5))
    sel_list <- list(c(TRUE, FALSE, TRUE, FALSE, TRUE), c(TRUE, TRUE, FALSE))
    sub_ex <- readex.gdsn(node, sel_list)
    closefn.gds(gfile)

    # --- Apply Transformations and Transpose Data [] ---
    # Key functions: openfn.gds, index.gdsn, add.gdsn, apply.gdsn, closefn.gds
    gfile <- openfn.gds("genomic_data.gds", readonly=FALSE)
    node <- index.gdsn(gfile, "genotypes/data")
    trans_node <- add.gdsn(gfile, "genotypes/transposed",
        storage="int", valdim=c(100, 0))
    apply.gdsn(node, margin=1, FUN=c, as.is="gdsnode",
        target.node=trans_node)
    closefn.gds(gfile)


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
        write.csv(as.data.frame(.main), "${prefix}_gdsfmt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_gdsfmt_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_gdsfmt_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_GDSFMT:", paste0("    gdsfmt: ", as.character(packageVersion("gdsfmt")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdsfmt_results.csv
    touch ${prefix}_gdsfmt_output.rds
    echo "BIOC_GDSFMT:" > versions.yml
    echo "    gdsfmt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GDSFMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GDSFMT(ch_input)

    emit:
    results  = BIOC_GDSFMT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GDSFMT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GDSFMT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GDSFMT.out.versions  // channel: path(versions.yml)
}
