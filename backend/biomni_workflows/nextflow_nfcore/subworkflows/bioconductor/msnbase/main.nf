#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSnbase
// MSnbase provides infrastructure for manipulation, processing and visualisation of mass spectrometry 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSnbase/inst/doc/v01-MSnbase-demo.R
// Upstream  : BiocParallel, BiocStyle, Rdisop, doParallel, ggplot2
// Downstream: bandle, msmsEDA, msmsTests, pRoloc, pRolocGUI
//
// Install: BiocManager::install("MSnbase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSNBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msnbase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msnbase:2.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msnbase:2.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msnbase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msnbase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msnbase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSmap)
    library(PXDataset)
    library(jsonlite)

    # --- Filter by row sum threshold [] ---
    # Key functions: sampleNames, rowSums, ggplot, geom_boxplot

    # --- Merge overlapping ranges [] ---
    # Key functions: reduce
    iddf2 <- reduce(iddf, key = "spectrumID")
    # --- Combine peptide features to proteins [] ---
    # Key functions: combineFeatures, quantify, fData, exprs, sample, droplevels
    sc <- quantify(msexp, method = "count")
    fData(sc)$DatabaseAccess[1] <- fData(sc)$DatabaseAccess[2]
    fData(sc)$DatabaseAccess
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_density, facet_wrap, filterIdentificationDataFrame
    library("ggplot2")
    ggplot(data = iddf, aes(x = MS.GF.RawScore, colour = isDecoy)) +
    geom_density() +
    # --- ReadMSData analysis [] ---
    # Key functions: readMSData, writeMSData, peaksCount, rtime, chromatogram, PXDataset, pxget, openMSfile


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msnbase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msnbase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msnbase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSNBASE:", paste0("    msnbase: ", packageVersion("MSnbase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msnbase_results.csv
    touch ${prefix}_msnbase_output.rds
    echo "BIOC_MSNBASE:" > versions.yml
    echo "    msnbase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSNBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSNBASE(ch_input)

    emit:
    results  = BIOC_MSNBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSNBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSNBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSNBASE.out.versions  // channel: path(versions.yml)
}
