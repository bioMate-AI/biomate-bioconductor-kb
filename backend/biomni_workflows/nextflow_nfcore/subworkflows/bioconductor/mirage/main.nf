#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MiRaGE
// The package contains functions for inferece of target gene regulation by miRNA, based on only target
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MiRaGE/inst/doc/MiRaGE.R
// Upstream  : Biobase, beadarrayExampleData, humanStemCell
// Downstream: none
//
// Install: BiocManager::install("MiRaGE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mirage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mirage:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mirage:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mirage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mirage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mirage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MiRaGE)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: MiRaGE
    library(MiRaGE)
    data(gene_exp)
    library(Biobase)
    result <- MiRaGE(gene_exp,species="HS")
    # --- Unevaluatedcode [] ---
    # Key functions: MiRaGE
    ## result <- MiRaGE(gene_exp,location="web",species="HS")
    # --- Data [] ---
    # Key functions: data
    data(gene_exp)
    gene_exp
    # --- Csv [] ---
    # Key functions: csv
    x_gene <- read.csv(system.file("extdata/x_all_7a.csv",package="MiRaGE"),sep="\t")
    x_gene[101:103,]
    # --- Data [] ---
    # Key functions: data
    require(humanStemCell)
    data(fhesc)
    # --- Pdata [] ---
    # Key functions: pData, fData, exprs
    pData(fhesc)[["sample_name"]] <- c("neg.1","neg.2","neg.3",
    "pos.1","pos.2","pos.3")
    fData(fhesc)[["gene_id"]] <-rownames(exprs(fhesc))
    # --- Mirage [] ---
    # Key functions: MiRaGE
    require(MiRaGE)
    result <- MiRaGE(fhesc,species="HS",ID="affy_hg_u133a_2")
    # --- Data [] ---
    # Key functions: data
    require(beadarrayExampleData)
    data(exampleBLData)
    data(exampleSummaryData)
    # --- Fdata [] ---
    # Key functions: fData, pData, MiRaGE
    vv <- exampleSummaryData[,1:12]
     fData(vv)[["gene_id"]] <- fData(exampleSummaryData)[["IlluminaID"]]
     pData(vv)[["sample_name"]] <- c("neg.1","neg.2","neg.3","neg.4",
    "neg.5","neg.6","brain.1","brain.2","brain.3","brain.4","brain.5","brain.6")
    result <- MiRaGE(vv,species="HS",ID="illumina_humanwg_6_v3")
    # --- Mirage [] ---
    # Key functions: MiRaGE
    ## result <- MiRaGE(...,species_force=F)
    # --- Data [] ---
    # Key functions: MiRaGE
    library(MiRaGE)
    data(gene_exp)
    library(Biobase)
    result <- MiRaGE(gene_exp,species="HS")
    # --- Unevaluatedcode [] ---
    # Key functions: id_conv_gen
    ## id_conv_gen(SP="MM")
    # --- Adjust [] ---
    # Key functions: adjust
    p.adjust(result$P1[,2],method="BH")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mirage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mirage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mirage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRAGE:", paste0("    mirage: ", packageVersion("MiRaGE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirage_results.csv
    touch ${prefix}_mirage_output.rds
    echo "BIOC_MIRAGE:" > versions.yml
    echo "    mirage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIRAGE(ch_input)

    emit:
    results  = BIOC_MIRAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRAGE.out.versions  // channel: path(versions.yml)
}
