#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GOexpress
// The package contains methods to visualise the expression profile of genes from a microarray or RNA-s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GOexpress/inst/doc/GOexpress-UsersGuide.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("GOexpress")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOEXPRESS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-goexpress"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-goexpress:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-goexpress:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_goexpress_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_goexpress_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_goexpress_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GO_analyse)
    library(jsonlite)

    # --- Goexpress Usersguide.Rnw:113 114 [] ---
    # Key functions: maintainer
    maintainer("GOexpress")
    # --- Goexpress Usersguide.Rnw:201 203 [] ---
    # Key functions: data
    library(GOexpress) # load the GOexpress package
    data(AlvMac) # import the training dataset
    # --- Goexpress Usersguide.Rnw:210 212 [] ---
    # Key functions: exprs, pData
    exprs(AlvMac)[1:5,1:5] # Subset of the expression data
    head(pData(AlvMac)) # Subset of the phenotypic information
    # --- Goexpress Usersguide.Rnw:223 224 [] ---
    # Key functions: exprs
    head(rownames(exprs(AlvMac))) # Subset of gene identifiers
    # --- Goexpress Usersguide.Rnw:250 252 [] ---
    # Key functions: factor
    is.factor(AlvMac$Treatment) # assertion test
    AlvMac$Treatment # visual inspection
    # --- Goexpress Usersguide.Rnw:262 263 [] ---
    # Key functions: factor
    ## AlvMac$Treatment <- factor(AlvMac$Treatment)
    # --- Goexpress Usersguide.Rnw:285 289 [] ---
    # Key functions: GO_analyse
    set.seed(4543) # set random seed for reproducibility
    AlvMac_results <- GO_analyse(
        eSet = AlvMac, f = "Treatment",
        GO_genes=AlvMac_GOgenes, all_GO=AlvMac_allGO, all_genes=AlvMac_allgenes)
    # --- Goexpress Usersguide.Rnw:301 305 [] ---
    # Key functions: terms, genes
    names(AlvMac_results) # Data slot names
    head(AlvMac_results$GO[, c(1:5, 7)], n=5) # Ranked table of GO terms (subset)
    head(AlvMac_results$genes[, c(1:3)], n=5) # Ranked table of genes (subset)
    head(AlvMac_results$mapping) # Gene to gene ontology mapping table (subset)
    # --- Goexpress Usersguide.Rnw:329 330 [] ---
    # Key functions: GO_analyse
    ## AlvMac_results <- GO_analyse(eSet = AlvMac, f = "Treatment")
    # --- Goexpress Usersguide.Rnw:349 350 [] ---
    # Key functions: data
    ## data(microarray2dataset)
    # --- Goexpress Usersguide.Rnw:365 366 [] ---
    # Key functions: pValue_GO
    ## AlvMac_results.pVal = pValue_GO(result=AlvMac_results, N=100)
    # --- Goexpress Usersguide.Rnw:369 370 [] ---
    # Key functions: data
    data(AlvMac_results.pVal)
    # --- Goexpress Usersguide.Rnw:423 438 [] ---
    # Key functions: subset_scores
    BP.5 <- subset_scores(
        result = AlvMac_results.pVal,
        namespace = "biological_process",
        total = 5, # requires 5 or more associated genes
        p.val=0.05)
    # --- Goexpress Usersguide.Rnw:472 476 [] ---
    # Key functions: subset
    ## subset(
    ##     AlvMac_results.pVal$GO,
    ##     total_count >= 5 & p.val<0.05 & namespace_1003=='biological_process'
    ##     )
    # --- Goexpress Usersguide.Rnw:515 518 [] ---
    # Key functions: heatmap_GO
    heatmap_GO(
        go_id = "GO:0034142", result = BP.5, eSet=AlvMac, cexRow=0.4,
        cexCol=1, cex.main=1, main.Lsplit=30)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_goexpress_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_goexpress_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_goexpress_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOEXPRESS:", paste0("    goexpress: ", packageVersion("GOexpress"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_goexpress_results.csv
    touch ${prefix}_goexpress_output.rds
    echo "BIOC_GOEXPRESS:" > versions.yml
    echo "    goexpress: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOEXPRESS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOEXPRESS(ch_input)

    emit:
    results  = BIOC_GOEXPRESS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOEXPRESS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOEXPRESS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOEXPRESS.out.versions  // channel: path(versions.yml)
}
