#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OrderedList
// Detection of similarities between ordered lists of genes. Thereby, either simple lists can be compar
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OrderedList/inst/doc/tr_2006_01.R
// Upstream  : Biobase, twilight
// Downstream: none
//
// Install: BiocManager::install("OrderedList")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ORDEREDLIST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-orderedlist"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-orderedlist:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-orderedlist:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_orderedlist_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_orderedlist_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_orderedlist_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OrderedList)
    library(jsonlite)

    # --- Exit [] ---
    # Key functions: exit
    library(Biobase)
    library(twilight)
    oldopt <- options(digits=3)
    on.exit( {options(oldopt)} )
    options(width=75)
    # --- Data [] ---
    # Key functions: prepareData
    library(OrderedList)
    data(OL.data)
    OL.data$breast
    OL.data$prostate
    OL.data$map[1:5,]
    # --- Orderedlist [] ---
    # Key functions: OrderedList
    x <- OrderedList(A, empirical=TRUE)
    x
    x$intersect[1:5]
    # --- Bitmap [] ---
    # Key functions: bitmap, off, sleep
    bitmap(file="tr_2006_01-pauc.png",width=4,height=3,res=300)
    plot(x,"pauc")
    dev.off()
    Sys.sleep(20)
    bitmap(file="tr_2006_01-scores.png",width=4,height=3, res=300)
    # --- Character [] ---
    # Key functions: sample, compareLists
    list1 <- as.character(OL.data$map$prostate)
    list2 <- c(sample(list1[1:500]),sample(list1[501:1000]))
    y <- compareLists(list1,list2)
    y
    # --- Getoverlap [] ---
    # Key functions: getOverlap
    z <- getOverlap(y)
    z
    z$intersect[1:5]
    # --- Bitmap [] ---
    # Key functions: bitmap, off, sleep
    bitmap(file="tr_2006_01-z.png",width=4,height=3,res=300)
    plot(z)
    dev.off()
    Sys.sleep(20)
    bitmap(file="tr_2006_01-density.png",width=4,height=3,res=300)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_orderedlist_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_orderedlist_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_orderedlist_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ORDEREDLIST:", paste0("    orderedlist: ", packageVersion("OrderedList"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_orderedlist_results.csv
    touch ${prefix}_orderedlist_output.rds
    echo "BIOC_ORDEREDLIST:" > versions.yml
    echo "    orderedlist: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ORDEREDLIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ORDEREDLIST(ch_input)

    emit:
    results  = BIOC_ORDEREDLIST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ORDEREDLIST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ORDEREDLIST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ORDEREDLIST.out.versions  // channel: path(versions.yml)
}
