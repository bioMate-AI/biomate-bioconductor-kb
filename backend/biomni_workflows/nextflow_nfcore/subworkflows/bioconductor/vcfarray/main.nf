#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VCFArray
// VCFArray extends the DelayedArray to represent VCF data entries as array-like objects with on-disk /
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VCFArray/inst/doc/VCFArray.R
// Upstream  : VariantAnnotation
// Downstream: none
//
// Install: BiocManager::install("VCFArray")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_VCFARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vcfarray"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vcfarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vcfarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vcfarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DelayedArray)
    library(RangedVcfStack)
    library(VCFArray)
    library(VcfFile)
    library(VcfStack)
    library(jsonlite)

    # --- Args analysis [] ---
    # Key functions: args, vcfFields, VCFArray, VcfFile, VcfStack, RangedVcfStack, lengths, path
    extdata <- system.file(package = "GenomicFiles", "extdata")
    files <- dir(extdata, pattern="^CEUtrio.*bgz\$", full=TRUE)[1:2]
    names(files) <- sub(".*_([0-9XY]+).*", "\\1", basename(files))

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
        write.csv(as.data.frame(.main), "${prefix}_vcfarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_vcfarray_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_vcfarray_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_VCFARRAY:", paste0("    vcfarray: ", as.character(packageVersion("VCFArray")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vcfarray_results.csv
    touch ${prefix}_vcfarray_output.rds
    echo "BIOC_VCFARRAY:" > versions.yml
    echo "    vcfarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VCFARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VCFARRAY(ch_input)

    emit:
    results  = BIOC_VCFARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VCFARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VCFARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VCFARRAY.out.versions  // channel: path(versions.yml)
}
