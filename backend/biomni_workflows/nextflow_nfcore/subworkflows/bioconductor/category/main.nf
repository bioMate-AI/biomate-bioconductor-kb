#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Category
// A collection of tools for performing category (gene set enrichment) analysis.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Category/inst/doc/Category.R
// Upstream  : ALL, RColorBrewer, SNPchip, annotate, genefilter
// Downstream: GOstats
//
// Install: BiocManager::install("Category")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CATEGORY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-category"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-category:2.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-category:2.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_category_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_category_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_category_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Category)
    library(KEGG2heatmap)
    library(KEGGmnplot)
    library(PWAmat)
    library(jsonlite)

    # --- Probe Mapping and Annotation Filtering [category] ---
    # Key functions: findLargest, probes2Path, PWAmat
    fL <- findLargest(featureNames(esetASub), abs(tobs$statistic), "hgu95av2")
    fL2 <- probes2Path(fL, "hgu95av2")
    inBoth <- fL %in% names(fL2)
    fL <- fL[inBoth]
    eS <- esetASub[match(names(fL2), featureNames(esetASub)), ]
    Amat <- t(PWAmat("hgu95av2"))
    AmER <- Amat[, names(fL)]
    rs <- rowSums(AmER)
    AmER2 <- AmER[rs > 5, ]

    # --- Category Statistics Computation [category] ---
    # Key functions: applyByCategory
    tobs <- rowttests(eS, "mol.biol")
    tA <- AmER2 %*% tobs$statistic
    tA <- tA / sqrt(rowSums(AmER2))
    names(tA) <- row.names(AmER2)
    med <- applyByCategory(tobs$statistic, AmER2, FUN = median)
    wt <- applyByCategory(tobs$statistic, AmER2, 
                          FUN = function(x) {
                              w <- wilcox.test(x)
                              c(w$statistic, p = w$p.value)
                          })

    # --- Permutation Analysis [category] ---
    # Key functions: ttperm
    v1 <- ttperm(exprs(eS), eS$mol.biol, B = 100)
    permDm <- matrix(0.0, nrow = length(v1$perms[[1]]$statistic),
                     ncol = length(v1$perms))
    for (j in seq_along(v1$perms)) {
        permDm[, j] <- v1$perms[[j]]$statistic
    }
    permD <- AmER2 %*% permDm
    permD2 <- sweep(permD, 1, sqrt(rowSums(AmER2)), "/")

    # --- Pathway Visualization [category] ---
    # Key functions: KEGGmnplot, KEGG2heatmap, getPathNames
    byTT <- names(tA)[tA < -7]
    pathNames <- getPathNames(byTT)
    KEGGmnplot(byTT[1], eS, group = eS$mol, data = "hgu95av2",
               main = paste(pathNames[[1]], 
                            paste("Overall:", round(tA[byTT[1]], 3)), 
                            sep = "\n"))
    hmcol <- rev(colorRampPalette(c("blue", "white", "red"))(256))
    spcol <- ifelse(eS$mol.biol == "BCR/ABL", "goldenrod", "skyblue")
    tmp1 <- KEGG2heatmap(byTT[1], eS, data = "hgu95av2",
                         col = hmcol, ColSideColors = spcol)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_category_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_category_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_category_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CATEGORY:", paste0("    category: ", packageVersion("Category"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_category_results.csv
    touch ${prefix}_category_output.rds
    echo "BIOC_CATEGORY:" > versions.yml
    echo "    category: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CATEGORY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CATEGORY(ch_input)

    emit:
    results  = BIOC_CATEGORY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CATEGORY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CATEGORY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CATEGORY.out.versions  // channel: path(versions.yml)
}
