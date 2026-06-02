#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GIGSEA
// We presented the Genotype-imputed Gene Set Enrichment Analysis (GIGSEA), a novel method that uses GW
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GIGSEA/inst/doc/GIGSEA_tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GIGSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GIGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gigsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gigsea:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gigsea:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gigsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gigsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gigsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GIGSEA)
    library(jsonlite)

    # --- Rungigsea [] ---
    # Key functions: runGIGSEA
    ---------------------------------------------------------------------
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(heart.metaXcan)
    head(heart.metaXcan)
    # --- Frame [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    gene = heart.metaXcan$gene_name
    # extract the imputed Z-score of differential gene expression, which follows
    # the normal distribution
    fc <- heart.metaXcan$zscore
    # --- Data [] ---
    # Key functions: data, class
    ---------------------------------------------------------------------
    # load data
    data(MSigDB.KEGG.Pathway)
    # MSigDB.KEGG.Pathway is a list comprising two components: net and annot
    class(MSigDB.KEGG.Pathway)
    # --- Readlines [] ---
    # Key functions: term, geneset, value, gmt2geneSet
    ---------------------------------------------------------------------
    # downlaod the gmt file
    gmt <- readLines( paste0('http://amp.pharm.mssm.edu/CREEDS/download/',
                            'single_drug_perturbations-v1.0.gmt') )
    # obtain the index of up-regulated and down-regulated gene sets
    # --- Orderedintersect [] ---
    # Key functions: orderedIntersect, all, time, permutationSimpleLm, permutationSimpleLmMatrix
    ---------------------------------------------------------------------
    # take MSigDB.KEGG.Pathway as an example
    net <- MSigDB.KEGG.Pathway$net
    # intersect the permuted genes with the gene sets of interest
    data2 <- orderedIntersect( x = data , by.x = data$gene , by.y = rownames(net) )
    # --- Time [] ---
    # Key functions: time, permutationMultipleLm, permutationMultipleLmMatrix
    ---------------------------------------------------------------------
    # MGSEA.res1 uses the weighted multiple linear regression model
    system.time( MGSEA.res1 <- permutationMultipleLm( fc=data2$fc , net=net2 ,
                                  weights=data2$weights , num=1000 ) )
    # MGSEA.res2 used the matrix solution
    # --- Data [] ---
    # Key functions: frame, weightedGSEA
    ---------------------------------------------------------------------
    # import packages and prepare data as above
    library(GIGSEA)
    # prepare the dataset
    data(heart.metaXcan)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gigsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gigsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gigsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GIGSEA:", paste0("    gigsea: ", packageVersion("GIGSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gigsea_results.csv
    touch ${prefix}_gigsea_output.rds
    echo "BIOC_GIGSEA:" > versions.yml
    echo "    gigsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GIGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GIGSEA(ch_input)

    emit:
    results  = BIOC_GIGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GIGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GIGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GIGSEA.out.versions  // channel: path(versions.yml)
}
