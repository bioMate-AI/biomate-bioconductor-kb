#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ALDEx2
// A differential abundance analysis for the comparison of two or more conditions. Useful for analyzing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ALDEx2/inst/doc/ALDEx2_vignette.R
// Upstream  : cowplot, ggpattern, ggplot2, tidyverse
// Downstream: omicplotR
//
// Install: BiocManager::install("ALDEx2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALDEX2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aldex2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aldex2:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aldex2:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_aldex2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aldex2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aldex2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ALDEx2)
    library(jsonlite)


    # --- Basecode [] ---
    # Key functions: load_all, rep, aldex
    # this is all the data generated once
    # all other data will be displayed but not evaluated

    ##### RECODE THE SOURCE PRIOR TO PUSHING TO BIOCONDUCTOR
    # devtools::load_all('~/Documents/0_git/ALDEx_bioc')
    library(ALDEx2)
    set.seed(11)

    #### BASIC ALDEx2
    #subset only the last 400 features for efficiency
    data(selex)
    selex.sub <- selex[1200:1600,]
    conds <- c(rep("NS", 7), rep("S", 7))
    x.aldex <- aldex(selex.sub, conds, mc.samples=16, test="t", effect=TRUE, 
      include.sample.summary=FALSE, denom="all", verbose=FALSE, paired.test=FALSE, gamma=NULL)

    # --- Ci [] ---
    # Key functions: sign, par, abline, grey, red, blue
    sgn <- sign(x.effect$effect.low) == sign(x.effect$effect.high)
    par(mfrow=c(1,2))
    plot(x.effect$rab.all, x.effect$diff.btw, pch=19, cex=0.3, col="grey", xlab="Abundance", ylab="Difference", main="Bland-Altman")
    points(x.effect$rab.all[abs(x.effect$effect) >=2], x.effect$diff.btw[abs(x.effect$effect) >=2], pch=19, cex=0.5, col="red")
    points(x.effect$rab.all[sgn], x.effect$diff.btw[sgn], cex=0.7, col="blue")

    plot(x.effect$diff.win, x.effect$diff.btw, pch=19, cex=0.3, col="grey",xlab="Dispersion", ylab="Difference", main="Effect")
    points(x.effect$diff.win[abs(x.effect$effect) >=2], x.effect$diff.btw[abs(x.effect$effect) >=2], pch=19, cex=0.5, col="red")
    points(x.effect$diff.win[sgn], x.effect$diff.btw[sgn], cex=0.7, col="blue")
    abline(0,2, lty=2, col="grey")
    abline(0,-2, lty=2, col="grey")

    # --- Glm [] ---
    # Key functions: aldex.glm.plot
    # NEW plot the glm.test and glm.eff data for particular contrasts
    aldex.glm.plot(glm.test, eff=glm.eff, contrast='B', type='MW', test='fdr')

    # --- Fig=true [] ---
    # Key functions: rgb, abline
    # identify which values are significant in both the t-test and glm tests
    found.by.all <- which(x.all$we.eBH < 0.05 & x.all$wi.eBH < 0.05)

    # identify which values are significant in fewer than all tests
    found.by.one <- which(x.all$we.eBH < 0.05 | x.all$wi.eBH < 0.05)

    # plot the within and between variation of the data
    plot(x.all$diff.win, x.all$diff.btw, pch=19, cex=0.3, col=rgb(0,0,0,0.3),
     xlab="Dispersion", ylab="Difference")
    points(x.all$diff.win[found.by.one], x.all$diff.btw[found.by.one], pch=19,
     cex=0.7, col=rgb(0,0,1,0.5))
    points(x.all$diff.win[found.by.all], x.all$diff.btw[found.by.all], pch=19,
     cex=0.7, col=rgb(1,0,0,1))
    abline(0,1,lty=2)
    abline(0,-1,lty=2)

    # --- Scale [] ---
    # Key functions: rep, aldex.clr, aldex.effect, aldex.makeScaleMatrix
    set.seed(11)
    data(synth2)
    # basic ALDEx2
    blocks <- c(rep("N", 10),rep("S", 10))
    x <- aldex.clr(synth2, blocks, gamma=NULL)
    x.e <- aldex.effect(x)

    # Add in asymmetry and scale variance
    # gamma can be smaller for the same output dispersion
    # in the full scale model built here
    # make a base scale for group 1 and 2
    mu.vec = c(log2(rep(1,10)), log2(rep(1.02,10)))
    scale_samples <- aldex.makeScaleMatrix(gamma=0.25, mu=mu.vec, 
      conditions=blocks) 


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aldex2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aldex2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aldex2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALDEX2:", paste0("    aldex2: ", packageVersion("ALDEx2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aldex2_results.csv
    touch ${prefix}_aldex2_output.rds
    echo "BIOC_ALDEX2:" > versions.yml
    echo "    aldex2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALDEX2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALDEX2(ch_input)

    emit:
    results  = BIOC_ALDEX2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALDEX2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALDEX2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALDEX2.out.versions  // channel: path(versions.yml)
}
