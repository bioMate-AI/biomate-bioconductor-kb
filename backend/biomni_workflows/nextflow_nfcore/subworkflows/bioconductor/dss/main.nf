#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DSS
// DSS is an R library performing differntial analysis for count-based sequencing data. It detectes dif
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DSS/inst/doc/DSS.R
// Upstream  : bsseq, edgeR
// Downstream: DeMixT
//
// Install: BiocManager::install("DSS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DSS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dss"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dss:2.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dss:2.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dss_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dss_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dss_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DE)
    library(jsonlite)

    # --- Estnormfactors [] ---
    # Key functions: estNormFactors
    ---------------------------------------------------------------------
    seqData = estNormFactors(seqData)
    # --- Estdispersion [] ---
    # Key functions: estDispersion
    ---------------------------------------------------------------------
    seqData = estDispersion(seqData)
    # --- Waldtest [] ---
    # Key functions: waldTest
    ---------------------------------------------------------------------
    result=waldTest(seqData, 0, 1)
    head(result,5)
    # --- Matrix [] ---
    # Key functions: rpois, DE
    ---------------------------------------------------------------------
    counts = matrix(rpois(600, 10), ncol=6)
    designs = c(0,0,0,1,1,1)
    result = DSS.DE(counts, designs)
    head(result)
    # --- Newseqcountset [] ---
    # Key functions: newSeqCountSet, frame, estNormFactors, estDispersion
    ---------------------------------------------------------------------
    seqData = newSeqCountSet(counts, as.data.frame(X))
    seqData = estNormFactors(seqData)
    seqData = estDispersion(seqData)
    # --- Glmfit [] ---
    # Key functions: glmFit, dispersion
    ---------------------------------------------------------------------
    fit.edgeR = glmFit(counts, X, dispersion=dispersion(seqData))
    # --- Glmlrt [] ---
    # Key functions: glmLRT
    ---------------------------------------------------------------------
    lrt.edgeR = glmLRT(glmfit=fit.edgeR, coef=2)
    head(lrt.edgeR$table)
    # --- Calldml [] ---
    # Key functions: callDML
    ---------------------------------------------------------------------
      dmls = callDML(dmlTest, p.threshold=0.001)
      head(dmls)
    # --- Calldmr [] ---
    # Key functions: callDMR
    ---------------------------------------------------------------------
    dmrs = callDMR(dmlTest, p.threshold=0.01)
    head(dmrs)
    # --- Rep [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    Strain = rep(c("A", "B", "C"), 4)
    Sex = rep(c("M", "F"), each=6)
    design = data.frame(Strain,Sex)
    design
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(RRBS)
    RRBS
    design
    # --- Multifactor [] ---
    # Key functions: multiFactor
    ---------------------------------------------------------------------
    DMLfit = DMLfit.multiFactor(RRBS, design=design, formula=~case+cell+case:cell)
    # --- Calldmr [] ---
    # Key functions: callDMR
    ---------------------------------------------------------------------
    callDMR(DMLtest.cell, p.threshold=0.05)
    # --- Multifactor [] ---
    # Key functions: multiFactor
    ---------------------------------------------------------------------
    ## fit a model with additive effect only
    DMLfit = DMLfit.multiFactor(RRBS, design, ~case+cell)
    ## test case effect
    test1 = DMLtest.multiFactor(DMLfit, coef=2)
    # --- Factor [] ---
    # Key functions: factor, frame
    ---------------------------------------------------------------------
    Treatment = factor(rep(c("Control","Treated"), 3))
    pair = factor( rep(1:3, each=2) )
    design = data.frame(Treatment, pair)
    design

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dss_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dss_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dss_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DSS:", paste0("    dss: ", packageVersion("DSS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dss_results.csv
    touch ${prefix}_dss_output.rds
    echo "BIOC_DSS:" > versions.yml
    echo "    dss: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DSS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DSS(ch_input)

    emit:
    results  = BIOC_DSS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DSS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DSS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DSS.out.versions  // channel: path(versions.yml)
}
