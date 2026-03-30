#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metahdep
// Tools for meta-analysis in the presence of hierarchical (and/or sampling) dependence, including with
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metahdep/inst/doc/metahdep.R
// Upstream  : ALLMLL, AnnotationDbi, SpikeInSubset
// Downstream: none
//
// Install: BiocManager::install("metahdep")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAHDEP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metahdep"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metahdep:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metahdep:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metahdep_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metahdep_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metahdep_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FEMA)
    library(HBLM)
    library(REMA)
    library(jsonlite)

    # --- Unlist [] ---
    # Key functions: unlist, mget, mappedkeys, frame
    ## library(AnnotationDbi)
    ## library(hgu133a.db); library(hgu133b.db); library(hgu95a.db); library(hgu95av2.db)
    ## EID.hgu133a <- unlist(mget(mappedkeys(hgu133aENTREZID),hgu133aENTREZID))
    ## EID.hgu133b <- unlist(mget(mappedkeys(hgu133bENTREZID),hgu133bENTREZID))
    ## EID.hgu95a <- unlist(mget(mappedkeys(hgu95aENTREZID),hgu95aENTREZID))
    # --- Data [] ---
    # Key functions: es, frame
    ## library(ALLMLL); data(MLL.A)
    ## ES.exp1 <- getPLM.es(abatch=MLL.A, trt1=list(c(1:5),c(6:10)), trt2=list(c(11:15),c(16:20)), sub.gn=use.hgu133a.gn, covariates=data.frame(Tissue=c(0,1)), dep.grp=1 )
    # --- Data [] ---
    # Key functions: sample
    library(metahdep)
    data(HGU.newnames)
    data(HGU.prep.list)
    set.seed(123)
    gene.subset <- sample(HGU.newnames$new.name, 50)
    # --- Metahdep [] ---
    # Key functions: metahdep
    FEMA <- metahdep(HGU.prep.list, method="FEMA", genelist=gene.subset, center.X=TRUE)
    # --- Frame [] ---
    # Key functions: frame
    pvals <- data.frame(FEMA=FEMA$Intercept.pval, REMA=REMA$Intercept.pval, REMA.ds=REMA.ds$Intercept.pval,
      HBLM=HBLM$Intercept.pval, HBLM.ds=HBLM.ds$Intercept.pval)
    plot(pvals, main='Comparison of Intercept P-values from Meta-Analysis',pch=16,cex=.5)
    # --- Data [] ---
    # Key functions: data
    library(metahdep)
    data(gloss)
    gloss.Table1
    # --- Diag [] ---
    # Key functions: diag
    pE <- c.correct^2*dfE/(dfE-2)
    var.theta <- pE*(1/n2+1/n1) + (pE-1)*theta^2
    V <- diag(var.theta)
    # --- List [] ---
    # Key functions: FEMA, diag, REMA, HBLM
    # define dependence groups for delta-splitting models
    dep.groups <- list( c(2,3,4,5), c(10,11,12) )
    # fixed effects meta-analysis
    FEMA.indep <- metahdep.FEMA(theta, diag(diag(V)), X, center.X=TRUE)
    FEMA.dep <- metahdep.FEMA(theta, V, X, center.X=TRUE)
    # --- Round [] ---
    # Key functions: frame
    ## r1 <- round(c(FEMA.indep$beta.hats[1], FEMA.indep$beta.hat.p.values[1],NA,NA),4)
    ## r2 <- round(c(FEMA.dep$beta.hats[1], FEMA.dep$beta.hat.p.values[1],NA,NA),4)
    ## r3 <- round(c(REMA.indep$beta.hats[1], REMA.indep$beta.hat.p.values[1], REMA.indep$tau2.hat, NA),4)
    ## r4 <- round(c(REMA.dep$beta.hats[1], REMA.dep$beta.hat.p.values[1], REMA.dep$tau2.hat, NA),4)
    ## r5 <- round(c(REMA.ds$beta.hats[1], REMA.ds$beta.hat.p.values[1], REMA.ds$tau2.hat, REMA.ds$varsigma.hat),4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metahdep_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metahdep_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metahdep_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METAHDEP:", paste0("    metahdep: ", packageVersion("metahdep"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metahdep_results.csv
    touch ${prefix}_metahdep_output.rds
    echo "BIOC_METAHDEP:" > versions.yml
    echo "    metahdep: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METAHDEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METAHDEP(ch_input)

    emit:
    results  = BIOC_METAHDEP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METAHDEP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METAHDEP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METAHDEP.out.versions  // channel: path(versions.yml)
}
