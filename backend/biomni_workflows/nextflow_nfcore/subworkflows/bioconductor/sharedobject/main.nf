#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SharedObject
// This package is developed for facilitating parallel computing in R. It is capable to create an R obj
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/SharedObject/inst/doc/quick_start_guide.html
// Upstream  : parallel
// Downstream: none
//
// Install: BiocManager::install("SharedObject")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SHAREDOBJECT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sharedobject"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sharedobject:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sharedobject:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sharedobject_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sharedobject_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sharedobject_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SharedObject)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: share
    ## Create data
    A1 <- matrix(1:9, 3, 3)
    ## Create a shared object
    A2 <- share(A1)
    # --- Code Block 2 [] ---
    # Key functions: makeCluster, clusterExport, clusterEvalQ, shared, stopCluster
    library(parallel)
    ## Create a cluster with only 1 worker
    cl <- makeCluster(1)
    clusterExport(cl, "A2")
    ## Check if the object is still a shared object
    # --- Code Block 3 [] ---
    # Key functions: share, serialize
    ## make a larger vector
    x1 <- rep(0, 10000)
    x2 <- share(x1)
    ## This is the actual data that will
    ## be sent to the other R workers
    # --- Code Block 4 [] ---
    # Key functions: symbol, share
    ## the element `A` is sharable and `B` is not
    x <- list(A = 1:3, B = as.symbol("x"))
    ## No error will be given,
    ## but the element `B` is not shared
    shared_x <- share(x)
    # --- Code Block 5 [] ---
    # Key functions: sharedObjectPkgOptions
    sharedObjectPkgOptions()
    #> $mustWork
    #> [1] FALSE
    #>
    #> $sharedAttributes
    # --- Code Block 6 [] ---
    # Key functions: share, shared
    x1 <- share(1:4)
    x2 <- x1
    ## x2 becames a regular R object after the change
    is.shared(x2)
    #> [1] TRUE
    # --- Code Block 7 [] ---
    # Key functions: share, shared
    x1 <- share(1:4, copyOnWrite = FALSE)
    x2 <- x1
    ## x2 will not be duplicated when a change is made
    is.shared(x2)
    #> [1] TRUE
    # --- Code Block 8 [] ---
    # Key functions: share
    x <- share(1:4, copyOnWrite = FALSE)
    x
    #> [1] 1 2 3 4
    -x
    #> [1] -1 -2 -3 -4
    # --- Code Block 9 [] ---
    # Key functions: share, setCopyOnWrite
    ## Create x1 with copy-on-write off
    x1 <- share(1:4, copyOnWrite = FALSE)
    x2 <- x1
    ## change the value of x2
    x2[1] <- 0L
    # --- Code Block 10 [] ---
    # Key functions: share, shared
    x1 <- share(1:4)
    x2 <- x1
    ## x2 is not shared after the duplication
    is.shared(x2)
    #> [1] TRUE
    # --- Code Block 11 [] ---
    # Key functions: listSharedObjects
    listSharedObjects()
    #>   Id  size
    #> 1 53    36
    #> 2 54 80000
    #> 3 57    12
    # --- Code Block 12 [] ---
    # Key functions: pkgconfig
    SHARED_OBJECT_LIBS = $(shell echo 'SharedObject:::pkgconfig("PKG_LIBS")'|\
    "${R_HOME}/bin/R" --vanilla --slave)
    SHARED_OBJECT_CPPFLAGS = $(shell echo 'SharedObject:::pkgconfig("PKG_CPPFLAGS")'|\
    "${R_HOME}/bin/R" --vanilla --slave)
    PKG_LIBS := $(PKG_LIBS) $(SHARED_OBJECT_LIBS)
    # --- Code Block 13 [] ---
    # Key functions: 1, namespace
    sessionInfo()
    #> R version 4.4.1 (2024-06-14)
    #> Platform: x86_64-pc-linux-gnu
    #> Running under: Ubuntu 24.04.1 LTS
    #>

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sharedobject_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sharedobject_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sharedobject_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SHAREDOBJECT:", paste0("    sharedobject: ", packageVersion("SharedObject"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sharedobject_results.csv
    touch ${prefix}_sharedobject_output.rds
    echo "BIOC_SHAREDOBJECT:" > versions.yml
    echo "    sharedobject: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SHAREDOBJECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SHAREDOBJECT(ch_input)

    emit:
    results  = BIOC_SHAREDOBJECT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SHAREDOBJECT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SHAREDOBJECT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SHAREDOBJECT.out.versions  // channel: path(versions.yml)
}
