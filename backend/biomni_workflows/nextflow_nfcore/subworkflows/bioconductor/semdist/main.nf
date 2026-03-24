#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SemDist
// This package implements methods to calculate information accretion for a given version of the gene o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SemDist/inst/doc/introduction.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SemDist")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEMDIST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-semdist"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-semdist:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-semdist:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_semdist_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_semdist_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_semdist_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RUMIcurve)
    library(jsonlite)

    # --- Introduction.Rnw:173 176 [] ---
    # Key functions: data
    # Examine built-in IA data
    data("Info_Accretion_mouse_CC", package="SemDist")
    head(IAccr)
    # --- Introduction.Rnw:178 182 [] ---
    # Key functions: computeIA
    ## # Calculate IA, specify evidence codes
    ## # Requires downloading annotation data package
    ## BiocManager::install("org.Hs.eg.db")
    ## IAccr <- computeIA("MF", "human", evcodes=c("EXP", "IC"))
    # --- Introduction.Rnw:189 198 [] ---
    # Key functions: computeIA
    # Calculate IA, specify ontology and annotations
    ontfile <- system.file("extdata", "mfo_ontology.txt",
                            package="SemDist")
    annotations <- system.file("extdata", "MFO_LABELS_TEST.txt",
                                package="SemDist")
    # --- Introduction.Rnw:204 207 [] ---
    # Key functions: computeIA
    ## # Calculate IA, specify ontology
    ## IAccr <- computeIA("MF", "human", specify.ont=TRUE,
    ##          myont=ontfile, specify.annotations=FALSE)
    # --- Introduction.Rnw:229 236 [] ---
    # Key functions: file
    # Sample true, prediction files included with SemDist:
    truefile <- system.file("extdata", "MFO_LABELS_TEST.txt",
                            package="SemDist")
    predfile <- system.file("extdata", "MFO_PREDS_TEST.txt",
                            package="SemDist")
    # --- Introduction.Rnw:245 248 [] ---
    # Key functions: findRUMI
    rumiTable <- findRUMI("MF", "human", 0.75, truefile, predfile)
    avgRU <- mean(rumiTable$RU)
    avgMI <- mean(rumiTable$MI)
    # --- Introduction.Rnw:258 266 [] ---
    # Key functions: findRUMI
    # A sample IA file that comes with the SemDist package.
    myIA <- system.file("extdata", "myIA.rda", package="SemDist")
    load(myIA)
    # "MF" and "human" are present only for naming purposes
    # since IA is taken from myIA.rda
    # --- Introduction.Rnw:278 281 [] ---
    # Key functions: RUMIcurve
    avgRUMIvals <- RUMIcurve("MF", "human", 0.05, truefile, predfile)
    firstset <- avgRUMIvals[[1]]
    plot(firstset$RU, firstset$MI)
    # --- Introduction.Rnw:307 311 [] ---
    # Key functions: RUMIcurve
    rumiout <- RUMIcurve("MF", "human", 0.05, truefile, predfile,
                         add.prec.rec=TRUE, add.weighted=TRUE)
    firstset <- rumiout[[1]]
    plot(firstset$WRU, firstset$WMI)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_semdist_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_semdist_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_semdist_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEMDIST:", paste0("    semdist: ", packageVersion("SemDist"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_semdist_results.csv
    touch ${prefix}_semdist_output.rds
    echo "BIOC_SEMDIST:" > versions.yml
    echo "    semdist: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEMDIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEMDIST(ch_input)

    emit:
    results  = BIOC_SEMDIST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEMDIST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEMDIST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEMDIST.out.versions  // channel: path(versions.yml)
}
