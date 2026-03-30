#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SCANVIS
// SCANVIS is a set of annotation-dependent tools for analyzing splice junctions and their read support
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SCANVIS/inst/doc/runningSCANVIS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SCANVIS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCANVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scanvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scanvis:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scanvis:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scanvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scanvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scanvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SCANVISlinkvar)
    library(SCANVISscan)
    library(SCANVISvisual)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(SCANVIS)
    data(SCANVISexamples)
    names(gen19)
    # --- Head [] ---
    # Key functions: SCANVISscan
    ---------------------------------------------------------------------
    head(gbm3)
    gbm3.scn<-SCANVISscan(sj=gbm3,gen=gen19,Rcut=5,bam=NULL,samtools=NULL)
    head(gbm3.scn)
    # --- Head [] ---
    # Key functions: SCANVISlinkvar
    ---------------------------------------------------------------------
    head(gbm3.vcf)
    gbm3.scnv<-SCANVISlinkvar(gbm3.scn,gbm3.vcf,gen19)
    gbm3.scnv[10:23,]
    # --- Scanvislinkvar [] ---
    # Key functions: SCANVISlinkvar
    ---------------------------------------------------------------------
    gbm3.scnvp<-SCANVISlinkvar(gbm3.scn,gbm3.vcf,gen19,p=100)
    table(gbm3.scnv[,'passedMUT'])
    table(gbm3.scnvp[,'passedMUT'])
    # --- Tail [] ---
    # Key functions: SCANVISvisual
    ---------------------------------------------------------------------
    ASJ<-tail(vis.lusc2[[2]])[,1:3]
    c2<-SCANVISvisual('PPA2',gen19,LUSC[[2]],TITLE=names(LUSC)[2],full.annot=TRUE,SJ.special=ASJ)
    # --- Scanvisvisual [] ---
    # Key functions: SCANVISvisual
    ---------------------------------------------------------------------
    vis.lusc.merged<-SCANVISvisual('PPA2',gen19,LUSC,TITLE='Two LUSC samples, merged',full.annot=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scanvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scanvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scanvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCANVIS:", paste0("    scanvis: ", packageVersion("SCANVIS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scanvis_results.csv
    touch ${prefix}_scanvis_output.rds
    echo "BIOC_SCANVIS:" > versions.yml
    echo "    scanvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCANVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCANVIS(ch_input)

    emit:
    results  = BIOC_SCANVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCANVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCANVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCANVIS.out.versions  // channel: path(versions.yml)
}
