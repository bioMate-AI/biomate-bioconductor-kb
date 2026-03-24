#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BgeeDB
// A package for the annotation and gene expression data download from Bgee database, and TopAnat analy
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BgeeDB/inst/doc/BgeeDB_Manual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BgeeDB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BGEEDB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bgeedb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bgeedb:2.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bgeedb:2.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bgeedb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bgeedb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bgeedb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BgeeDB)
    library(jsonlite)

    # --- Listbgeespecies [] ---
    # Key functions: listBgeeSpecies
    ---------------------------------------------------------------------
    listBgeeSpecies()
    # --- Getannotation [] ---
    # Key functions: getAnnotation
    ---------------------------------------------------------------------
    annotation_bgee_zebrafish <- getAnnotation(bgee)
    # list the first experiments and libraries
    lapply(annotation_bgee_zebrafish, head)
    # --- Getsampleprocesseddata [] ---
    # Key functions: getSampleProcessedData
    ---------------------------------------------------------------------
    # download all RNA-seq experiments from zebrafish
    data_bgee_zebrafish <- getSampleProcessedData(bgee)
    # number of experiments downloaded
    length(data_bgee_zebrafish)
    # --- Formatdata [] ---
    # Key functions: formatData
    ---------------------------------------------------------------------
    # use only present calls and fill expression matrix with TPM values
    gene.expression.zebrafish.tpm <- formatData(bgee, data_bgee_zebrafish_gse68666, callType = "present", stats = "tpm")
    gene.expression.zebrafish.tpm
    # --- Loadtopanatdata [] ---
    # Key functions: loadTopAnatData
    ---------------------------------------------------------------------
    # Loading calls of expression
    myTopAnatData <- loadTopAnatData(bgee)
    # Look at the data
    ## str(myTopAnatData)
    # --- Data [] ---
    # Key functions: topAnat
    ---------------------------------------------------------------------
    data(geneList)
    myTopAnatObject <-  topAnat(myTopAnatData, geneList)
    # --- Runtest [] ---
    # Key functions: runTest
    ---------------------------------------------------------------------
    results <- runTest(myTopAnatObject, algorithm = 'weight', statistic = 'fisher')
    # --- Maketable [] ---
    # Key functions: makeTable
    ---------------------------------------------------------------------
    # Display results sigificant at a 1% FDR threshold
    tableOver <- makeTable(myTopAnatData, myTopAnatObject, results, cutoff = 0.01)
    head(tableOver)
    # --- Termstat [] ---
    # Key functions: termStat, genesInTerm, sigGenes
    ---------------------------------------------------------------------
    # In order to retrieve significant genes mapped to the term " paired limb/fin bud"
    term <- "UBERON:0004357"
    termStat(myTopAnatObject, term)
    # 172 genes mapped to this term for Bgee 15.2

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bgeedb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bgeedb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bgeedb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BGEEDB:", paste0("    bgeedb: ", packageVersion("BgeeDB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bgeedb_results.csv
    touch ${prefix}_bgeedb_output.rds
    echo "BIOC_BGEEDB:" > versions.yml
    echo "    bgeedb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BGEEDB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BGEEDB(ch_input)

    emit:
    results  = BIOC_BGEEDB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BGEEDB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BGEEDB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BGEEDB.out.versions  // channel: path(versions.yml)
}
