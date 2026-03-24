#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scanMiRApp
// A shiny interface to the scanMiR package. The application enables the scanning of transcripts and cu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scanMiRApp/inst/doc/IndexedFST.R
// Upstream  : BiocStyle, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("scanMiRApp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCANMIRAPP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scanmirapp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scanmirapp:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scanmirapp:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scanmirapp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scanmirapp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scanmirapp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Loadindexedfst [] ---
    # Key functions: loadIndexedFst
    ---------------------------------------------------------------------
    d2 <- loadIndexedFst(f)
    class(d2)
    summary(d2)
    # --- Format [] ---
    # Key functions: size
    ---------------------------------------------------------------------
    format(object.size(d),units="Kb")
    format(object.size(d2),units="Kb")
    # --- Granges [] ---
    # Key functions: GRanges, sample, IRanges, factor
    ---------------------------------------------------------------------
    library(GenomicRanges)
    gr <- GRanges(sample(LETTERS[1:3],200,replace=TRUE), IRanges(seq_len(200), width=2))
    gr$propertyA <- factor(sample(letters[1:5],200,replace=TRUE))
    gr
    # --- Saveindexedfst [] ---
    # Key functions: saveIndexedFst, loadIndexedFst
    ---------------------------------------------------------------------
    saveIndexedFst(gr, index.by="propertyA", file.prefix=f2)
    d2 <- loadIndexedFst(f2)
    names(d2)
    # --- Files [] ---
    # Key functions: files
    ---------------------------------------------------------------------
    list.files(tmp, "test2")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scanmirapp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scanmirapp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scanmirapp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCANMIRAPP:", paste0("    scanmirapp: ", packageVersion("scanMiRApp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scanmirapp_results.csv
    touch ${prefix}_scanmirapp_output.rds
    echo "BIOC_SCANMIRAPP:" > versions.yml
    echo "    scanmirapp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCANMIRAPP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCANMIRAPP(ch_input)

    emit:
    results  = BIOC_SCANMIRAPP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCANMIRAPP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCANMIRAPP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCANMIRAPP.out.versions  // channel: path(versions.yml)
}
