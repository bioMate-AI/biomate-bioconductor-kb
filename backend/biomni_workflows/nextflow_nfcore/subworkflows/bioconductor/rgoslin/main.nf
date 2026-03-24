#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rgoslin
// The R implementation for the Grammar of Succint Lipid Nomenclature parses different short hand notat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rgoslin/inst/doc/introduction.R
// Upstream  : dplyr, ggplot2, kableExtra, knitr, lipidr
// Downstream: none
//
// Install: BiocManager::install("rgoslin")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGOSLIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rgoslin"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rgoslin:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rgoslin:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rgoslin_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rgoslin_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rgoslin_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Phosphatidylcholines)
    library(TG)
    library(jsonlite)

    # --- Listavailablegrammars [] ---
    # Key functions: listAvailableGrammars
    ---------------------------------------------------------------------
    listAvailableGrammars()
    # --- Isvalidlipidname [] ---
    # Key functions: isValidLipidName
    ---------------------------------------------------------------------
    isValidLipidName("PC 32:1")
    # --- Parselipidnames [] ---
    # Key functions: parseLipidNames
    ---------------------------------------------------------------------
    df <- parseLipidNames("PC 32:1")
    # --- Tg [] ---
    # Key functions: TG, 1, 2, parseLipidNames
    ---------------------------------------------------------------------
    originalName <- "TG(16:1(5E)/18:0/20:2(3Z,6Z))"
    tagDf <- parseLipidNames(originalName, grammar = "LipidMaps")
    # --- Parselipidnames [] ---
    # Key functions: parseLipidNames, TG
    ---------------------------------------------------------------------
    multipleLipidNamesDf <- parseLipidNames(c("PC 32:1","LPC 34:1","TG(18:1_18:0_16:1)"))
    # --- Parselipidnames [] ---
    # Key functions: parseLipidNames, rowData
    ---------------------------------------------------------------------
    lipidNames <- parseLipidNames(rowData(d)$clean_name)
    # --- Rowdata [] ---
    # Key functions: rowData, potential, str_match, group, str_replace_all, parseLipidNames
    ---------------------------------------------------------------------
    # lipidr stores original lipid names in the Molecule column
    old_names <- rowData(d)$Molecule
    # split lipid prefix from potential (d7) suffix for labeled internal standards
    new_names <- rowData(d)$clean_name %>% str_match(pattern="([\\w :-]+)(\\(\\w+\\))?")
    # --- Update Molecule Names [] ---
    # Key functions: update_molecule_names
    ---------------------------------------------------------------------
    updated <- update_molecule_names(d, old_names, normalized_new_names$Normalized.Name)
    # --- Rowdata [] ---
    # Key functions: rowData, Phosphatidylcholines
    ---------------------------------------------------------------------
    rowData(updated)$Class <- normalized_new_names$Lipid.Maps.Main.Class
    rowData(updated)$Category <- normalized_new_names$Lipid.Maps.Category
    rowData(updated)$Molecule <- normalized_new_names$Normalized.Name
    rowData(updated)$LipidSpecies <- normalized_new_names$Species.Name
    # --- To Long Format [] ---
    # Key functions: to_long_format, ggplot, aes, geom_boxplot, facet_wrap, scale_y_log10, coord_flip
    ---------------------------------------------------------------------
    ddf <- lipidr:::to_long_format(d)
    ggplot(data=ddf, mapping=aes(x=Molecule, y=Area, fill=Class)) + geom_boxplot() + facet_wrap(~filename, scales = "free_y") + scale_y_log10() + coord_flip()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rgoslin_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rgoslin_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rgoslin_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RGOSLIN:", paste0("    rgoslin: ", packageVersion("rgoslin"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgoslin_results.csv
    touch ${prefix}_rgoslin_output.rds
    echo "BIOC_RGOSLIN:" > versions.yml
    echo "    rgoslin: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RGOSLIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RGOSLIN(ch_input)

    emit:
    results  = BIOC_RGOSLIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RGOSLIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RGOSLIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RGOSLIN.out.versions  // channel: path(versions.yml)
}
