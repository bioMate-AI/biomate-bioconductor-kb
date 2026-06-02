#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: paircompviz
// This package provides visualization of the results from the multiple (i.e. pairwise) comparison test
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/paircompviz/inst/doc/vignette.R
// Upstream  : multcomp, plyr, reshape, rpart, xtable
// Downstream: none
//
// Install: BiocManager::install("paircompviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAIRCOMPVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-paircompviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-paircompviz:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-paircompviz:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_paircompviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_paircompviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_paircompviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(paircompviz)
    library(jsonlite)

    # --- Test [] ---
    # Key functions: test
    pairwise.t.test(cholesterol$response, cholesterol$trt)
    # --- Cholesterolhasse [] ---
    # Key functions: paircomp
    paircomp(obj=cholesterol$response, grouping=cholesterol$trt, test="t")
    # --- Bonfer [] ---
    # Key functions: paircomp
    paircomp(InsectSprays$count, InsectSprays$spray, test="t",
               compress=TRUE, p.adjust.method="bonferroni")
    # --- Tukeyhasse [] ---
    # Key functions: glht, cld, aov, mcp, paircomp
    library(rpart)       # for car90 dataset
      library(multcomp)    # for glht() and cld() functions
      aovR <- aov(Price ~ Type, data = car90)
      glhtR <- glht(aovR, linfct = mcp(Type = "Tukey"))
      paircomp(glhtR, compress=FALSE)
    # --- Tukeycld [] ---
    # Key functions: cld
    cldR <- cld(glhtR)
      par(mar=c(4, 3, 5, 1))
      plot(cldR)
    # --- Nocompress [] ---
    # Key functions: paircomp
    paircomp(InsectSprays$count, InsectSprays$spray, test="t",
               compress=FALSE)
    # --- Compress [] ---
    # Key functions: paircomp
    paircomp(InsectSprays$count, InsectSprays$spray, test="t",
               compress=TRUE)
    # --- Data [] ---
    # Key functions: test
    data("brokentrans")
      tapply(brokentrans$x, brokentrans$g, mean)
      pairwise.t.test(brokentrans$x, brokentrans$g, pool.sd=FALSE)
    # --- Csv [] ---
    # Key functions: csv, element, omit, factor, mapvalues, levels
    library(plyr)
      experiment <- read.csv("result.csv")
      experiment[!is.element(experiment$error, c("broken", "ok")), "error"] <- NA
      experiment <- na.omit(experiment)
      experiment$error <- factor(experiment$error)
    # --- Frame [] ---
    # Key functions: frame, xtable, cast
    library(reshape)
      ttt <- as.data.frame(table(experiment[, c("test", "error")]) )
      print(xtable(cast(ttt, test~error)), floating=FALSE, include.rownames=FALSE)
    # --- Colnames [] ---
    # Key functions: xtable
    ttt <- experiment[experiment$error == 'broken', ]
      ttt$X <- NULL
      ttt$error <- NULL
      colnames(ttt) <- c('package', 'dataset', 'obj', 'grouping', 'levels', 'test')
      print(xtable(ttt), floating=FALSE, include.rownames=FALSE)
    # --- Customhasse [] ---
    # Key functions: transReduct, hasse
    # create adjacency matrix

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_paircompviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_paircompviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_paircompviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PAIRCOMPVIZ:", paste0("    paircompviz: ", packageVersion("paircompviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paircompviz_results.csv
    touch ${prefix}_paircompviz_output.rds
    echo "BIOC_PAIRCOMPVIZ:" > versions.yml
    echo "    paircompviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PAIRCOMPVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PAIRCOMPVIZ(ch_input)

    emit:
    results  = BIOC_PAIRCOMPVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PAIRCOMPVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PAIRCOMPVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PAIRCOMPVIZ.out.versions  // channel: path(versions.yml)
}
