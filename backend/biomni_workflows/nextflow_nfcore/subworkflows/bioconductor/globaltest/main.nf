#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: globaltest
// The global test tests groups of covariates (or features) for association with a response variable. T
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/globaltest/inst/doc/GlobalTest.R
// Upstream  : MASS, boot, golubEsets, gss, lungExpression
// Downstream: GlobalAncova
//
// Install: BiocManager::install("globaltest")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLOBALTEST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-globaltest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-globaltest:5.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-globaltest:5.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_globaltest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_globaltest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_globaltest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Surv)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: data
    library(golubEsets)
    data(Golub_Train)
    # --- Quality control and filtering [] ---
    # Key functions: exprs, vsn2
    library(vsn)
    exprs(Golub_Train) <- exprs(vsn2(Golub_Train))
    # --- Data normalization [] ---
    # Key functions: gtLI, scale
    gtLI(medv~., data=Boston, standardize=T)
    gtLI(medv~., data=scale(Boston))
    # --- Rnorm analysis [] ---
    # Key functions: rnorm, gt, value, score, result, size, rpois, rexp
    covs=c("Age","Number","Start")
    bd=c(3,3,3);ni=c(10,10,10);po=c(2,2,2);cs<-c(0,cumsum(bd+ni-po))
    X0<-model.matrix(fit0)[,]
    combZ<-do.call(cbind,lapply(1:length(covs),function(x){reparamZ(bbase(kyphosis[,covs[x]], nint=ni[x], bdeg=bd[x]), pord=po[x])}))
    comb<-gt(Kyphosis~., alternative=combZ, data = kyphosis, model="logistic")
    # --- Clustering and classification [] ---
    # Key functions: hclust, dist, inheritance
    hc <- hclust(dist(t(X)))
    resHC <- inheritance(res, hc)
    resHC
    # --- Statistical modeling and testing [] ---
    # Key functions: reparamZ, lm, glm, gtPS, gtKS, sterms
    fit0<-lm(ph~lat*lon, data=LakeAcidity)
    res<-gtPS(fit0, covs=c("lat","lon"), interact=TRUE, data=LakeAcidity)
    res@result
    sterms(res)
    # --- Visualization and reporting [] ---
    # Key functions: draw
    ## draw(res, interactive=TRUE)
    ## legend <- draw(res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_globaltest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_globaltest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_globaltest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GLOBALTEST:", paste0("    globaltest: ", packageVersion("globaltest"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_globaltest_results.csv
    touch ${prefix}_globaltest_output.rds
    echo "BIOC_GLOBALTEST:" > versions.yml
    echo "    globaltest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GLOBALTEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GLOBALTEST(ch_input)

    emit:
    results  = BIOC_GLOBALTEST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GLOBALTEST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GLOBALTEST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GLOBALTEST.out.versions  // channel: path(versions.yml)
}
