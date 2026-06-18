#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TnT
// A R interface to the TnT javascript library (https://github.com/ tntvis) to provide interactive and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TnT/inst/doc/introduction.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("TnT")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TNT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tnt"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tnt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tnt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tnt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("TnT", "BlockTrack", "GenomicRanges", "TnTBoard", "TnTGenome", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(TnT)
    library(BlockTrack)
    library(GenomicRanges)
    library(TnTBoard)
    library(TnTGenome)
    library(jsonlite)

    # --- Track Creation [Track Creation] ---
    # Key functions: BlockTrack
    gr <- GenomicRanges::GRanges("chr7",
        ranges = IRanges::IRanges(
            start = c(26549019L, 26564119L, 26585667L, 26591772L),
            end =   c(26550183L, 26564500L, 26586158L, 26593309L)
        ),
        ID = 1:4,
        Name = paste("My Range", 1:4)
    )
    btrack <- TnT::BlockTrack(gr)

    # --- Track Customization [Track Customization] ---
    # Key functions: trackSpec, trackData
    btrack2 <- btrack
    TnT::trackSpec(btrack2, "background") <- "blanchedalmond"
    TnT::trackSpec(btrack2, "label")      <- "My Ranges"
    TnT::trackSpec(btrack2, "height")     <- 50
    btrack2\$color <- "darkseagreen4"
    TnT::trackData(btrack2) <- GenomicRanges::shift(
        TnT::trackData(btrack2),
        10000
    )

    # --- Interactive Tooltip Configuration [Interactive Tooltip Configuration] ---
    # Key functions: tooltip, trackData
    tooltip_df <- as.data.frame(TnT::trackData(btrack2))
    TnT::tooltip(btrack2) <- cbind(
        TnT::tooltip(btrack2),
        tooltip_df
    )

    # --- Genome Board Visualization [Genome Board Visualization] ---
    # Key functions: PinTrack, TnTBoard, TnTGenome
    pintrack <- TnT::PinTrack(
        GenomicRanges::GRanges("chr7",
            IRanges::IRanges(start = c(26350000, 26450000), width = 1)
        ),
        value = c(1, 3),
        color = c("blue", "yellow")
    )
    board <- TnT::TnTBoard(list(btrack, btrack2, pintrack))
    genome_view <- TnT::TnTGenome(
        list(pintrack, btrack2),
        view.range = GenomicRanges::GRanges("chr7",
            IRanges::IRanges(26550000, 26600000)
        ),
        coord.range = IRanges::IRanges(26350000, 27050000),
        zoom.allow = IRanges::IRanges(50000, 200000)
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
        write.csv(as.data.frame(.main), "${prefix}_tnt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_tnt_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_tnt_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TNT:", paste0("    tnt: ", as.character(packageVersion("TnT")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tnt_results.csv
    touch ${prefix}_tnt_output.rds
    echo "BIOC_TNT:" > versions.yml
    echo "    tnt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TNT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TNT(ch_input)

    emit:
    results  = BIOC_TNT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TNT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TNT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TNT.out.versions  // channel: path(versions.yml)
}
