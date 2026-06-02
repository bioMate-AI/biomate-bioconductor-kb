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
    library(KEGG2heatmap)
    library(KEGGmnplot)
    library(PWAmat)
    library(jsonlite)

    # --- Example [] ---
    # Key functions: intersect, factor, nsFilter
    ## subset of interest: 37+42 samples
    data(ALL)
    esetA <- ALL[, intersect(grep("^B", as.character(ALL$BT)),
              which(as.character(ALL$mol) %in% c("NEG", "BCR/ABL")))]
    esetA@annotation = "hgu95av2"
    # --- Parametric1 [] ---
    # Key functions: rowttests, findLargest, featureNames, probes2Path
    ttests = rowttests(esetASub, "mol.biol")
    ##find the probes that we are going to use
    fL = findLargest(featureNames(esetASub), abs(ttests$statistic), "hgu95av2")
    fL2 = probes2Path(fL, "hgu95av2")
    length(fL2)
    # --- Reorder [] ---
    # Key functions: featureNames, rowttests
    eS = esetASub[match(names(fL2), featureNames(esetASub)),]
    tobs = rowttests(eS, "mol.biol")
    # --- Amat [] ---
    # Key functions: PWAmat
    Amat = t(PWAmat("hgu95av2"))
    AmER = Amat[,names(fL)]
    # --- Rs [] ---
    # Key functions: rowSums
    rs = rowSums(AmER)
    AmER2 = AmER[rs>5,]
    rs2   = rs[rs>5]
    nCats = length(rs2)
    # --- Keggmnplot [] ---
    # Key functions: KEGGmnplot, getPathNames
    KEGGmnplot(byTT, eS, group=eS$mol, data="hgu95av2",
                   main=paste(getPathNames(byTT)[[1]], paste("Overall:",
                   round(tA[byTT], 3)), sep="\n"))
    # --- Setuphmcols [] ---
    # Key functions: colorRampPalette, pal, ifelse
    hmcol <- rev(colorRampPalette(brewer.pal(10, "RdBu"))(256))
    spcol <- ifelse(eS$mol.biol=="BCR/ABL", "goldenrod", "skyblue")
    # --- Ribosomeheatmap [] ---
    # Key functions: KEGG2heatmap, getPathNames
    tmp1 = KEGG2heatmap(byTT, eS, data="hgu95av2",
                   main=paste(getPathNames(byTT)[[1]], paste("Overall:",
                   round(tA[byTT], 3)), sep="\n"), col=hmcol,
                     ColSideColors=spcol)
    # --- Hmbysex [] ---
    # Key functions: ifelse, KEGG2heatmap, getPathNames
    spcol2 <- ifelse(eS$sex=="M", "lightgreen", "slategrey")
        tmp2 = KEGG2heatmap(byTT, eS, data="hgu95av2",
                   main=paste(getPathNames(byTT)[[1]], paste("Overall:",
                   round(tA[byTT], 3)), sep="\n"), col=hmcol,
                     ColSideColors=spcol2)
    # --- Ttperms [] ---
    # Key functions: ttperm, exprs, sweep
    v1 = ttperm(exprs(eS), eS$mol.biol, B=NPERM)
    permDm <- matrix(0.0, nrow=length(v1$perms[[1]]$statistic),
                     ncol=length(v1$perms))
    # --- Gethighnames [] ---
    # Key functions: getPathNames
    getPathNames(highC)[1:5]
    # --- Mnplot1 [] ---
    # Key functions: KEGGmnplot, getPathNames
    KEGGmnplot(highC[lnhC], eS, group=eS$mol, data="hgu95av2",
                   main=paste(getPathNames(highC[lnhC])[[1]], paste("Overall:",
                   round(tA[highC[lnhC]], 3)), sep="\n"), pch=16, col="blue")
    # --- Mnplot2 [] ---
    # Key functions: KEGGmnplot, getPathNames
    KEGGmnplot(highC[lnhC-1], eS, group=eS$mol, data="hgu95av2",
                   main=paste(getPathNames(highC[lnhC-1])[[1]], paste("Overall:",
                   round(tA[highC[lnhC-1]], 3)), sep="\n"))
    # --- Mnplot3 [] ---
    # Key functions: KEGGmnplot, getPathNames
    KEGGmnplot(highC[lnhC-2], eS, group=eS$mol, data="hgu95av2",
                   main=paste(getPathNames(highC[lnhC-2])[[1]], paste("Overall:",
                   round(tA[highC[lnhC-2]], 3)), sep="\n"))
    # --- Hmperm [] ---
    # Key functions: KEGG2heatmap, getPathNames
    tmp2 = KEGG2heatmap(highC[lnhC-2], eS, data="hgu95av2",
                   main=paste(getPathNames(highC[lnhC-2])[[1]], paste("Overall:",
                   round(tA[highC[lnhC-2]], 3)), sep="\n"), col=hmcol,
                     ColSideColors=spcol)

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
