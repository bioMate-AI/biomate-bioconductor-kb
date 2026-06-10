#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cmapR
// The Connectivity Map (CMap) is a massive resource of perturbational gene expression profiles built b
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/cmapR/inst/doc/tutorial.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cmapR")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_CMAPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cmapr"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cmapr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cmapr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cmapr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("cmapR", "jsonlite")
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
    library(cmapR)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: 20, 1
    ## Bioconductor version 3.20 (BiocManager 1.30.25), R 4.4.1 (2024-06-14)
    # --- Code Block 2 [] ---
    # Key functions: package, version
    ## Warning: package(s) not installed when version(s) same as or greater than current; use
    ##   `force = TRUE` to re-install: 'cmapR'
    # --- Code Block 3 [] ---
    # Key functions: attr, proteasome, 1, chr
    ## Formal class 'GCT' [package "cmapR"] with 7 slots
    ##   ..@ mat    : num [1:978, 1:272] -0.524 -0.372 0.578 0.569 1.48 ...
    ##   .. ..- attr(*, "dimnames")=List of 2
    ##   .. .. ..\$ : chr [1:978] "200814_at" "222103_at" "201453_x_at" "204131_s_at" ...
    ##   .. .. ..\$ : chr [1:272] "CPC006_A549_6H:BRD-U88459701-000-01-8:10" "CPC020_A375_6H:BRD-A82307304-001-01-8:10" "CPC020_HT29_6H:BRD-A82307304-001-01-8:10" "CPC020_PC3_24H:BRD-A82307304-001-01-8:10" ...
    # --- Code Block 4 [] ---
    # Key functions: mat, meta, ids
    # access the data matrix
    m <- mat(ds)
    # access the row and column metadata
    rdesc <- meta(ds, dimension = "row")
    cdesc <- meta(ds, dimension = "column")
    # --- Code Block 5 [] ---
    # Key functions: mat, meta, frame, sample
    # update the matrix data to set some values to zero
    # note that the updated matrix must be the of the same dimensions as
    # the current matrix
    m[1:10, 1:10] <- 0
    mat(ds) <- m
    # --- Code Block 6 [] ---
    # Key functions: attr, chr
    ## Formal class 'GCT' [package "cmapR"] with 7 slots
    ##   ..@ mat    : num [1:978, 1:272] 0 0 0 0 0 0 0 0 0 0 ...
    ##   .. ..- attr(*, "dimnames")=List of 2
    ##   .. .. ..\$ : chr [1:978] "200814_at" "222103_at" "201453_x_at" "204131_s_at" ...
    ##   .. .. ..\$ : chr [1:272] "CPC006_A549_6H:BRD-U88459701-000-01-8:10" "CPC020_A375_6H:BRD-A82307304-001-01-8:10" "CPC020_HT29_6H:BRD-A82307304-001-01-8:10" "CPC020_PC3_24H:BRD-A82307304-001-01-8:10" ...
    # --- Code Block 7 [] ---
    # Key functions: parse_gctx
    # create a variable to store the path to the GCTX file
    # here we'll use a file that's internal to the cmapR package, but
    # in practice this could be any valid path to a GCT or GCTX file
    ds_path <- system.file("extdata", "modzs_n25x50.gctx", package="cmapR")
    my_ds <- parse_gctx(ds_path)
    # --- Code Block 9 [] ---
    # Key functions: attr, proteasome, 1, chr
    ## Formal class 'GCT' [package "cmapR"] with 7 slots
    ##   ..@ mat    : num [1:50, 1:25] -1.145 -1.165 0.437 0.139 -0.673 ...
    ##   .. ..- attr(*, "dimnames")=List of 2
    ##   .. .. ..\$ : chr [1:50] "200814_at" "222103_at" "201453_x_at" "204131_s_at" ...
    ##   .. .. ..\$ : chr [1:25] "CPC004_PC3_24H:BRD-A51714012-001-03-1:10" "BRAF001_HEK293T_24H:BRD-U73308409-000-01-9:0.625" "CPC006_HT29_24H:BRD-U88459701-000-01-8:10" "CVD001_HEPG2_24H:BRD-U88459701-000-01-8:10" ...
    # --- Code Block 10 [] ---
    # Key functions: indices, parse_gctx
    # read just the first 10 columns, using numeric indices
    (my_ds_10_columns <- parse_gctx(ds_path, cid=1:10))
    # --- Code Block 12 [] ---
    # Key functions: attr, proteasome, 1, chr
    ## Formal class 'GCT' [package "cmapR"] with 7 slots
    ##   ..@ mat    : num [1:50, 1:10] -1.145 -1.165 0.437 0.139 -0.673 ...
    ##   .. ..- attr(*, "dimnames")=List of 2
    ##   .. .. ..\$ : chr [1:50] "200814_at" "222103_at" "201453_x_at" "204131_s_at" ...
    ##   .. .. ..\$ : chr [1:10] "CPC004_PC3_24H:BRD-A51714012-001-03-1:10" "BRAF001_HEK293T_24H:BRD-U73308409-000-01-9:0.625" "CPC006_HT29_24H:BRD-U88459701-000-01-8:10" "CVD001_HEPG2_24H:BRD-U88459701-000-01-8:10" ...
    # --- Code Block 13 [] ---
    # Key functions: read_gctx_meta, parse_gctx
    # read the column metadata
    col_meta <- read_gctx_meta(ds_path, dim="col")
    # figure out which signatures correspond to vorinostat by searching the 'pert_iname' column
    idx <- which(col_meta\$pert_iname=="vemurafenib")
    # read only those columns from the GCTX file by using the 'cid' parameter
    # --- Code Block 15 [] ---
    # Key functions: parse_gctx
    # get a vector of character ids, using the id column in col_meta
    col_ids <- col_meta\$id[idx]
    vemurafenib_ds2 <- parse_gctx(ds_path, cid=col_ids)

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
        write.csv(as.data.frame(.main), "${prefix}_cmapr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_cmapr_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_cmapr_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_CMAPR:", paste0("    cmapr: ", as.character(packageVersion("cmapR")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cmapr_results.csv
    touch ${prefix}_cmapr_output.rds
    echo "BIOC_CMAPR:" > versions.yml
    echo "    cmapr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CMAPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CMAPR(ch_input)

    emit:
    results  = BIOC_CMAPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CMAPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CMAPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CMAPR.out.versions  // channel: path(versions.yml)
}
