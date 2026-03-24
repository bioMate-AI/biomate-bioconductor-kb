#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: drugTargetInteractions
// Provides utilities for identifying drug-target interactions for sets of small molecule or gene/prote
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/drugTargetInteractions/inst/doc/drugTargetInteractions.R
// Upstream  : DT
// Downstream: none
//
// Install: BiocManager::install("drugTargetInteractions")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DRUGTARGETINTERACTIONS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-drugtargetinteractions"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-drugtargetinteractions:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-drugtargetinteractions:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_drugtargetinteractions_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_drugtargetinteractions_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_drugtargetinteractions_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(drugTargetInteractions)
    library(jsonlite)

    # --- gen Config [] ---
    # Key functions: genConfig
    chembldb <- system.file("extdata", "chembl_sample.db", package="drugTargetInteractions")
    resultsPath <- system.file("extdata", "results", package="drugTargetInteractions")
    config <- genConfig(chemblDbPath=chembldb, resultsPath=resultsPath)
    # --- download Uni Chem [] ---
    # Key functions: downloadUniChem, cmpIdMapping
    downloadUniChem(config=config)
    cmpIdMapping(config=config)
    # --- get Uniprot I Ds [] ---
    # Key functions: getUniprotIDs
    keys <- c("ENSG00000145700", "ENSG00000135441", "ENSG00000120071")
    res_list90 <- getUniprotIDs(taxId=9606, kt="ENSEMBL", keys=keys, seq_cluster="UNIREF90")
    # --- datatable [] ---
    # Key functions: datatable
    library(DT)
    datatable(res_list90[[1]], options = list(scrollX=TRUE, scrollY="600px", autoWidth = TRUE))
    # --- get Paralogs [] ---
    # Key functions: getParalogs
    queryBy <- list(molType="gene", idType="external_gene_name", ids=c("ANKRD31", "BLOC1S1", "KANSL1"))
    queryBy <- list(molType="gene", idType="ensembl_gene_id", ids=c("ENSG00000145700", "ENSG00000135441", "ENSG00000120071"))
    res_list <- getParalogs(queryBy)
    # --- datatable [] ---
    # Key functions: datatable
    library(DT)
    datatable(res_list[[1]], options = list(scrollX = TRUE, scrollY="400px", autoWidth = TRUE))
    # --- drug Target Annot [] ---
    # Key functions: drugTargetAnnot
    queryBy <- list(molType="cmp", idType="chembl_id", ids=c("CHEMBL17", "CHEMBL19", "CHEMBL1201117", "CHEMBL25", "nomatch", "CHEMBL1742471"))
    qresult1 <- drugTargetAnnot(queryBy, config=config)
    # --- cmp query result1 [] ---
    # Key functions: datatable
    library(DT)
    datatable(qresult1, options = list(scrollX = TRUE, scrollY="600px", autoWidth = TRUE))
    # --- drug Target Annot [] ---
    # Key functions: drugTargetAnnot
    queryBy <- list(molType="protein", idType="UniProt_ID", ids=c("P43166", "P00915"))
    qresult2 <- drugTargetAnnot(queryBy, config=config)
    # --- protein query result1 [] ---
    # Key functions: datatable
    library(DT)
    datatable(qresult2, options = list(scrollX = TRUE, scrollY="600px", autoWidth = TRUE))
    # --- get Uniprot I Ds [] ---
    # Key functions: getUniprotIDs
    keys <- c("ENSG00000120088", "ENSG00000135441", "ENSG00000120071")
    res_list90 <- getUniprotIDs(taxId=9606, kt="ENSEMBL", keys=keys, seq_cluster="UNIREF90")
    # --- drug Target Annot [] ---
    # Key functions: drugTargetAnnot
    queryBy <- list(molType="protein", idType="UniProt_ID", ids=id_list[[2]])
    qresultSSNN <- drugTargetAnnot( queryBy, config=config)
    ensidsSSNN <- tapply(res_list90[[2]]$ENSEMBL, res_list90[[2]]$ID, paste, collapse=", ")
    # --- protein query result2 [] ---
    # Key functions: datatable
    library(DT)
    datatable(qresultSSNN, options = list(scrollX = TRUE, scrollY="600px", autoWidth = TRUE))
    # --- cmp query2 [] ---
    # Key functions: getDrugTarget
    id_mapping <- c(chembl="chembl_id", pubchem="PubChem_ID", uniprot="UniProt_ID", drugbank="DrugBank_ID")
    queryBy <- list(molType="cmp", idType="pubchem", ids=c("2244", "65869", "2244"))
    queryBy <- list(molType="protein", idType="uniprot", ids=c("P43166", "P00915", "P43166"))
    # --- cmp query result2 [] ---
    # Key functions: datatable
    library(DT)
    datatable(qresult3, options = list(scrollX = TRUE, scrollY="600px", autoWidth = TRUE))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_drugtargetinteractions_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_drugtargetinteractions_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_drugtargetinteractions_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DRUGTARGETINTERACTIONS:", paste0("    drugtargetinteractions: ", packageVersion("drugTargetInteractions"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drugtargetinteractions_results.csv
    touch ${prefix}_drugtargetinteractions_output.rds
    echo "BIOC_DRUGTARGETINTERACTIONS:" > versions.yml
    echo "    drugtargetinteractions: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DRUGTARGETINTERACTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DRUGTARGETINTERACTIONS(ch_input)

    emit:
    results  = BIOC_DRUGTARGETINTERACTIONS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DRUGTARGETINTERACTIONS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DRUGTARGETINTERACTIONS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DRUGTARGETINTERACTIONS.out.versions  // channel: path(versions.yml)
}
