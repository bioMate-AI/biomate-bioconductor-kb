#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EBarrays
// EBarrays provides tools for the analysis of replicated/unreplicated microarray data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EBarrays/inst/doc/vignette.R
// Upstream  : none
// Downstream: EBcoexpress, gaga, geNetClassifier
//
// Install: BiocManager::install("EBarrays")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBARRAYS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ebarrays"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ebarrays:2.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ebarrays:2.70.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ebarrays_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ebarrays_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ebarrays_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EBarrays)
    library(jsonlite)

    # --- Readpattern [] ---
    # Key functions: ebPatterns
    pattern <- ebPatterns(c("1, 1, 1, 1, 1, 1, 1, 1, 1, 1",
                            "1, 1, 1, 1, 1, 2, 2, 2, 2, 2"))
    pattern
    # --- eb Patterns [] ---
    # Key functions: ebPatterns
    pattern <- ebPatterns(c("1,1,1,0,0,0,0,0,0,0","1,2,2,0,0,0,0,0,0,0"))
    pattern
    # --- Emfit [] ---
    # Key functions: emfit, postprob, fun
    gg.em.out <- emfit(gould, family = "GG", hypotheses = pattern,
                       num.iter = 10)
    gg.em.out
    gg.post.out <- postprob(gg.em.out, gould)$pattern
    gg.threshold <- crit.fun(gg.post.out[,1], 0.05)
    # --- Ebpatterns [] ---
    # Key functions: ebPatterns
    pattern4 <- ebPatterns(c("1, 1, 1, 1, 1, 1, 1, 1, 1, 1",
                             "1, 2, 2, 2, 2, 2, 2, 2, 2, 2",
                             "1,2,2,1,1,1,1,1,2,2",
                             "1,1,1,1,1,1,1,1,2,2"))
    pattern4
    # --- Fourgroups [] ---
    # Key functions: emfit, postprob, fun
    gg4.em.out <- emfit(gould, family = "GG", pattern4,
                        num.iter = 10)
    gg4.em.out
    gg4.post.out <- postprob(gg4.em.out, gould)$pattern
    gg4.threshold2 <- crit.fun(1-gg4.post.out[,2], 0.05)
    # --- Checkccv [] ---
    # Key functions: checkCCV
    checkCCV(gould[,1:3])
    # --- Qqplotgamma [] ---
    # Key functions: checkModel
    print(checkModel(gould, gg.em.out, model = "gamma", nb = 50))
    # --- Qqplotlnorm [] ---
    # Key functions: checkModel
    print(checkModel(gould, lnn.em.out, model = "lognormal", nb = 50))
    # --- Qqplotlnnmv [] ---
    # Key functions: checkModel
    print(checkModel(gould, lnnmv.em.out, model = "lnnmv", nb = 50,
    		 groupid = c(1,2,2,0,0,0,0,0,0,0)))
    # --- Ggmarg [] ---
    # Key functions: plotMarginal
    print(plotMarginal(gg.em.out, gould))
    # --- Lnnmarg [] ---
    # Key functions: plotMarginal
    print(plotMarginal(lnn.em.out, gould))
    # --- Varsqqplotlnnmv [] ---
    # Key functions: checkVarsQQ
    print(checkVarsQQ(gould, groupid = c(1,2,2,0,0,0,0,0,0,0)))
    # --- Varsmarglnnmv [] ---
    # Key functions: checkVarsMar
    print(checkVarsMar(gould, groupid = c(1,2,2,0,0,0,0,0,0,0),
                       nint=2000, xlim=c(-0.1, 0.5)))
    # --- plot Marginal [] ---
    # Key functions: plotMarginal
    print(plotMarginal(gg4.em.out, data = gould))
    # --- Varsmarglnnmv4 [] ---
    # Key functions: checkVarsMar
    print(checkVarsMar(gould, groupid = c(1,2,2,3,3,3,3,3,4,4),
          	           nint=2000, xlim=c(-0.1, 0.5)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ebarrays_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ebarrays_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ebarrays_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EBARRAYS:", paste0("    ebarrays: ", packageVersion("EBarrays"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ebarrays_results.csv
    touch ${prefix}_ebarrays_output.rds
    echo "BIOC_EBARRAYS:" > versions.yml
    echo "    ebarrays: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EBARRAYS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EBARRAYS(ch_input)

    emit:
    results  = BIOC_EBARRAYS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EBARRAYS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EBARRAYS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EBARRAYS.out.versions  // channel: path(versions.yml)
}
