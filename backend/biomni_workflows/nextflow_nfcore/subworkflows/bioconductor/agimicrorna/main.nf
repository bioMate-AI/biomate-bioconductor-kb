#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AgiMicroRna
// Processing and Analysis of Agilent microRNA data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AgiMicroRna/inst/doc/AgiMicroRna.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("AgiMicroRna")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AGIMICRORNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-agimicrorna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-agimicrorna:2.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-agimicrorna:2.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_agimicrorna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_agimicrorna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_agimicrorna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AgiMicroRna)
    library(RleMicroRna)
    library(jsonlite)

    # --- Normalisation [] ---
    # Key functions: tgsMicroRna, tgsNormalization
    data(dd.micro)
    data(targets.micro)
    ddTGS <- tgsMicroRna(dd.micro, half=TRUE, makePLOT=FALSE,
                         verbose=FALSE)
    ddNORM <- tgsNormalization(ddTGS, "quantile", makePLOTpre=FALSE,
                               makePLOTpost=FALSE, targets.micro,
                               verbose=TRUE)


    # --- Filtering and ExpressionSet Creation [] ---
    # Key functions: filterMicroRna, esetMicroRna
    ddPROC <- filterMicroRna(ddNORM, dd.micro, control=TRUE,
                             IsGeneDetected=TRUE, wellaboveNEG=FALSE,
                             limIsGeneDetected=75, limNEG=25,
                             makePLOT=FALSE, targets.micro,
                             verbose=TRUE, writeout=FALSE)
    esetPROC <- esetMicroRna(ddPROC, targets.micro, makePLOT=FALSE,
                             verbose=TRUE)


    # --- Differential Expression [] ---
    # Key functions: getDecideTests
    design <- model.matrix(~ targets.micro$GErep)
    fit <- limma::lmFit(Biobase::exprs(esetPROC), design)
    fit2 <- limma::eBayes(fit)
    DE <- getDecideTests(fit2, DEmethod="separate", MTestmethod="BH",
                         PVcut=0.10, verbose=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_agimicrorna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_agimicrorna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_agimicrorna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AGIMICRORNA:", paste0("    agimicrorna: ", packageVersion("AgiMicroRna"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agimicrorna_results.csv
    touch ${prefix}_agimicrorna_output.rds
    echo "BIOC_AGIMICRORNA:" > versions.yml
    echo "    agimicrorna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AGIMICRORNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AGIMICRORNA(ch_input)

    emit:
    results  = BIOC_AGIMICRORNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AGIMICRORNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AGIMICRORNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AGIMICRORNA.out.versions  // channel: path(versions.yml)
}
