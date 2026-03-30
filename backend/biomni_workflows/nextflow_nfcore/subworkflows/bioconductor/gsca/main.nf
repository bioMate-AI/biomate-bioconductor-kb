#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSCA
// GSCA takes as input several lists of activated and repressed genes. GSCA then searches through a com
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSCA/inst/doc/GSCA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GSCA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsca:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsca:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSCA)
    library(GSCAeda)
    library(GSCAplot)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(GSCA)
    data(Oct4ESC_TG)
    head(Oct4ESC_TG[[1]]) ##Show some positive target genes of Oct4
    head(Oct4ESC_TG[[2]]) ##Show some negative target genes of Oct4
    # --- Frame [] ---
    # Key functions: frame
    Octpattern <- data.frame(
          gsname=c("TF","TG"),
          acttype="High",
          cotype="Norm",
          cutoff=0.1,
    # --- Gsca [] ---
    # Key functions: GSCA
    displayoct <- Octoutput <- GSCA(Octgenedata,Octpattern,"moe4302",Pval.co=0.05,directory=NULL)
    displayoct[[1]]$SampleType <- substr(displayoct[[1]]$SampleType,1,25)
    head(displayoct[[1]]) ## Partial results of the ranking table
    # --- Gscaplot [] ---
    # Key functions: GSCAplot
    GSCAplot(Octoutput,N=5,plotfile=NULL,Title="GSCA plot of Oct4 in ESC")
    # --- Data [] ---
    # Key functions: activated
    data(STAT1_TG) ### Note, only activated (+) STAT1 target genes were found
    # --- Gsca [] ---
    # Key functions: GSCA
    Statoutput <- GSCA(Statgenedata,Statpattern,"hgu133a",Pval.co=0.05,directory=NULL)
    head(Statoutput[[1]])
    # --- Tabsearch [] ---
    # Key functions: tabSearch
    GSE7123out <- tabSearch("GSE7123","hgu133a")
    GSE7123out
    # --- Gscaeda [] ---
    # Key functions: GSCAeda
    GSE7123followup <- GSCAeda(Statgenedata,Statpattern,"hgu133a",GSE7123out,Pval.co=0.05,Ordering="Average",Title=NULL,outputdir=NULL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSCA:", paste0("    gsca: ", packageVersion("GSCA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsca_results.csv
    touch ${prefix}_gsca_output.rds
    echo "BIOC_GSCA:" > versions.yml
    echo "    gsca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSCA(ch_input)

    emit:
    results  = BIOC_GSCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSCA.out.versions  // channel: path(versions.yml)
}
