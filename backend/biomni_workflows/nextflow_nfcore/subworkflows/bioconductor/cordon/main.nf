#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: coRdon
// Tool for analysis of codon usage in various unannotated or KEGG/COG annotated DNA sequences. Calcula
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/coRdon/inst/doc/coRdon.R
// Upstream  : Biobase, ggplot2
// Downstream: none
//
// Install: BiocManager::install("coRdon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CORDON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cordon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cordon:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cordon:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cordon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cordon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cordon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Bplot)
    library(MELP)
    library(MILC)
    library(jsonlite)

    # --- Readset [] ---
    # Key functions: readSet, codonTable
    ---------------------------------------------------------------------
    dnaLD94 <- readSet(
      file="https://raw.githubusercontent.com/BioinfoHR/coRdon-examples/master/LD94.fasta"
    )
    LD94 <- codonTable(dnaLD94)
    # --- Codoncounts [] ---
    # Key functions: codonCounts, getlen
    ---------------------------------------------------------------------
    cc <- codonCounts(HD59)
    head(cc)
    l <- getlen(HD59)
    head(l)
    # --- Getko [] ---
    # Key functions: getKO
    ---------------------------------------------------------------------
    ko <- getKO(HD59)
    head(ko)
    # --- Milc [] ---
    # Key functions: MILC
    ---------------------------------------------------------------------
    milc <- MILC(HD59)
    head(milc)
    # --- Frame [] ---
    # Key functions: frame, getlen, ggplot, aes, geom_density, geom_vline, theme_light
    ---------------------------------------------------------------------
    lengths <- as.data.frame(getlen(HD59))
    colnames(lengths) <- "length"
    ggplot(lengths, aes(length)) +
        geom_density() +
    # --- Milc [] ---
    # Key functions: MILC
    ---------------------------------------------------------------------
    milc <- MILC(HD59, ribosomal = TRUE, filtering = "hard")
    # --- Milc [] ---
    # Key functions: MILC, Bplot, labs
    ---------------------------------------------------------------------
    library(ggplot2)
    xlab <- "MILC distance from sample centroid"
    ylab <- "MILC distance from ribosomal genes"
    milc_HD59 <- MILC(HD59, ribosomal = TRUE)
    # --- Getko [] ---
    # Key functions: getKO, getlen, Bplot, labs
    ---------------------------------------------------------------------
    genes <- getKO(HD59)[getlen(HD59) > 80]
    Bplot(x = "ribosomal", y = "self", data = milc,
            annotations = genes, ribosomal = TRUE) +
        labs(x = xlab, y = ylab)
    # --- Intrabplot [] ---
    # Key functions: intraBplot
    ---------------------------------------------------------------------
    intraBplot(HD59, LD94, names = c("HD59", "LD94"),
                variable = "MILC",
                ribosomal = TRUE)
    # --- Melp [] ---
    # Key functions: MELP
    ---------------------------------------------------------------------
    melp <- MELP(HD59, ribosomal = TRUE, filtering = "hard")
    head(melp)
    # --- Crosstab [] ---
    # Key functions: crossTab
    ---------------------------------------------------------------------
    ct <- crossTab(genes, as.numeric(melp), threshold = 1L)
    ct
    # --- Contable [] ---
    # Key functions: contable, getSeqAnnot, getVariable
    ---------------------------------------------------------------------
    contable(ct)
    ann <- getSeqAnnot(ct)
    head(ann)
    var <- getVariable(ct)
    # --- Crosstab [] ---
    # Key functions: crossTab
    ---------------------------------------------------------------------
    crossTab(genes, as.numeric(melp), percentiles = 0.05)
    # --- Enrichment [] ---
    # Key functions: enrichment
    ---------------------------------------------------------------------
    enr <- enrichment(ct)
    enr
    # --- Pdata [] ---
    # Key functions: pData
    ---------------------------------------------------------------------
    require(Biobase)
    enr_data <- pData(enr)
    head(enr_data)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cordon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cordon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cordon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CORDON:", paste0("    cordon: ", packageVersion("coRdon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cordon_results.csv
    touch ${prefix}_cordon_output.rds
    echo "BIOC_CORDON:" > versions.yml
    echo "    cordon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CORDON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CORDON(ch_input)

    emit:
    results  = BIOC_CORDON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CORDON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CORDON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CORDON.out.versions  // channel: path(versions.yml)
}
