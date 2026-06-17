#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.vcf
// Save variant calling SummarizedExperiment to file and load them back as VCF objects. This is a more 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.vcf/inst/doc/userguide.R
// Upstream  : BiocStyle, VariantAnnotation
// Downstream: none
//
// Install: BiocManager::install("alabaster.vcf")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ALABASTER_VCF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_vcf"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_vcf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_vcf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_vcf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("alabaster.vcf", "jsonlite", "alabaster.se")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(alabaster.vcf)
    library(jsonlite)

    # --- Acquiremetadata [] ---
    # Key functions: acquireMetadata, loadObject
    ---------------------------------------------------------------------
    meta <- acquireMetadata(tmp, "vcf/experiment.json")
    roundtrip <- loadObject(meta, tmp)
    class(roundtrip)
    # --- Loadsummarizedexperiment [] ---
    # Key functions: loadSummarizedExperiment
    ---------------------------------------------------------------------
    library(alabaster.se)
    loadSummarizedExperiment(meta, tmp)

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
        write.csv(as.data.frame(.main), "${prefix}_alabaster_vcf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_alabaster_vcf_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_alabaster_vcf_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_VCF:", paste0("    alabaster_vcf: ", as.character(packageVersion("alabaster.vcf")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_vcf_results.csv
    touch ${prefix}_alabaster_vcf_output.rds
    echo "BIOC_ALABASTER_VCF:" > versions.yml
    echo "    alabaster_vcf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_VCF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_VCF(ch_input)

    emit:
    results  = BIOC_ALABASTER_VCF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_VCF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_VCF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_VCF.out.versions  // channel: path(versions.yml)
}
