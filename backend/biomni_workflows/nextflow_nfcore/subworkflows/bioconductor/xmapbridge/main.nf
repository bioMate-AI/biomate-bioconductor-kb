#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: xmapbridge
// xmapBridge can plot graphs in the X:Map genome browser. This package exports plotting files in a sui
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/xmapbridge/inst/doc/xmapbridge.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("xmapbridge")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XMAPBRIDGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xmapbridge"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-xmapbridge:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-xmapbridge:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xmapbridge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xmapbridge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xmapbridge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(xmapbridge)
    library(jsonlite)

    # --- Debug [] ---
    # Key functions: debug
    cat( xmap.debug( xmap.plot( x, y, species="homo_sapiens", chr="1", type="line" ), newlines=TRUE ) )
    # --- Split [] ---
    # Key functions: split
    l <- split(exon.data,exon.data$"gene")
    # --- Debug [] ---
    # Key functions: debug
    cat( xmap.debug( xmap.plot(x,y,chr,species="homo_sapiens",type="area",col="#ff000066"), newlines=TRUE ) )
    # --- Array [] ---
    # Key functions: array, 4th
    #We were plotting the 1st array (2nd column in g), now plot the 4th (5th column in g)
    y <- g[,5]
    # --- Debug [] ---
    # Key functions: debug
    cat( xmap.debug( xmap.points(x,y,chr,type="area",col="#0000ff33"), newlines=TRUE ) )
    # --- Pal [] ---
    # Key functions: pal, col
    #Five levels of red, chosen by the RColorBrewer
    reds <- brewer.pal( 5, "Reds" )
    reds <- xmap.col( reds, alpha=0x55 )
    # --- Setenv [] ---
    # Key functions: setenv
    #put the environment variable back. Not strictly necessary, but why not?
    Sys.setenv(XMAP_BRIDGE_CACHE=old.path)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_xmapbridge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_xmapbridge_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_xmapbridge_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_XMAPBRIDGE:", paste0("    xmapbridge: ", packageVersion("xmapbridge"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xmapbridge_results.csv
    touch ${prefix}_xmapbridge_output.rds
    echo "BIOC_XMAPBRIDGE:" > versions.yml
    echo "    xmapbridge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XMAPBRIDGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XMAPBRIDGE(ch_input)

    emit:
    results  = BIOC_XMAPBRIDGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XMAPBRIDGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XMAPBRIDGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XMAPBRIDGE.out.versions  // channel: path(versions.yml)
}
