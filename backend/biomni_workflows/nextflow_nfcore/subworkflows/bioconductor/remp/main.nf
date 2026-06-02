#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: REMP
// Machine learning-based tools to predict DNA methylation of locus-specific repetitive elements (RE) b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/REMP/inst/doc/REMP.R
// Upstream  : devtools, knitr
// Downstream: none
//
// Install: BiocManager::install("REMP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-remp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-remp:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-remp:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_remp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_remp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_remp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(REMP)
    library(jsonlite)

    # --- Data Preparation and Grooming [Data Prep] ---
    # Key functions: getGM12878, grooMethy
    GM12878_450k <- getGM12878("450k")
    GM12878_450k <- grooMethy(GM12878_450k)

    # --- Repetitive Element Annotation Initialization [Annotation] ---
    # Key functions: initREMP, saveParcel
    data(Alu.hg19.demo)
    remparcel <- initREMP(
        arrayType = "450k",
        REtype = "Alu",
        annotation.source = "AH",
        genome = "hg19",
        RE = Alu.hg19.demo,
        ncore = 1
    )
    saveParcel(remparcel)

    # --- Repetitive Element Methylation Prediction [Prediction] ---
    # Key functions: remp, details
    remp.res <- remp(
        GM12878_450k,
        REtype = "Alu",
        parcel = remparcel,
        ncore = 1,
        seed = 777
    )
    details(remp.res)

    # --- Quality Control and Aggregation [Filtering] ---
    # Key functions: rempTrim, rempAggregate, details
    remp.res <- rempTrim(remp.res, threshold = 1.7, missingRate = 0.2)
    remp.res <- rempAggregate(remp.res, NCpG = 2)
    details(remp.res)

    # --- Genomic Annotation and Data Extraction [Extraction] ---
    # Key functions: decodeAnnot, rempAnnot, rempB, rempM, rempImp
    remp.res <- decodeAnnot(remp.res)
    annot_info <- rempAnnot(remp.res)
    beta_values <- rempB(remp.res)
    m_values <- rempM(remp.res)
    imp_scores <- rempImp(remp.res)

    # --- Visualization and Profiling [Visualization] ---
    # Key functions: remplot, remprofile, details
    remplot(remp.res, main = "Alu methylation (GM12878)", col = "blue")
    remp.profile <- remprofile(
        GM12878_450k,
        REtype = "Alu",
        annotation.source = "AH",
        genome = "hg19",
        RE = Alu.hg19.demo
    )
    details(remp.profile)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_remp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_remp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_remp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REMP:", paste0("    remp: ", packageVersion("REMP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_remp_results.csv
    touch ${prefix}_remp_output.rds
    echo "BIOC_REMP:" > versions.yml
    echo "    remp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REMP(ch_input)

    emit:
    results  = BIOC_REMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REMP.out.versions  // channel: path(versions.yml)
}
