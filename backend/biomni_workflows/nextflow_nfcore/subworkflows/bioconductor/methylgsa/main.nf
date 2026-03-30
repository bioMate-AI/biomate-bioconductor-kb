#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylGSA
// The main functions for methylGSA are methylglm and methylRRA. methylGSA implements logistic regressi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylGSA/inst/doc/methylGSA-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("methylGSA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLGSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylgsa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylgsa:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylgsa:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylgsa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylgsa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylgsa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylGSA)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(cpgtoy)
    head(cpg.pval, 20)
    # --- Methylglm [] ---
    # Key functions: methylglm
    ---------------------------------------------------------------------
    res1 = methylglm(cpg.pval = cpg.pval, minsize = 200,
                     maxsize = 500, GS.type = "KEGG")
    head(res1, 15)
    # --- Select [] ---
    # Key functions: select
    ---------------------------------------------------------------------
    library(org.Hs.eg.db)
    genes_04080 = select(org.Hs.eg.db, "04080", "SYMBOL", keytype = "PATH")
    head(genes_04080)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(GSlisttoy)
    ## to make the display compact, only a proportion of each gene set is shown
    head(lapply(GS.list, function(x) x[1:30]), 3)
    # --- Prepareannot [] ---
    # Key functions: prepareAnnot
    ---------------------------------------------------------------------
    FullAnnot = prepareAnnot(CpG2Gene)
    # --- Methylrra [] ---
    # Key functions: methylRRA
    ---------------------------------------------------------------------
    GS.list = GS.list[1:10]
    res5 = methylRRA(cpg.pval = cpg.pval, FullAnnot = FullAnnot, method = "ORA",
                        GS.list = GS.list, GS.idtype = "SYMBOL",
                        minsize = 100, maxsize = 300)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylgsa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylgsa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylgsa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLGSA:", paste0("    methylgsa: ", packageVersion("methylGSA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylgsa_results.csv
    touch ${prefix}_methylgsa_output.rds
    echo "BIOC_METHYLGSA:" > versions.yml
    echo "    methylgsa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLGSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLGSA(ch_input)

    emit:
    results  = BIOC_METHYLGSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLGSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLGSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLGSA.out.versions  // channel: path(versions.yml)
}
