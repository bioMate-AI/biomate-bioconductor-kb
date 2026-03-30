#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hopach
// The HOPACH clustering algorithm builds a hierarchical tree of clusters by recursively partitioning a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hopach/inst/doc/hopach.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("hopach")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HOPACH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hopach"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hopach:2.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hopach:2.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hopach_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hopach_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hopach_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Data)
    library(jsonlite)

    # --- Golub [] ---
    # Key functions: data
    library(hopach)
    data(golub)
    # --- Distance [] ---
    # Key functions: distancematrix
    gene.dist<-distancematrix(golub.subset,"cosangle")
    dim(gene.dist)
    # --- Hopachgene [] ---
    # Key functions: hopach
    gene.hobj<-hopach(golub.subset,dmat=gene.dist)
    gene.hobj$clust$k
    table(gene.hobj$clust$labels)
    gene.hobj$clust$sizes
    # --- Dplot [] ---
    # Key functions: dplot, Data
    ## dplot(gene.dist,gene.hobj,ord="final",main="Golub AML/ALL Data (1999): Gene Distance Matrix",showclusters=FALSE)
    # --- Bootstrap [] ---
    # Key functions: boothopach
    bobj<-boothopach(golub.subset,gene.hobj,B=100)
    # --- Bootplot [] ---
    # Key functions: bootplot, Data
    ## bootplot(bobj,gene.hobj,ord="bootp",main="Golub AML/ALL Data (1999)",showclusters=FALSE)
    # --- Hopacharray [] ---
    # Key functions: hopach
    array.hobj<-hopach(t(golub.subset),d="euclid")
    array.hobj$clust$k
    # --- Output [] ---
    # Key functions: makeoutput
    ## makeoutput(golub.subset,gene.hobj,bobj,file="Golub.out",gene.names=gnames.subset[,3])
    # --- Fuzzy [] ---
    # Key functions: boot2fuzzy
    ## boot2fuzzy(golub.subset,bobj,gene.hobj,array.hobj,file="GolubFuzzy",gene.names=gnames.subset[,3])
    # --- Hierarchical [] ---
    # Key functions: hopach2tree
    ## hopach2tree(golub.subset,file="GolubTree",hopach.genes=gene.hobj,hopach.arrays=NULL,dist.genes=gene.dist,gene.names=gnames.subset[,3])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hopach_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hopach_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hopach_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HOPACH:", paste0("    hopach: ", packageVersion("hopach"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hopach_results.csv
    touch ${prefix}_hopach_output.rds
    echo "BIOC_HOPACH:" > versions.yml
    echo "    hopach: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HOPACH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HOPACH(ch_input)

    emit:
    results  = BIOC_HOPACH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HOPACH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HOPACH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HOPACH.out.versions  // channel: path(versions.yml)
}
