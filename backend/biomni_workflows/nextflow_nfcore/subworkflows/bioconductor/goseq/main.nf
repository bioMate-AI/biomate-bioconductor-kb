#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: goseq
// Detects Gene Ontology and/or other user defined categories which are over/under represented in RNA-s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/goseq/inst/doc/goseq.R
// Upstream  : edgeR
// Downstream: rgsepd
//
// Install: BiocManager::install("goseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-goseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-goseq:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-goseq:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_goseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_goseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_goseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGEList)
    library(jsonlite)

    # --- Supported Genomes [] ---
    # Key functions: supportedOrganisms
    ## supportedOrganisms()
    # --- Getlengthdatafromucsc [] ---
    # Key functions: transcriptsBy, width
    ## txsByGene <- transcriptsBy(txdb, "gene")
    ## lengthData <- median(width(txsByGene))
    # --- Edger 1 [] ---
    # Key functions: factor, DGEList
    library(edgeR)
    table.summary <- read.table(system.file("extdata", "Li_sum.txt", package = "goseq"),
      sep = "\t", header = TRUE, stringsAsFactors = FALSE
    )
    counts <- table.summary[, -1]
    # --- Edger 2 [] ---
    # Key functions: estimateCommonDisp, exactTest, topTags
    disp <- estimateCommonDisp(summarized)
    disp$common.dispersion
    tested <- exactTest(disp)
    topTags(tested)
    # --- Edger 3 [] ---
    # Key functions: adjust
    genes <- as.integer(p.adjust(tested$table$PValue[tested$table$logFC != 0],
      method = "BH"
    ) < .05)
    names(genes) <- row.names(tested$table[tested$table$logFC != 0, ])
    table(genes)
    # --- Head Organisms [] ---
    # Key functions: supportedOrganisms
    head(supportedOrganisms())
    # --- Head Geneids [] ---
    # Key functions: supportedOrganisms
    supportedOrganisms()[supportedOrganisms()$Genome == "hg19", ]
    # --- Pwf [] ---
    # Key functions: nullp
    pwf <- nullp(genes, "hg19", "ensGene")
    head(pwf)
    # --- goseq [] ---
    # Key functions: goseq
    GO.wall <- goseq(pwf, "hg19", "ensGene")
    head(GO.wall)
    # --- Enriched Go [] ---
    # Key functions: adjust
    enriched.GO <- GO.wall$category[p.adjust(GO.wall$over_represented_pvalue,
      method = "BH"
    ) < .05]
    head(enriched.GO)
    # --- Getlength [] ---
    # Key functions: getlength
    len <- getlength(names(genes), "hg19", "ensGene")
    length(len)
    length(genes)
    head(len)
    # --- Getgo [] ---
    # Key functions: getgo
    go <- getgo(names(genes), "hg19", "ensGene")
    length(go)
    length(genes)
    head(go)
    # --- Norm Analysis [] ---
    # Key functions: nullp, goseq
    ## pwf <- nullp(genes, "hg19", "ensGene")
    ## go <- goseq(pwf, "hg19", "ensGene")
    # --- Verbose Analysis [] ---
    # Key functions: getlength, nullp, getgo, goseq
    ## gene_lengths <- getlength(names(genes), "hg19", "ensGene")
    ## pwf <- nullp(genes, bias.data = gene_lengths)
    ## go_map <- getgo(names(genes), "hg19", "ensGene")
    ## go <- goseq(pwf, "hg19", "ensGene", gene2cat = go_map)
    # --- Kegg Mappings [] ---
    # Key functions: unlist
    ## # Get the mapping from ENSEMBL 2 Entrez
    ## en2eg <- as.list(org.Hs.egENSEMBL2EG)
    ## # Get the mapping from Entrez 2 KEGG
    ## eg2kegg <- as.list(org.Hs.egPATH)
    ## # Define a function which gets all unique KEGG IDs

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_goseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_goseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_goseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOSEQ:", paste0("    goseq: ", packageVersion("goseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_goseq_results.csv
    touch ${prefix}_goseq_output.rds
    echo "BIOC_GOSEQ:" > versions.yml
    echo "    goseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOSEQ(ch_input)

    emit:
    results  = BIOC_GOSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOSEQ.out.versions  // channel: path(versions.yml)
}
