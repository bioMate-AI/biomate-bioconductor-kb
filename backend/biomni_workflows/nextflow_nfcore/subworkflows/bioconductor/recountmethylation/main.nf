#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: recountmethylation
// Resources for cross-study analyses of public DNAm array data from NCBI GEO repo, produced using Illu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/recountmethylation/inst/doc/cpg_probe_annotations.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("recountmethylation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECOUNTMETHYLATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-recountmethylation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-recountmethylation:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-recountmethylation:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_recountmethylation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_recountmethylation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_recountmethylation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(recountmethylation)
    library(Body)
    library(TSS1500)
    library(TSS200)
    library(UTR)
    library(jsonlite)

    # --- Preprocessing and SNP Filtering [] ---
    # Key functions: preprocessRaw, mapToGenome, dropLociWithSnps
    gm <- minfi::preprocessRaw(rg)
    gms <- minfi::mapToGenome(gm)
    gmsf <- minfi::dropLociWithSnps(gms)


    # --- Gene-Centric Probe Filtering [] ---
    # Key functions: grepl, strsplit
    gene.str <- "ARID1A"
    gene.patt <- paste0("(^|;)", gene.str, "($|;)")
    which.gene <- which(grepl(gene.patt, man$UCSC_RefGene_Name))
    manf <- man[which.gene, ]
    gene.regionv <- unlist(strsplit(man$UCSC_RefGene_Group, ";"))


    # --- Promoter and Gene Body Mapping [] ---
    # Key functions: grepl, table
    prom.catv <- c("5'UTR", "TSS1500", "TSS200")
    prom.patt <- paste0("(^|;)", prom.catv, "($|;)", collapse = "|")
    man$promoter <- ifelse(grepl(prom.patt, man$UCSC_RefGene_Group),
                           TRUE, FALSE)
    body.catv <- c("Body", "3'UTR")
    body.patt <- paste0("(^|;)", body.catv, "($|;)", collapse = "|")
    man$gene_body <- ifelse(grepl(body.patt, man$UCSC_RefGene_Group),
                            TRUE, FALSE)


    # --- CpG Island and Genic Status Analysis [] ---
    # Key functions: table, ggplot
    dfp <- as.data.frame(table(man$Relation_to_Island,
                               man$UCSC_RefGene_Name == ""))
    dfp$region <- paste0(dfp$Var1, " ; ",
                         c(rep("genic", 6), rep("intergenic", 6)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_recountmethylation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_recountmethylation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_recountmethylation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RECOUNTMETHYLATION:", paste0("    recountmethylation: ", packageVersion("recountmethylation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recountmethylation_results.csv
    touch ${prefix}_recountmethylation_output.rds
    echo "BIOC_RECOUNTMETHYLATION:" > versions.yml
    echo "    recountmethylation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RECOUNTMETHYLATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RECOUNTMETHYLATION(ch_input)

    emit:
    results  = BIOC_RECOUNTMETHYLATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RECOUNTMETHYLATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RECOUNTMETHYLATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RECOUNTMETHYLATION.out.versions  // channel: path(versions.yml)
}
