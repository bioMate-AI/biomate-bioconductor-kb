#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bigmelon
// Methods for working with Illumina arrays using gdsfmt.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bigmelon/inst/doc/bigmelon.R
// Upstream  : methylumi
// Downstream: none
//
// Install: BiocManager::install("bigmelon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIGMELON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bigmelon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bigmelon:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bigmelon:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bigmelon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bigmelon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bigmelon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bigmelon)
    library(jsonlite)

    # --- Code Block [] ---
    # Key functions: es2gds, betas, gdsn, pfilter, dasen
    library(bigmelon)
    data(melon)
    # Convert methylumiset or methylset objects to .gds
    gfile <- es2gds(melon, 'melon.gds')
    # 'melon.gds' file created in current working directory
    # --- Unseencodeandoutput [] ---
    # Key functions: gds, unlink
    closefn.gds(gfile)
    unlink('melon.gds', force = TRUE)
    # --- Unevaluatedcode [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install('wateRmelon', 'gdsfmt')
    # --- Unevaluatedcode [] ---
    # Key functions: packages
    ## install.packages('bigmelon_0.99.11.tar.gz', repos = NULL, type = 'source')
    # --- Unevaluatedcode [] ---
    # Key functions: iadd, iadd2
    ## # read in an IDAT file with barcode 'sentrixid_rnncnn'
    ## gfile <- iadd('sentrixid_rnncnn', gds = 'melon.gds')
    ## gfile <- iadd2('Data/IDATLocations/dataset', gds = 'melon.gds', chunksize = 100)
    # --- Code Block [] ---
    # Key functions: es2gds
    data(melon)
    gfile <- es2gds(melon, 'melon.gds')
    # --- Unevaluatedcode [] ---
    # Key functions: methyLumiR, finalreport2gds
    ## library(methylumi)
    ## # read Illumina methylation data into a MethyLumiSet object
    ## melon <- methyLumiR('finalreport.txt')
    ## # read Illumina methylation final report into a gds.class object.
    ## gfile <- finalreport2gds('finalreport.txt', gds='melon.gds')
    # --- Unevaluatedcode [] ---
    # Key functions: es2gds
    ## # convert a MethyLumiSet object to a gds.class object
    ## gfile <- es2gds(melon, 'melon.gds')
    # --- Unevaluatedcode [] ---
    # Key functions: gds
    ## # Closing File
    ## closefn.gds(gfile)
    ##
    ## # Opening File
    ## gfile <- openfn.gds('melon.gds')
    # --- Code Block [] ---
    # Key functions: gdsn
    index.gdsn(gfile, 'betas')
    class(index.gdsn(gfile, 'betas'))
    # Access nodes with additional nodes inside
    index.gdsn(gfile, 'fData/TargetID')
    # --- Code Block [] ---
    # Key functions: betas
    betas(gfile)
    class(betas(gfile))
    # --- Code Block [] ---
    # Key functions: gdsn
    ls.gdsn(gfile)
    # Look into nodes with additional nodes
    ls.gdsn(index.gdsn(gfile, 'fData'))
    # --- Code Block [] ---
    # Key functions: betas, gdsn
    # Call a gdsn.class node
    anode <- betas(gfile)
    anode
    class(anode)
    # All data
    # --- Code Block [] ---
    # Key functions: characters
    # Logical Indexing
    anode[1:5,c(TRUE,FALSE,FALSE)]
    # Ordering calls
    anode[c(5,9,1,500,345), c(8,4,1,3)]
    # Indexing by characters (and drop functionality)
    # --- Code Block [] ---
    # Key functions: gdsn
    read.gdsn(index.gdsn(gfile, "paths"))
    head(read.gdsn(index.gdsn(gfile, "fData/TargetID")))
    head(read.gdsn(index.gdsn(gfile, "pData/sampleID")))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bigmelon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bigmelon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bigmelon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIGMELON:", paste0("    bigmelon: ", packageVersion("bigmelon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bigmelon_results.csv
    touch ${prefix}_bigmelon_output.rds
    echo "BIOC_BIGMELON:" > versions.yml
    echo "    bigmelon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIGMELON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIGMELON(ch_input)

    emit:
    results  = BIOC_BIGMELON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIGMELON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIGMELON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIGMELON.out.versions  // channel: path(versions.yml)
}
