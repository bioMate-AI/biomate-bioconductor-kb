#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CGEN
// This is a package for analysis of case-control data in genetic epidemiology. It provides a set of st
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CGEN/inst/doc/vignette.R
// Upstream  : cluster
// Downstream: none
//
// Install: BiocManager::install("CGEN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CGEN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cgen"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cgen:3.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cgen:3.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cgen_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cgen_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cgen_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CGEN)
    library(jsonlite)

    # --- Load Data [] ---
    # Key functions: data
    data(Xdata, package="CGEN")
    Xdata[1:5, ]
    # --- logistic [] ---
    # Key functions: logistic
    mainVars <- c("oral.years", "n.children", "age.group_1",
                  "age.group_2", "age.group_3", "age.group_5")
    # --- Wald Test [] ---
    # Key functions: getWaldTest
    getWaldTest(fit, c("BRCA.status", "BRCA.status:oral.years", "BRCA.status:n.children"))
    # --- Getmatchedsets [] ---
    # Key functions: ifelse, daisy, getMatchedSets
    library("cluster")
    size <- ifelse(Xdata$ethnic.group == 3, 3, 4)
    d <- daisy(Xdata[,c("age.group_1","gynSurgery.history","BRCA.history")])
    mx <- getMatchedSets(d, CC=TRUE, NN=TRUE, ccs.var = Xdata$case.control,
    	  strata.var = Xdata$ethnic.group, size = size, fixed = TRUE)
    # --- Xdata [] ---
    # Key functions: cbind
    mx$CC[1:10]
    mx$tblCC
    Xdata <- cbind(Xdata, CCStrat = mx$CC, NNStrat = mx$NN)
    Xdata[1:5,]
    # --- matched [] ---
    # Key functions: matched
    intVars <- ~ oral.years + n.children
    snpVars <- ~ BRCA.status
    fit <- snp.matched(Xdata, "case.control", snp.vars=snpVars,
                         main.vars=intVars, int.vars=intVars,
                         cc.var="CCStrat", nn.var="NNStrat")
    # --- Summary Table 2 [] ---
    # Key functions: getSummary
    getSummary(fit, method = c("CLR", "CCL"))
    # --- Wald Test 2 [] ---
    # Key functions: getWaldTest
    getWaldTest(fit$HCL, c( "BRCA.status" , "BRCA.status:oral.years" , "BRCA.status:n.children"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cgen_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cgen_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cgen_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CGEN:", paste0("    cgen: ", packageVersion("CGEN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cgen_results.csv
    touch ${prefix}_cgen_output.rds
    echo "BIOC_CGEN:" > versions.yml
    echo "    cgen: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CGEN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CGEN(ch_input)

    emit:
    results  = BIOC_CGEN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CGEN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CGEN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CGEN.out.versions  // channel: path(versions.yml)
}
