#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chopsticks
// Implements classes and methods for large-scale SNP association studies
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chopsticks/inst/doc/chopsticks-vignette.R
// Upstream  : hexbin
// Downstream: none
//
// Install: BiocManager::install("chopsticks")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHOPSTICKS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chopsticks"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chopsticks:1.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chopsticks:1.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chopsticks_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chopsticks_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chopsticks_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(chopsticks)
    library(jsonlite)

    # --- Init [] ---
    # Key functions: data
    library(chopsticks)
    library(hexbin)
    data(for.exercise)
    # --- Plot Summaries [] ---
    # Key functions: hexbin
    hb <- hexbin(sum.controls$Call.rate, sum.cases$Call.rate, xbin=50)
    sp <- plot(hb)
    hexVP.abline(sp$plot.vp, a=0, b=1, col="black")
    # --- Plot Freqs [] ---
    # Key functions: hexbin
    sp <- plot(hexbin(sum.controls$MAF, sum.cases$MAF, xbin=50))
    hexVP.abline(sp$plot.vp, a=0, b=1, col="white")
    # --- Tests [] ---
    # Key functions: tests
    tests <- single.snp.tests(cc, data = subject.support, snp.data = snps.10)
    # --- Plot Tests [] ---
    # Key functions: pchisq, hexbin
    p1 <- pchisq(tests$chi2.1df, df = 1, lower.tail = FALSE)
    plot(hexbin(position, -log10(p1), xbin=50))
    # --- Qqplot [] ---
    # Key functions: chisq
    qq.chisq(tests$chi2.1df, df = 1)
    # --- More Tests [] ---
    # Key functions: tests, pchisq, hexbin
    tests <- single.snp.tests(cc, stratum, data = subject.support,
         snp.data = snps.10)
    tests <- tests[use, ]
    p1 <- pchisq(tests$chi2.1df, df = 1, lower.tail = FALSE)
    plot(hexbin(position, -log10(p1), xbin=50))
    # --- More Tests Qq [] ---
    # Key functions: chisq
    qq.chisq(tests$chi2.1df, df = 1)
    # --- Ld 2Mb [] ---
    # Key functions: snp
    snps.2mb <- snps.10[, local]
    ld.2mb <- ld.snp(snps.2mb)
    # --- Top1 [] ---
    # Key functions: attach, glm
    attach(subject.support)
    top <- snps.10[, "rs870041"]
    top <- as.numeric(top)
    glm(cc ~ top + stratum, family = "binomial")
    # --- Top2 3 [] ---
    # Key functions: glm
    top2 <- snps.10[, "rs7088765"]
    top2 <- as.numeric(top2)
    glm(cc ~ top2 + stratum, family = "binomial")
    top3 <- snps.10[, "rs1916572"]
    top3 <- as(top3, "numeric")
    # --- Blocks [] ---
    # Key functions: split, cut
    blocks <- split(posord, cut(position, seq(100000, 135300000, 20000)))
    bsize <- sapply(blocks, length)
    table(bsize)
    blocks <- blocks[bsize>0]
    # --- Blocks Use [] ---
    # Key functions: remove
    snps.use <- snps.10[, use]
    remove(snps.10)
    # --- Mtests [] ---
    # Key functions: tests
    mtests <- snp.rhs.tests(cc ~ stratum, family = "binomial",
         data = subject.support, snp.data = snps.use, tests = blocks)
    summary(mtests)
    # --- Plot Mtests [] ---
    # Key functions: pchisq, hexbin
    pm <- pchisq(mtests$Chi.squared, mtests$Df, lower.tail = FALSE)
    plot(hexbin(-log10(pm), xbin=50))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chopsticks_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chopsticks_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chopsticks_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHOPSTICKS:", paste0("    chopsticks: ", packageVersion("chopsticks"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chopsticks_results.csv
    touch ${prefix}_chopsticks_output.rds
    echo "BIOC_CHOPSTICKS:" > versions.yml
    echo "    chopsticks: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHOPSTICKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHOPSTICKS(ch_input)

    emit:
    results  = BIOC_CHOPSTICKS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHOPSTICKS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHOPSTICKS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHOPSTICKS.out.versions  // channel: path(versions.yml)
}
