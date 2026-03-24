#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: triplex
// This package provides functions for identification and visualization of potential intramolecular tri
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/triplex/inst/doc/triplex.R
// Upstream  : rtracklayer
// Downstream: none
//
// Install: BiocManager::install("triplex")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRIPLEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-triplex"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-triplex:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-triplex:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_triplex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_triplex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_triplex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAString)
    library(jsonlite)

    # --- Dnastring [] ---
    # Key functions: DNAString, search
    seq <- DNAString("TTGGGGAAAGCAATGCCAGGCAGGGGGTTCCTTTCGTTACGGTCCGTCCC")
    triplex.search(seq)
    # --- Search [] ---
    # Key functions: search
    triplex.search(seq, type=1)
    # --- Alignment [] ---
    # Key functions: alignment
    triplex.alignment(t[1])
    # --- Diagram [] ---
    # Key functions: diagram
    triplex.diagram(t[1])
    # --- Alignment [] ---
    # Key functions: alignment
    triplex.alignment(t[1])
    # --- Export [] ---
    # Key functions: export
    library(rtracklayer)
    export(gr,"test.gff", version="3")
    # --- Readlines [] ---
    # Key functions: strwrap
    text <- readLines("test.gff",n=10)
    cat(strwrap(text, width=80, exdent=3),sep="\n")
    # --- Writexstringset [] ---
    # Key functions: writeXStringSet
    writeXStringSet(dss, file="test.fa", format="fasta")
    # --- Search [] ---
    # Key functions: search
    t <- triplex.search(Celegans[["chrX"]][1:100000],min_score=17,min_len=8)
    t
    # --- Order [] ---
    # Key functions: score
    ts <- t[order(score(t),decreasing=TRUE)]
    ts
    # --- Diagram [] ---
    # Key functions: diagram
    triplex.diagram(ts[1])
    # --- 3D [] ---
    # Key functions: 3D
    ## triplex.3D(ts[1])
    # --- Alignment [] ---
    # Key functions: alignment
    triplex.alignment(ts[1])
    # --- Export [] ---
    # Key functions: export
    library(rtracklayer)
    export(as(t, "GRanges"),"test.gff", version="3")
    # --- Readlines [] ---
    # Key functions: strwrap
    text <- readLines("test.gff",n=10)
    cat(strwrap(text, width=80, exdent=3),sep="\n")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_triplex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_triplex_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_triplex_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRIPLEX:", paste0("    triplex: ", packageVersion("triplex"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_triplex_results.csv
    touch ${prefix}_triplex_output.rds
    echo "BIOC_TRIPLEX:" > versions.yml
    echo "    triplex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRIPLEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRIPLEX(ch_input)

    emit:
    results  = BIOC_TRIPLEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRIPLEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRIPLEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRIPLEX.out.versions  // channel: path(versions.yml)
}
