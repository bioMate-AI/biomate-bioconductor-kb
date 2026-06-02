#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DTA
// Dynamic Transcriptome Analysis (DTA) can monitor the cellular response to perturbations with higher 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DTA/inst/doc/DTA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DTA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DTA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dta"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dta:2.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dta:2.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dta_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dta_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dta_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DTA)
    library(jsonlite)

    # --- Estimation Procedure [] ---
    # Key functions: estimate
    res = DTA.estimate(Sc.phenomat,Sc.datamat,Sc.tnumber,
    ccl = 150,mRNAs = 60000,reliable = Sc.reliable,
    condition = "real_data",save.plots = TRUE,notinR = TRUE,folder = ".")
    # --- Plot Half Lives/Sythesis Rates [] ---
    # Key functions: data
    data(Sc.ribig.ensg)
    data(Sc.rpg.ensg)
    data(Sc.tf.ensg)
    data(Sc.stress.ensg)
    # --- Plot Half Lives/Sythesis Rates [] ---
    # Key functions: ellipsescatter, it

    # --- Estimation Procedure [] ---
    # Key functions: estimate
    res.nobias = DTA.estimate(Sc.phenomat,Sc.datamat,Sc.tnumber,
    ccl = 150, mRNAs = 60000,reliable = Sc.reliable,save.plots = TRUE,
    notinR = TRUE,folder = ".",bicor = FALSE,condition="no_bias_correction")
    # --- Creating Simulation Object [] ---
    # Key functions: generate
    sim.object = DTA.generate(timepoints=rep(c(6,12),2))
    # --- Estimation Procedure For Simulated Data [] ---
    # Key functions: estimate
    res.sim = DTA.estimate(ratiomethod = "bias",save.plots = TRUE,
    notinR = TRUE,folder = ".",simulation = TRUE,sim.object = sim.object,
    condition = "simulation")
    # --- Loading Miller2011Dynamic [] ---
    # Key functions: data
    data(Miller2011dynamic)
    # --- Estimation Procedure [] ---
    # Key functions: estimate
    timecourse.res = DTA.dynamic.estimate(Sc.phenomat.dynamic,Sc.datamat.dynamic,
    Sc.tnumber,ccl = 150,mRNAs = 60000,reliable = Sc.reliable.dynamic,
    LtoTratio = rep(0.1,7),save.plots = TRUE,notinR = TRUE,folder = ".",
    condition = "timecourse")
    # --- Creating Timecourse Simulation [] ---
    # Key functions: rf, pmax, rnorm
    nrgenes = 5000
    truesynthesisrates = rf(nrgenes,5,5)*18
    steady = rep(1,nrgenes)
    shock = 1/pmax(rnorm(nrgenes,mean = 8,sd = 4),1)
    induction = pmax(rnorm(nrgenes,mean = 8,sd = 4),1)
    # --- Creating Timecourse Simulation Object [] ---
    # Key functions: generate
    timecourse.sim.object = DTA.dynamic.generate(duration = 36,lab.duration = 6,
    nrgenes = nrgenes,mu.values.mat = mu.values.mat,mu.breaks.mat = mu.breaks.mat,
    lambda.values.mat = lambda.values.mat,lambda.breaks.mat = lambda.breaks.mat)
    # --- Estimation Procedure For Simulated Timecourse Data [] ---
    # Key functions: estimate
    timecourse.res.sim = DTA.dynamic.estimate(save.plots = TRUE,notinR = TRUE,
    simulation = TRUE,sim.object = timecourse.sim.object,ratiomethod = "tls",
    folder = ".",condition = "simulation_timecourse",check = FALSE)
    # --- Loading Doelken2008 [] ---
    # Key functions: data
    ## data(Doelken2008)
    # --- Mm Map Tnumber [] ---
    # Key functions: it
    ## Mm.tnumber = DTA.map.it(Mm.tnumber,Mm.enst2ensg)
    # --- Mm Dta Estimation Procedure [] ---
    # Key functions: estimate
    ## res = DTA.estimate(Mm.phenomat,Mm.datamat,Mm.tnumber,
    ## ccl = 24*60,reliable = Mm.reliable,ratiomethod = "tls")
    # --- Hs Map Tnumber [] ---
    # Key functions: it
    ## Hs.tnumber = DTA.map.it(Hs.tnumber,Hs.enst2ensg)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dta_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dta_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dta_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DTA:", paste0("    dta: ", packageVersion("DTA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dta_results.csv
    touch ${prefix}_dta_output.rds
    echo "BIOC_DTA:" > versions.yml
    echo "    dta: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DTA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DTA(ch_input)

    emit:
    results  = BIOC_DTA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DTA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DTA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DTA.out.versions  // channel: path(versions.yml)
}
