#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genomeIntervals
// This package defines classes for representing genomic intervals and provides functions and methods f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genomeIntervals/inst/doc/genomeIntervals.R
// Upstream  : none
// Downstream: girafe
//
// Install: BiocManager::install("genomeIntervals")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMEINTERVALS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomeintervals"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomeintervals:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomeintervals:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomeintervals_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomeintervals_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomeintervals_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(genomeIntervals)
    library(jsonlite)

    # --- Classes [] ---
    # Key functions: data
    library( genomeIntervals )
    data("gen_ints")
    i
    # --- Ends [] ---
    # Key functions: closed
    i[,1]
    i[,2]
    closed(i)
    closed(i)[2,2] <- FALSE
    # --- closed [] ---
    # Key functions: closed
    i2 <- i
    closed(i2) <- c( TRUE, FALSE )
    i2
    # --- seqnames [] ---
    # Key functions: seqnames, strand
    seqnames(i)
    strand(i)
    strand(i)[2] <- "-"
    # --- Annotation [] ---
    # Key functions: annotation
    annotation(i)
    annotation(i)$myannot = rep( c("my", "annot"), length=nrow(i) )
    annotation(i[2:3,])
    # --- Intervaloverlap [] ---
    # Key functions: interval_overlap
    interval_overlap( from=i, to=j )
    # --- Setoperations [] ---
    # Key functions: interval_intersection, interval_complement
    interval_intersection(i,j)
    interval_complement(j[1:2,])
    # --- Distance [] ---
    # Key functions: distance_to_nearest
    distance_to_nearest(i,j)
    # --- Inter Base [] ---
    # Key functions: inter_base
    k
    inter_base(k)
    k[inter_base(k),]
    # --- Intervaloverlap.Inter Base [] ---
    # Key functions: interval_overlap
    interval_overlap(j,k)
    # --- Distance.Inter Base [] ---
    # Key functions: distance_to_nearest
    distance_to_nearest(j,k)
    # --- Setoperations.Inter Base [] ---
    # Key functions: interval_union, interval_intersection, interval_complement
    interval_union(k)
    interval_intersection(k,j)
    interval_complement(k[1:2,])
    # --- Loadgff [] ---
    # Key functions: packages, path, readGff3, getGffAttribute
    libPath <- installed.packages()["genomeIntervals", "LibPath"]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomeintervals_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomeintervals_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomeintervals_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMEINTERVALS:", paste0("    genomeintervals: ", packageVersion("genomeIntervals"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomeintervals_results.csv
    touch ${prefix}_genomeintervals_output.rds
    echo "BIOC_GENOMEINTERVALS:" > versions.yml
    echo "    genomeintervals: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMEINTERVALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMEINTERVALS(ch_input)

    emit:
    results  = BIOC_GENOMEINTERVALS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMEINTERVALS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMEINTERVALS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMEINTERVALS.out.versions  // channel: path(versions.yml)
}
