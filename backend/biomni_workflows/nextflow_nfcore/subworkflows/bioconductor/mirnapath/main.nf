#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miRNApath
// This package provides pathway enrichment techniques for miRNA expression data. Specifically, the set
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miRNApath/inst/doc/miRNApath.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("miRNApath")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRNAPATH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mirnapath"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mirnapath:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mirnapath:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mirnapath_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mirnapath_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mirnapath_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(miRNApath)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: loadmirnapath
    ## Start with miRNA data from this package
    data(mirnaobj);
    ## Write a file as example of required input
    # --- Filtermirnapath [] ---
    # Key functions: filtermirnapath
    mirnaobj <- filtermirnapath( mirnaobj, pvalue=0.05,
        expression=NA, foldchange=NA );
    # --- Data [] ---
    # Key functions: frame
    ## Again we load data from the package
    data(mirnaobj);
    ## Write a file as example of required miRNA-gene input
    # --- Loadmirnatogene [] ---
    # Key functions: loadmirnatogene
    ## Load the miRNA to gene associations
    mirnaobj <- loadmirnatogene( mirnafile="mirnaGene.txt",
        mirnaobj=mirnaobj, mirnacol="miRNA Name",
        genecol="Entrez Gene ID",
        columns=c(assayidcol="ASSAYID") );
    # --- Data [] ---
    # Key functions: data
    ## Again we load data from the package
    data(mirnaobj);
    ## Write a file as example of required input
    # --- Loadmirnapathways [] ---
    # Key functions: loadmirnapathways
    ## Load the gene to pathway associations
    mirnaobj <- loadmirnapathways( mirnaobj=mirnaobj,
        pathwayfile="mirnaPathways.txt",
        pathwaycol="Pathway Name", genecol="Entrez Gene ID");
    ## Display summary, noting the number of pathways reported
    # --- Unique [] ---
    # Key functions: runEnrichment
    Groups = unique(mirnaobj@mirnaTable[,
    	mirnaobj@columns["groupcol"] ]);
    mirnaobj <- runEnrichment( mirnaobj=mirnaobj, Composite=TRUE,
       groups=Groups[grep("^AD.+(UP|DOWN)",Groups)], permutations=0 );
    # --- Mirnatable [] ---
    # Key functions: mirnaTable
    finaltable <- mirnaTable( mirnaobj, groups=NULL, format="Tall",
       Significance=0.1, pvalueTypes=c("pvalues","permpvalues"),
       maxStringLength=42 );
    ## Display only the first few rows of the best P-values...
    finaltable[sort(finaltable[,"pvalues"], index.return=TRUE)$ix,][1:5,];
    # --- Heatmap [] ---
    # Key functions: mirnaTable, na
    ## Example which calls heatmap function on the resulting data
    widetable <- mirnaTable( mirnaobj, groups=NULL, format="Wide",
        Significance=0.3, na.char=NA, pvalueTypes=c("pvalues") );
    ## Assign 1 to NA values, assuming they're all equally
    ## non-significant
    # --- Newpage [] ---
    # Key functions: newpage
    ## grid.newpage()
    ##

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mirnapath_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mirnapath_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mirnapath_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRNAPATH:", paste0("    mirnapath: ", packageVersion("miRNApath"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirnapath_results.csv
    touch ${prefix}_mirnapath_output.rds
    echo "BIOC_MIRNAPATH:" > versions.yml
    echo "    mirnapath: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRNAPATH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIRNAPATH(ch_input)

    emit:
    results  = BIOC_MIRNAPATH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRNAPATH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRNAPATH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRNAPATH.out.versions  // channel: path(versions.yml)
}
