#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: affyContam
// structured corruption of cel file data to demonstrate QA effectiveness
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/affyContam/inst/doc/affyContam.R
// Upstream  : SpikeIn, affy, affyMvout, affydata, limma
// Downstream: none
//
// Install: BiocManager::install("affyContam")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYCONTAM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affycontam"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affycontam:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affycontam:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affycontam_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affycontam_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affycontam_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(affyContam)
    library(jsonlite)

    # --- Lkd [] ---
    # Key functions: image
    library(affydata)
    data(Dilution)
    image(Dilution[,1])
    # --- Dodef [] ---
    # Key functions: setCircRegion
    library(affyContam)
    dilc = setCircRegion(Dilution, chip=1)
    # --- Getl [] ---
    # Key functions: data
    ## library(affyMvout)
    ## library(affy)
    ## library(SpikeIn)
    ## data(SpikeIn133)
    ## library(mdqc)
    # --- Doperm [] ---
    # Key functions: rma, exprs, featureNames
    ## s12 = SpikeIn133[,1:12]
    ## s12rma = rma(s12)
    ## mads = apply(exprs(s12rma),1,mad)
    ## kp = which(mads > quantile(mads,.95))
    ## kppn = featureNames(s12rma)[kp]
    # --- Cod [] ---
    # Key functions: exprs, lmFit, eBayes, contFun

    # --- Ddd [] ---
    # Key functions: fullrun
    ## ff = fullrun( s12, s12rma, setCircRegion, kppn, mostmr, chips=1:2 )
    # --- Scr [] ---
    # Key functions: annotation, grid
    ## scr.40 = function (x, chip = 1, center = c(150, 150), rad = 75, vals = 30,
    ##     valgen = NULL)
    # --- Scr2 [] ---
    # Key functions: annotation, grid
    ## scr.20k = function (x, chip = 1, center = c(500, 500), rad = 75, vals = 30000,
    ##     valgen = NULL)
    # --- Dov [] ---
    # Key functions: getCircRegion, setCircRegion
    ## incvarCircRegion = function(x, chip=1, center=c(150,500), rad=100, fac=3) {
    ##  tmp = fac*getCircRegion(x, chip, center, rad)
    ##  setCircRegion(x, chip, center, rad, vals=tmp)
    ## }
    # --- Dov [] ---
    # Key functions: getRectRegion, setRectRegion
    ## incvarRectRegion = function(x, chip=1, xinds=350:700, yinds=1:700, fac=3) {
    ##  tmp = fac*getRectRegion(x, chip, xinds, yinds)
    ##  setRectRegion(x, chip, xinds, yinds, vals=tmp)
    ## }
    # --- Compo [] ---
    # Key functions: 40, 20k, incvarCircRegion, incvarRectRegion, image, off
    ## tryout = scr.40(s12)
    ## tryout = scr.20k(tryout)
    ## tryout = incvarCircRegion(tryout)
    ## fin = incvarRectRegion(tryout)
    ## png(file="lkcomp.png")
    # --- Doruns [] ---
    # Key functions: fullrun
    ## d1b = fullrun( s12, s12rma, scr.40, kppn, mostmr, chips=1 )
    ## save(d1b, file="d1b.rda")
    ## d2b = fullrun( s12, s12rma, scr.40, kppn, mostmr, chips=1:2 )
    ## save(d2b, file="d2b.rda")
    ## d3b = fullrun( s12, s12rma, scr.40, kppn, mostmr, chips=c(1:2,11) )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affycontam_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affycontam_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affycontam_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFYCONTAM:", paste0("    affycontam: ", packageVersion("affyContam"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affycontam_results.csv
    touch ${prefix}_affycontam_output.rds
    echo "BIOC_AFFYCONTAM:" > versions.yml
    echo "    affycontam: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFYCONTAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFYCONTAM(ch_input)

    emit:
    results  = BIOC_AFFYCONTAM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFYCONTAM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFYCONTAM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFYCONTAM.out.versions  // channel: path(versions.yml)
}
