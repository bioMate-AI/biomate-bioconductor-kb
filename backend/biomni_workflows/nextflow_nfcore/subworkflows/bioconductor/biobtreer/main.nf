#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biobtreeR
// The biobtreeR package provides an interface to [biobtree](https://github.com/tamerh/biobtree) tool w
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biobtreeR/inst/doc/biobtreeR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biobtreeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOBTREER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biobtreer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biobtreer:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biobtreer:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biobtreer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biobtreer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biobtreer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biobtreeR)
    library(jsonlite)

    # --- Bbuseoutdir [] ---
    # Key functions: bbUseOutDir, tempdir
    ---------------------------------------------------------------------
    library(biobtreeR)
    # Create an folder and set as an output directory
    # It is used for database and configuration files
    # temporary directory is used for demonstration purpose
    # --- Danio Rerio [] ---
    # Key functions: danio_rerio, gallus_gallus, bbBuiltInDB
    ---------------------------------------------------------------------
    # Called once and saves the built in database to local disk
    # Included datasets hgnc,hmdb,taxonomy,go,efo,eco,chebi,interpro
    # Included uniprot proteins and ensembl genomes belongs to following organisms:
    # homo_sapiens, danio_rerio(zebrafish), gallus_gallus(chicken), mus_musculus, Rattus norvegicus, saccharomyces_cerevisiae,
    # --- Bbstart [] ---
    # Key functions: bbStart
    ---------------------------------------------------------------------
     bbStart()
    # --- Bbsearch [] ---
    # Key functions: bbSearch
    ---------------------------------------------------------------------
    bbSearch("tpi1,vav_human,ENST00000297261")
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map
    ---------------------------------------------------------------------
    bbMapping("AT5G3_HUMAN",'map(go)',attrs = "type")
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map, filter
    ---------------------------------------------------------------------
    bbMapping("AT5G3_HUMAN",'map(go).filter(go.type=="biological_process")',attrs = "type")
    # --- Bblistattrs [] ---
    # Key functions: bbListAttrs
    ---------------------------------------------------------------------
    bbListAttrs("go")
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map
    ---------------------------------------------------------------------
    res<-bbMapping("ATP5MC3,TP53",'map(transcript)')
    head(res)
    # --- Bbmapping [] ---
    # Key functions: bbMapping, filter, map
    ---------------------------------------------------------------------
    res<-bbMapping("shh",'filter(ensembl.genome=="homo_sapiens").map(ortholog)')
    head(res)
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map
    ---------------------------------------------------------------------
    bbMapping("fry,mog",'map(paralog)',showInputColumn = TRUE)
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map, filter
    ---------------------------------------------------------------------
    res<-bbMapping("homo_sapiens",'map(ensembl).filter(ensembl.seq_region=="Y" && ensembl.biotype=="lncRNA")',attrs = 'name')
    head(res)
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map
    ---------------------------------------------------------------------
    bbMapping("tpi1,shh",'map(transcript).map(cds)')
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map, filter
    ---------------------------------------------------------------------
    bbMapping("9606",'map(ensembl).filter((114129278>ensembl.start && 114129278<ensembl.end) || (114129328>ensembl.start && 114129328<ensembl.end))',attrs = "name")
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map, filter, overlaps
    ---------------------------------------------------------------------
    bbMapping("9606",'map(ensembl).filter(ensembl.overlaps(114129278,114129328))',attrs = "name")
    # --- Bbmapping [] ---
    # Key functions: bbMapping, map
    ---------------------------------------------------------------------
    bbMapping("202763_at,213596_at,209310_s_at",source ="affy_hg_u133_plus_2" ,'map(transcript).map(ensembl)',attrs = "name")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biobtreer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biobtreer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biobtreer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOBTREER:", paste0("    biobtreer: ", packageVersion("biobtreeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biobtreer_results.csv
    touch ${prefix}_biobtreer_output.rds
    echo "BIOC_BIOBTREER:" > versions.yml
    echo "    biobtreer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOBTREER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOBTREER(ch_input)

    emit:
    results  = BIOC_BIOBTREER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOBTREER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOBTREER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOBTREER.out.versions  // channel: path(versions.yml)
}
