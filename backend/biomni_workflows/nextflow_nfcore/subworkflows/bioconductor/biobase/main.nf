#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Biobase
// Functions that are needed by many other packages or which replace R functions.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Biobase/inst/doc/BiobaseDevelopment.R
// Upstream  : BiocManager, convert
// Downstream: ACME, affy, affycomp, affyContam, affycoretools
//
// Install: BiocManager::install("Biobase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biobase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biobase:2.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biobase:2.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biobase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biobase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biobase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Biobase)
    library(jsonlite)

    # --- Getclass [] ---
    # Key functions: getClass
    ---------------------------------------------------------------------
    getClass("eSet")
    # --- Getvalidity [] ---
    # Key functions: getValidity, getClass
    ---------------------------------------------------------------------
    getValidity(getClass("eSet"))
    # --- Getclass [] ---
    # Key functions: getClass, getValidity
    ---------------------------------------------------------------------
    getClass("ExpressionSet")
    getValidity(getClass("ExpressionSet"))
    # --- Setclass [] ---
    # Key functions: setClass
    ---------------------------------------------------------------------
    setClass("SwirlSet", contains="eSet")
    # --- Setmethod [] ---
    # Key functions: setMethod, assayDataNew, new, missing, any
    ---------------------------------------------------------------------
    # --- Setvalidity [] ---
    # Key functions: setValidity, assayDataValidMembers, assayData
    ---------------------------------------------------------------------
    setValidity("SwirlSet", function(object) {
        assayDataValidMembers(assayData(object), c("R", "G", "Rb", "Gb"))
    })
    # --- Data [] ---
    # Key functions: classVersion, updateObject
    ---------------------------------------------------------------------
    data(sample.ExpressionSet)
    classVersion(sample.ExpressionSet)
    obj <- updateObject(sample.ExpressionSet)
    # --- Iscurrent [] ---
    # Key functions: isCurrent
    ---------------------------------------------------------------------
    isCurrent(sample.ExpressionSet)[c("eSet", "ExpressionSet")]
    # --- Setclass [] ---
    # Key functions: setClass, prototype, new, classVersion
    ---------------------------------------------------------------------
    setClass("MySet",
             contains = "eSet",
             prototype = prototype(new("VersionedBiobase",
                                   versions=c(classVersion("eSet"), MySet="1.0.0"))))
    # --- Setclass [] ---
    # Key functions: setClass, prototype, new, classVersion, isCurrent
    ---------------------------------------------------------------------
    # --- Setmethod [] ---
    # Key functions: setMethod, signature, updateObject, callNextMethod, isCurrent
    ---------------------------------------------------------------------
    # --- Classversion [] ---
    # Key functions: classVersion, updateObject
    ---------------------------------------------------------------------
    classVersion(updateObject(obj))
    # --- Classversion [] ---
    # Key functions: classVersion, new
    ---------------------------------------------------------------------
    classVersion(new("AnnotatedDataFrame"))
    # --- Setclass [] ---
    # Key functions: setClass, prototype, new, classVersion
    ---------------------------------------------------------------------
    setClass("SwirlSet", contains = "eSet",
             prototype = prototype(
                 new("VersionedBiobase",
                     versions=c(classVersion("eSet"), SwirlSet="1.0.0"))))
    # --- Classversion [] ---
    # Key functions: classVersion, updateObject
    ---------------------------------------------------------------------
     classVersion(updateObject(obj))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biobase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biobase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biobase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOBASE:", paste0("    biobase: ", packageVersion("Biobase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biobase_results.csv
    touch ${prefix}_biobase_output.rds
    echo "BIOC_BIOBASE:" > versions.yml
    echo "    biobase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOBASE(ch_input)

    emit:
    results  = BIOC_BIOBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOBASE.out.versions  // channel: path(versions.yml)
}
