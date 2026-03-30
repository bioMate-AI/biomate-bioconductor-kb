#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowCyBar
// A package to analyze flow cytometric data using gate information to follow population/community dyna
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowCyBar/inst/doc/flowCyBar-manual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowCyBar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCYBAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowcybar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowcybar:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowcybar:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowcybar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowcybar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowcybar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowCyBar)
    library(jsonlite)

    # --- Readexample [] ---
    # Key functions: filename
    ## # Type the path into the quotes
    ## setwd("")
    ## # or in Windows use
    ## setwd(choose.dir(getwd(), "Choose the folder containing the data"))
    ## # Type the filename (including extension) the quotes
    # --- Cell Number [] ---
    # Key functions: data
    # Load dataset
    data(Cell_number_sample)
    # Show data
    Cell_number_sample[,-1]
    # --- Normalize Mean [] ---
    # Key functions: normalize
    ## # Normalize data, print 2 digits
    ## normalize(Cell_number_sample[,-1],digits=2)
    # --- Normalize First [] ---
    # Key functions: normalize
    ## # Use method "first"
    ## normalize(Cell_number_sample[,-1],method="first",digits=2)
    # --- Writenorm [] ---
    # Key functions: normalize
    ## # Save normalized values
    ## normalized<-normalize(Cell_number_sample[,-1],digits=2)
    ## # Write a new file containing the normalized values
    ## write.table(normalized,file="normalized.txt",row.names=TRUE,
    ## quote=FALSE,sep="\t")
    # --- Cybarplotdefault [] ---
    # Key functions: normalize, frame, cybar_plot
    # Load dataset
    data(Cell_number_sample)
    Normalized_mean<-normalize(Cell_number_sample[,-1],digits=2)
    Normalized_mean<-data.frame(data.matrix(Normalized_mean))
    # Plot with default parameters
    # --- Cybarplotfirst [] ---
    # Key functions: normalize, frame, cybar_plot
    Normalized_first<-normalize(Cell_number_sample[,-1],method="first",digits=2)
    Normalized_first<-data.frame(data.matrix(Normalized_first))
    # Plot with default parameters
    cybar_plot(Normalized_first,Cell_number_sample[,-1])
    # --- Cybarplotfirstrange [] ---
    # Key functions: cybar_plot
    # Plot with changed range
    cybar_plot(x=Normalized_first,to=3.5)
    # --- Cybarlabelorder [] ---
    # Key functions: cybar_plot
    # Plot with different parameters
    cybar_plot(Normalized_mean,Cell_number_sample[,-1],labels="vert",order="sim")
    # --- Cybarlabelorderfirst [] ---
    # Key functions: cybar_plot
    # Plot with different parameters
    cybar_plot(Normalized_first,Cell_number_sample[,-1],to=3.5,labels="vert",order="sim")
    # --- Cybarrowv [] ---
    # Key functions: cybar_plot
    # Barcode with ordered rows
    cybar_plot(x=Normalized_mean,Rowv=TRUE,grad=15,dendrogram="both",
    barmain="Normalized cell numbers")
    # --- Cybarsamples [] ---
    # Key functions: cybar_plot
    # Change row names
    rownames(Normalized_mean)<-Cell_number_sample[,1]
    # Plot
    cybar_plot(Normalized_mean,Cell_number_sample[,-1],
    barmain="Normalized cell numbers",labels="vert",order="sim",boxmain="Cell numbers")
    # --- Nmdsdefault [] ---
    # Key functions: nmds
    # NMDS plot of percental cell numbers
    nmds(Cell_number_sample[,-1])
    # --- Nmdsnormalized [] ---
    # Key functions: normalize, frame, nmds
    Normalized_mean<-normalize(Cell_number_sample[,-1],digits=2)
    Normalized_mean<-data.frame(data.matrix(Normalized_mean))
    # NMDS plot of normalized cel numbers
    nmds(Normalized_mean)
    # --- Nmdschangeparam [] ---
    # Key functions: nmds
    # NMDS plot with different parameters as described
    nmds(Normalized_mean,main="NMDS plot of
    normalized cell numbers",type="b",pos=3,pch=2,col="red")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowcybar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowcybar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowcybar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWCYBAR:", paste0("    flowcybar: ", packageVersion("flowCyBar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowcybar_results.csv
    touch ${prefix}_flowcybar_output.rds
    echo "BIOC_FLOWCYBAR:" > versions.yml
    echo "    flowcybar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWCYBAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWCYBAR(ch_input)

    emit:
    results  = BIOC_FLOWCYBAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWCYBAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWCYBAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWCYBAR.out.versions  // channel: path(versions.yml)
}
