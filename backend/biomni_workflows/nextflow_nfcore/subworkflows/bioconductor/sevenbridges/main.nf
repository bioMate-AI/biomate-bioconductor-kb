#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sevenbridges
// R client and utilities for Seven Bridges platform API, from Cancer Genomics Cloud to other Seven Bri
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sevenbridges/inst/doc/api.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sevenbridges")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_SEVENBRIDGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sevenbridges"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sevenbridges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sevenbridges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sevenbridges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sevenbridges)
    library(Auth)
    library(Date)
    library(Metadata)
    library(Tool)
    library(jsonlite)

    # --- Platform Authentication ---
    # Key functions: Auth
    a <- Auth(
        token = "your_token",
        platform = "aws-us"
    )
    p <- a\$project(id = "your_project_id")

    # --- App Schema Inspection ---
    # Key functions: convert_app, output_matrix
    f1 <- system.file(
        "extdata/app", "flow_star.json",
        package = "sevenbridges"
    )
    app <- convert_app(f1)
    in_mat <- app\$input_matrix(
        c("id", "label", "type"),
        required = TRUE
    )
    out_mat <- output_matrix(f1)

    # --- File Querying ---
    # Key functions: Auth
    fastq_in <- p\$file(
        name = "SRR1039508*.fastq",
        complete = TRUE
    )
    fasta_in <- p\$file(
        name = "Homo_sapiens.GRCh38.dna.primary_assembly.fa",
        exact = TRUE
    )
    gtf_in <- p\$file(
        name = "Homo_sapiens.GRCh38.84.gtf",
        exact = TRUE
    )

    # --- Task Creation and Batching ---
    # Key functions: batch
    taskName <- "RFranklin-star-alignment"
    tsk <- p\$task_add(
        name = taskName,
        description = "Batch Star Test",
        app = "RFranklin/api-testing-2/newcopyofstar/0",
        batch = batch(
            input = "fastq",
            criteria = c("metadata.sample_id")
        ),
        inputs = list(
            sjdbGTFfile = gtf_in,
            fastq = fastq_in,
            genomeFastaFiles = fasta_in
        )
    )

    # --- Task Execution and Monitoring ---
    # Key functions: setTaskHook, getTaskHook
    tsk\$run()
    setTaskHook("completed", function() {
        tsk\$download(tempdir())
        return(TRUE)
    })
    current_hook <- getTaskHook("completed")


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
        write.csv(as.data.frame(.main), "${prefix}_sevenbridges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_sevenbridges_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_sevenbridges_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEVENBRIDGES:", paste0("    sevenbridges: ", as.character(packageVersion("sevenbridges")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sevenbridges_results.csv
    touch ${prefix}_sevenbridges_output.rds
    echo "BIOC_SEVENBRIDGES:" > versions.yml
    echo "    sevenbridges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEVENBRIDGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEVENBRIDGES(ch_input)

    emit:
    results  = BIOC_SEVENBRIDGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEVENBRIDGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEVENBRIDGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEVENBRIDGES.out.versions  // channel: path(versions.yml)
}
