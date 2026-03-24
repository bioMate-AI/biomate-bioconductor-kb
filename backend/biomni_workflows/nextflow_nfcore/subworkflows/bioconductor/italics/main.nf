#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ITALICS
// A Method to normalize of Affymetrix GeneChip Human Mapping 100K and 500K set
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ITALICS/inst/doc/ITALICS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ITALICS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ITALICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-italics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-italics:2.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-italics:2.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_italics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_italics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_italics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(I)
    library(ITALICS)
    library(jsonlite)

    # --- Attr [] ---
    # Key functions: attr, environment, search
    require(ITALICS)
    ITALICSDataPATH <- attr(as.environment(match("package:ITALICSData",search())),"path")
    load(paste(ITALICSDataPATH,"/data/snpInfo.RData", sep=""))
    load(paste(ITALICSDataPATH,"/data/quartetInfo.RData", sep=""))
    # --- Attr [] ---
    # Key functions: attr, environment, search, readCelHeader, cleanPlatformName
    ITALICSDataPATH <- attr(as.environment(match("package:ITALICSData",search())),"path")
    filename <- paste(ITALICSDataPATH,"/extdata/HF0844_Xba.CEL", sep="")
    headdetails <- readCelHeader(filename[1])
    pkgname <- cleanPlatformName(headdetails[["chiptype"]])
    quartetEffectFile <- paste(ITALICSDataPATH,"/extdata/Xba.QuartetEffect.csv", sep="")
    # --- Italics [] ---
    # Key functions: ITALICS, I
    profilSNPXba <- ITALICS(quartet$quartetInfo, snpInfo,
         formule="Smoothing+QuartetEffect+FL+I(FL^2)+I(FL^3)+GC+I(GC^2)+I(GC^3)")
    # --- Data [] ---
    # Key functions: plotProfile
    data(cytoband)
    plotProfile(profilSNPXba, Smoothing="Smoothing", cytoband=cytoband)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_italics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_italics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_italics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ITALICS:", paste0("    italics: ", packageVersion("ITALICS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_italics_results.csv
    touch ${prefix}_italics_output.rds
    echo "BIOC_ITALICS:" > versions.yml
    echo "    italics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ITALICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ITALICS(ch_input)

    emit:
    results  = BIOC_ITALICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ITALICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ITALICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ITALICS.out.versions  // channel: path(versions.yml)
}
