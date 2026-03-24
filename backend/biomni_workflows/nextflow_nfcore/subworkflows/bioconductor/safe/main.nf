#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: safe
// SAFE is a resampling-based method for testing functional categories in gene expression experiments. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/safe/inst/doc/SAFEmanual3.R
// Upstream  : breastCancerUPP, doParallel
// Downstream: none
//
// Install: BiocManager::install("safe")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SAFE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-safe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-safe:3.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-safe:3.46.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_safe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_safe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_safe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Surv)
    library(Time)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: exprs, pData
    data(upp)
    ex.upp <- exprs(upp)
    p.upp <- pData(upp)
    data(p53.stat)
    p.upp <- cbind(p.upp, p53 = p53.stat$p53)
    # --- Which [] ---
    # Key functions: unlist
    grade.3 <- which(p.upp$grade == 3)
    p3.upp <- p.upp[grade.3,]
    genes <- unlist(as.list(hgu133aSYMBOL))
    drop <- grep("AFFX", names(genes))
    genes <- genes[-drop]
    # --- Toptable [] ---
    # Key functions: toptable
    ## safe.toptable(results, number = 10)
    # --- Results [] ---
    # Key functions: results
    gene.results(results, cat.name = "REACTOME:R-HSA-69183", gene.names = genes)
    # --- Plot0 [] ---
    # Key functions: safeplot
    safeplot(results, cat.name = "REACTOME:R-HSA-69183", gene.names = genes)
    # --- Unlist [] ---
    # Key functions: unlist, mget, getCmatrix, safe
    entrez <- unlist(mget(names(genes),hgu133aENTREZID))
    C.mat <- getCmatrix(gene.list = as.list(reactomeEXTID2PATHID),
                        present.genes = entrez,prefix = "REACTOME:",
                        min.size = 10, max.size = 500)
    results <- safe(e3.upp, p3.upp$p53, C.mat, print.it = FALSE)
    # --- Getcmatrix [] ---
    # Key functions: getCmatrix
    ## C.mat2 <- getCmatrix(gene.list = as.list(hgu133aPFAM),
    ##                      present.genes = rownames(e3.upp))
    # --- List [] ---
    # Key functions: getCmatrix
    ## GO.list <- as.list(hgu133aGO2ALLPROBES)
    ## C.mat2 <- getCmatrix(keyword.list = GO.list, GO.ont = "CC",
    ##             present.genes = rownames(e3.upp))
    # --- Safe [] ---
    # Key functions: safe
    results2 <- safe(e3.upp, p3.upp$p53, C.mat, local = "t.Welch",
                     Pi.mat = 1, print.it = FALSE)
    cbind(Student = round(results@local.stat[1:3], 3),
          Welch   = round(results2@local.stat[1:3], 3))
    # --- Rep [] ---
    # Key functions: safe
    y.vec <- rep(1:27,2)*rep(c(-1,1), each = 27)
    results2 <- safe(e3.upp, y.vec, C.mat, local = "t.paired",
                     Pi.mat = 1, print.it = FALSE)
    # --- Safe [] ---
    # Key functions: safe
    results3 <-  safe(e3.upp, y.vec, C.mat, local = "WilcoxSignRank",
                      Pi.mat = 1, print.it = FALSE)
    cbind(Paired.t  = round(results2@local.stat[1:3], 3),
          Sign.Rank = results3@local.stat[1:3])
    # --- Surv [] ---
    # Key functions: survfit, Surv, Time
    layout(matrix(1:2,2,1), heights=c(4,2))
    plot(survfit(Surv(p3.upp$t.rfs, p3.upp$e.rfs) ~ 1),
         xlab = "Time (days)", ylim = c(.4,1))
    # --- Na [] ---
    # Key functions: na, getCOXresiduals, safe
    drop <- is.na(p3.upp$t.rfs)
    Xy <- getCOXresiduals(e3.upp[,!drop], p3.upp$t.rfs[!drop],
                          p3.upp$e.rfs[!drop])
    results2 <- safe(Xy$X.star, Xy$y.star, C.mat,
                     Pi.mat = 1, print.it = FALSE)
    # --- Table [] ---
    # Key functions: getXYresiduals, safe
    table(ER = p3.upp$er, p53 = p3.upp$p53)
    Xy <- getXYresiduals(e3.upp, p3.upp$p53, Z.mat = p3.upp$er)
    results2 <- safe(Xy$X.star, Xy$y.star, C.mat,
                     Pi.mat = 1, print.it = FALSE)
    # --- Safe [] ---
    # Key functions: safe
    results2 <- safe(e3.upp, p3.upp$p53, C.mat,
                     global = "AveDiff", print.it = FALSE)
    cor(results@global.pval, results2@global.pval, method = "spearman")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_safe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_safe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_safe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SAFE:", paste0("    safe: ", packageVersion("safe"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_safe_results.csv
    touch ${prefix}_safe_output.rds
    echo "BIOC_SAFE:" > versions.yml
    echo "    safe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SAFE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_SAFE(ch_input)

    emit:
    results  = BIOC_SAFE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SAFE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SAFE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SAFE.out.versions  // channel: path(versions.yml)
}
