#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plyinteractions
// Operate on `GInteractions` objects as tabular data using `dplyr`-like verbs. The functions and metho
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plyinteractions/inst/doc/process_pairs.R
// Upstream  : Biostrings, GenomicRanges, plyranges, sessioninfo, tidyverse
// Downstream: none
//
// Install: BiocManager::install("plyinteractions")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_PLYINTERACTIONS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plyinteractions"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plyinteractions_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plyinteractions_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plyinteractions_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DNAStringSet", "HiContactsData", "Biostrings", "GenomicRanges", "jsonlite", "plyinteractions", "plyranges", "sessioninfo", "tidyverse")
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
    library(plyinteractions)
    library(Biostrings)
    library(HiContactsData)
    library(jsonlite)

    # --- Import Genomic Interactions [] ---
    # Key functions: as_ginteractions
    pairs_df <- data.frame(
        ID = 1:100,
        seqnames1 = "chr1", start1 = seq(1, 1000, by = 10),
        seqnames2 = "chr1", start2 = seq(5, 1004, by = 10),
        strand1 = "+", strand2 = "-"
    )
    pairs <- as_ginteractions(
        pairs_df, end1 = start1, end2 = start2, 
        keep.extra.columns = TRUE
    )

    # --- Annotate Interactions [] ---
    # Key functions: annotate, mutate
    fragments <- GenomicRanges::GRanges(
        seqnames = "chr1",
        ranges = IRanges::IRanges(start = seq(1, 1000, by = 100), width = 99),
        binID = 1:10
    )
    annotated_pairs <- pairs |> 
        plyinteractions::annotate(fragments, by = "binID") |> 
        mutate(
            n_fragments = binID.2 - binID.1, 
            group = paste0(strand1, strand2)
        )

    # --- Filter Interactions [] ---
    # Key functions: filter, mutate
    filtered_pairs <- annotated_pairs |>
        mutate(type = case_when(
            group %in% c('--', '++') & n_fragments < 5 ~ "excluded",
            group == '+-' & n_fragments < 5 ~ "uncut",
            .default = "kept"
        )) |>
        filter(type == "kept")

    # --- Calculate Interaction Frequency [] ---
    # Key functions: mutate, group_by
    dat <- filtered_pairs |> 
        mutate(s = abs(end2 - start1)) |> 
        group_by(s) |> 
        count(name = "n") |>
        as_tibble() |> 
        mutate(Ps = n / sum(n))


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
        write.csv(as.data.frame(.main), "${prefix}_plyinteractions_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_plyinteractions_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_plyinteractions_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLYINTERACTIONS:", paste0("    plyinteractions: ", as.character(packageVersion("plyinteractions")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plyinteractions_results.csv
    touch ${prefix}_plyinteractions_output.rds
    echo "BIOC_PLYINTERACTIONS:" > versions.yml
    echo "    plyinteractions: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLYINTERACTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLYINTERACTIONS(ch_input)

    emit:
    results  = BIOC_PLYINTERACTIONS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLYINTERACTIONS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLYINTERACTIONS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLYINTERACTIONS.out.versions  // channel: path(versions.yml)
}
