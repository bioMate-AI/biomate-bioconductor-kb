#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: knowYourCG
// knowYourCG automates the functional analysis of DNA methylation data. The package tests the enrichme
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/knowYourCG/inst/doc/Array.R
// Upstream  : sesameData, SummarizedExperiment, gprofiler2, knitr, sesame
// Downstream: none
//
// Install: BiocManager::install("knowYourCG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-knowyourcg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-knowyourcg:1.2.5--r44_0' :
        'quay.io/biocontainers/bioconductor-knowyourcg:1.2.5--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_knowyourcg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_knowyourcg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_knowyourcg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(knowYourCG)
    library(jsonlite)


    # --- Ky1 [] ---
    # Key functions: sesameDataCache, genomeInfo.hg38, genomeInfo.mm10, probeIDSignature, getDBs
    library(knowYourCG)
    library(sesameData)
    # --- Ky3 [] ---
    # Key functions: testEnrichment, listDBGroups
    dbs <- c("KYCG.MM285.chromHMM.20210210",
             "KYCG.HM450.TFBSconsensus.20211013",
             "KYCG.MM285.HMconsensus.20220116",
             "KYCG.MM285.tissueSignature.20211211",
             "KYCG.MM285.chromosome.mm10.20210630",
             "KYCG.MM285.designGroup.20210210")
    results_pgc <- testEnrichment(query,databases = dbs,platform="MM285")
    head(results_pgc)
    listDBGroups("MM285")

    # --- Ky6 [] ---
    # Key functions: getDBs, str
    dbs <- getDBs("MM285.design")
    str(dbs[["PGCMeth"]])

    # --- Ky10 [] ---
    # Key functions: rowData, sesameDataGet, testEnrichment, filter, select, fetal_brain, fetal_liver, B_cell
    library(SummarizedExperiment)

    ## prepare a query
    df <- rowData(sesameDataGet('MM285.tissueSignature'))
    query <- df$Probe_ID[df$branch == "fetal_brain" & df$type == "Hypo"]

    results <- testEnrichment(query, "TFBS", platform="MM285")
    results %>% dplyr::filter(overlap>10) %>% head

    ## prepare another query
    df <- rowData(sesameDataGet('MM285.tissueSignature'))
    query <- df$Probe_ID[df$branch == "B_cell"]
    head(query)

    # --- Ky16 [] ---
    # Key functions: sesameData_getProbesByGene, testEnrichment, buildGeneDBs, dbname, estimate, gene_name, overlap
    library(knowYourCG)
    library(sesameData)
    library(SummarizedExperiment)
    query <- names(sesameData_getProbesByGene("Dnmt3a", "MM285"))
    results <- testEnrichment(query, 
        buildGeneDBs(query, max_distance=100000, platform="MM285"),
        platform="MM285")
    main_stats <- c("dbname","estimate","gene_name","FDR", "nQ", "nD", "overlap")
    results[,main_stats]
    query <- names(sesameData_getProbesByGene("Dnmt3a", "MM285"))
    dbs <- c("KYCG.MM285.chromHMM.20210210","KYCG.HM450.TFBSconsensus.20211013",
             "KYCG.MM285.chromosome.mm10.20210630")
    results <- testEnrichment(query,databases=dbs,
                              platform="MM285",include_genes=TRUE)
    main_stats <- c("dbname","estimate","gene_name","FDR", "nQ", "nD", "overlap")
    results[,main_stats] %>% 
        head()

    # --- Ky18 [] ---
    # Key functions: rowData, sesameDataGet, testGO, fetal_liver, mmusculus, testProbeProximity, sessionInfo
    library(gprofiler2)
    df <- rowData(sesameDataGet('MM285.tissueSignature'))
    query <- df$Probe_ID[df$branch == "fetal_liver" & df$type == "Hypo"]
    res <- testGO(query, platform="MM285",organism = "mmusculus")
    head(res$result)
    df <- rowData(sesameDataGet('MM285.tissueSignature'))
    probes <- df$Probe_ID[df$branch == "fetal_liver" & df$type == "Hypo"]
    res <- testProbeProximity(probeIDs=probes)
    head(res)

    ## -----------------------------------------------------------------------------
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_knowyourcg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_knowyourcg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_knowyourcg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KNOWYOURCG:", paste0("    knowyourcg: ", packageVersion("knowYourCG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_knowyourcg_results.csv
    touch ${prefix}_knowyourcg_output.rds
    echo "BIOC_KNOWYOURCG:" > versions.yml
    echo "    knowyourcg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KNOWYOURCG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KNOWYOURCG(ch_input)

    emit:
    results  = BIOC_KNOWYOURCG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KNOWYOURCG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KNOWYOURCG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KNOWYOURCG.out.versions  // channel: path(versions.yml)
}
