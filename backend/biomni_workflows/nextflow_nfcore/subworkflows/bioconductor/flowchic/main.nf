#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowCHIC
// A package to analyze flow cytometric data of complex microbial communities based on histogram images
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowCHIC/inst/doc/flowCHICmanual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowCHIC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCHIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowchic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowchic:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowchic:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowchic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowchic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowchic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FCS)
    library(jsonlite)

    # --- Getchannels [] ---
    # Key functions: files, FCS, unname
    ## # Set the working directory to the path where your FCS files are located
    ## # Type the path into the quotes
    ## setwd("")
    ## # Or in Windows use
    ## setwd(choose.dir(getwd(), "Choose the folder containing the FCS files"))
    # --- Createimage [] ---
    # Key functions: fcs_to_img
    ## # Create the histogram images using default parameters
    ## fcs_to_img(files)
    ## # Create the histogram images using different channels
    ## # Not working for the FCS files attached to the package
    ## fcs_to_img(files,ch1="SS.Log",ch2="FL.1.Log")
    # --- Createsubset [] ---
    # Key functions: img_sub
    ## # Create the histogram image subsets using default parameters
    ## img_sub(files,ch1="FS.Log",ch2="FL.4.Log")
    # --- Createchangedsubset [] ---
    # Key functions: img_sub
    ## # Create the histogram images using different boundaries for the x/y axis
    ## # and a different value for the maximal value set to black
    ## # These values work well for the first downloadable dataset and
    ## # the FCS files included to the package
    ## img_sub(files,x_start=200,x_end=3500,y_start=1000,y_end=3000,maxv=160)
    # --- Calculatexorover [] ---
    # Key functions: files, calculate_overlaps_xor
    ## # Save the names of all subset images as a list
    ## subsets <- list.files(path=paste(getwd(),"chic_subset",sep="/"),full=TRUE,pattern="*.png")
    ## # Calculate overlap and XOR images and write values to two new files
    ## results<-calculate_overlaps_xor(subsets)
    # --- Calculatexorover Files [] ---
    # Key functions: files, calculate_overlaps_xor
    ## # Save the names of all subset images as a list
    ## subsets <- list.files(path=paste(getwd(),"chic_subset",sep="/"),full=TRUE,pattern="*.png")
    ## # Calculate overlap and XOR images and write values to two new files
    ## calculate_overlaps_xor(subsets,verbose=TRUE)
    # --- Nmdsxoroverlaplist [] ---
    # Key functions: plot_nmds
    ## # Show a NMDS plot of the samples
    ## plot_nmds(results$overlap,results$xor)
    # --- Readoverxor [] ---
    # Key functions: data
    ## # Type the filename of the overlap data (including extension) into the quotes
    ## Results_overlaps<-read.table("Results_overlaps.txt",header=TRUE,sep="\t")
    ## # Type the filename of the XOR data (including extension) into the quotes
    ## Results_xor<-read.table("Results_xor.txt",header=TRUE,sep="\t")
    # --- Nmdsxoroverlapread [] ---
    # Key functions: plot_nmds
    ## # Show a NMDS plot of the samples
    ## plot_nmds(Results_overlaps,Results_xor)
    # --- Plotdefault [] ---
    # Key functions: plot_nmds
    # Load datasets
    data(Results_overlaps)
    data(Results_xor)
    # Show a NMDS plot of the samples
    plot_nmds(Results_overlaps,Results_xor)
    # --- Plotdefaultchanged [] ---
    # Key functions: plot_nmds
    # Change default parameters
    plot_nmds(Results_overlaps,Results_xor,main="NMDS plot",pos=3,pch=2,col_nmds="red")
    # --- Overlapsmix [] ---
    # Key functions: data
    # Load dataset
    data(Results_overlaps_mix)
    # Show data (first five lines)
    Results_overlaps_mix[1:5,]
    # --- Xormix [] ---
    # Key functions: data
    # Load dataset
    data(Results_xor_mix)
    # Show data (first five lines)
    Results_xor_mix[1:5,]
    # --- Plotdefault Mix [] ---
    # Key functions: plot_nmds
    # Plot
    plot_nmds(Results_overlaps_mix,Results_xor_mix)
    # --- Overlapsincol [] ---
    # Key functions: data
    # Load dataset
    data(Results_overlaps_incol)
    # Show data (first five lines)
    Results_overlaps_incol[1:5,]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowchic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowchic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowchic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWCHIC:", paste0("    flowchic: ", packageVersion("flowCHIC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowchic_results.csv
    touch ${prefix}_flowchic_output.rds
    echo "BIOC_FLOWCHIC:" > versions.yml
    echo "    flowchic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWCHIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWCHIC(ch_input)

    emit:
    results  = BIOC_FLOWCHIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWCHIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWCHIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWCHIC.out.versions  // channel: path(versions.yml)
}
