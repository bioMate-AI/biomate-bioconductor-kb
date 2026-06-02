#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: made4
// Multivariate data analysis and graphical display of microarray data. Functions include for supervise
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/made4/inst/doc/introduction.R
// Upstream  : ade4, scatterplot3d
// Downstream: none
//
// Install: BiocManager::install("made4")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MADE4 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-made4"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-made4:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-made4:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_made4_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_made4_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_made4_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(made4)
    library(jsonlite)


    # --- Eval=false [] ---
    # Key functions: requireNamespace, install, made4, overview, ord, coa
    #  if (!requireNamespace("BiocManager", quietly=TRUE))
    #      install.packages("BiocManager")
    #  BiocManager::install("made4")

    ## -----------------------------------------------------------------------------
     library(made4)
     library(ade4)
     data(khan)

    ## -----------------------------------------------------------------------------
    overview(k.data, labels=k.class)
    overview(k.data, classvec=k.class, labels=k.class)

    ## -----------------------------------------------------------------------------
    k.coa<- ord(k.data, type="coa")

    # --- Output Coa [] ---
    # Key functions: summary, grey3
    names(k.coa)
    summary(k.coa$ord)
    k.class
    plot(k.coa, classvec=k.class, genecol="grey3")

    # --- Plotarrays [] ---
    # Key functions: plotarrays, ord, plotgenes, red
    plotarrays(k.coa, arraylabels=k.class)
    k.coa2<-ord(k.data, classvec=k.class)
    plot(k.coa2)
    plotgenes(k.coa, n=5, col="red")

    # --- Plotgenescmd [] ---
    # Key functions: plotgenes, red, topgenes, neg
    gene.symbs<- khan$annotation$Symbol 
    gene.symbs[1:4]
    plotgenes(k.coa, n=10, col="red", genelabels=gene.symbs)
    topgenes(k.coa, labels=gene.symbs, end="neg")

    # --- Do3d [] ---
    # Key functions: do3d, include_graphics, html3D.png, bga, coa
    do3d(k.coa$ord$co, classvec=k.class, cex.symbols=3)
    knitr::include_graphics("html3D.png")
    k.bga<-bga(k.data, type="coa", classvec=k.class)

    # --- Bgaplot [] ---
    # Key functions: between.graph, axes, cia, G1_Ross_1375.txt, G5_Affy_1517.txt
    plot(k.bga, genelabels=gene.symbs) # Use the gene symbols earlier
    between.graph(k.bga, ax=1)  # Show the separation on the first axes(ax)
    # Example data are "G1_Ross_1375.txt" and "G5_Affy_1517.txt"
    data(NCI60)
    coin <- cia(NCI60$Ross, NCI60$Affy)
    names(coin)
    coin$coinertia$RV

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_made4_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_made4_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_made4_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MADE4:", paste0("    made4: ", packageVersion("made4"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_made4_results.csv
    touch ${prefix}_made4_output.rds
    echo "BIOC_MADE4:" > versions.yml
    echo "    made4: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MADE4_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MADE4(ch_input)

    emit:
    results  = BIOC_MADE4.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MADE4.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MADE4.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MADE4.out.versions  // channel: path(versions.yml)
}
