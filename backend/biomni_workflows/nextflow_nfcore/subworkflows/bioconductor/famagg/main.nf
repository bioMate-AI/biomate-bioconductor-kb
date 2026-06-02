#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FamAgg
// Framework providing basic pedigree analysis and plotting utilities as well as a variety of methods t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FamAgg/inst/doc/FamAgg.R
// Upstream  : BiocStyle, gap
// Downstream: none
//
// Install: BiocManager::install("FamAgg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FAMAGG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-famagg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-famagg:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-famagg:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_famagg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_famagg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_famagg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FamAgg)
    library(jsonlite)


    # --- Libraries [] ---
    # Key functions: FAData, pedigree, father, age, famid, fatherid, motherid, sex
    library(FamAgg)

    data(minnbreast)
    ## Subsetting to only few families of the whole data set.
    mbsub <- minnbreast[minnbreast$famid %in% 4:14, ]
    mbped <- mbsub[, c("famid", "id", "fatherid", "motherid", "sex")]
    ## Renaming column names.
    colnames(mbped) <- c("family", "id", "father", "mother", "sex")
    ## Defining the optional argument age.
    endage <- mbsub$endage
    ## Extract the pedigree information from family "4"...
    nrow(family(fad, family = 4))

    head(family(fad, family = 4))

    ## ...which is the same as extracting the family pedigree
    ## for an individual of this family.
    head(family(fad, id = 3))

    ## Note that IDs are internally always converted to character,

    # --- Subsetting [] ---
    # Key functions: switchPlotfun, plotPed, ks2paint
    ## Subset the object to a single family.
    fam4 <- fad[fad$family == "4", ]
    table(fam4$family)
    switchPlotfun("ks2paint")
    ## By supplying device="plot", we specify that we wish to visualize the
    ## pedigree in an R plot. This is the default for "ks2paint", anyway.
    plotPed(fad, id = 3, device = "plot")

    # --- Build Ped [] ---
    # Key functions: buildPed, plotPed, findFounders
    ## Build the pedigree for individual 3.
    fullPed <- buildPed(fad, id = "3")
    nrow(fullPed)

    ## ----buildPed-prune, message = FALSE------------------------------------------
    ## Find the subpedigree for individuals 21, 22 and 17.
    buildPed(fad, id = c(21, 22, 17), prune = TRUE)

    ## ----plotPed-3ids, message=FALSE, fig.align='center', warning = FALSE---------
    plotPed(fad, id = c(21, 22, 17), prune = TRUE)
    ## Find founders for family 4.
    findFounders(fad, "4")

    # --- Get Common Ancestors [] ---
    # Key functions: getCommonAncestor, getChildren, getAncestors, getSiblings, trait, affectedIndividuals, function, findFounders
    ## Find the closest common ancestor.
    getCommonAncestor(fad, id = c(21, 22, 17))

    ## ----getChildren-and-others, message = FALSE----------------------------------
    ## Get the children of ID 4.
    getChildren(fad, id = "4", max.generations = 1)

    ## Get the offsprings.
    getChildren(fad, id = "4")

    ## Get all individuals sharing kinship with individual 4.
    shareKinship(fad, id = "4")

    # --- Share Kinship Rm [] ---
    # Key functions: shareKinship, estimateGenerations
    ## Get all individuals sharing kinship with individual 4, but only with kinship
    ## higher than 0.125 (exclude first cousins, grand children, great grand
    ## parents etc, i.e. everybody with kinship 0.125 or lower)
    shareKinship(fad, id = "4", rmKinship = 0.125)
    ## Estimate generation levels for all families.
    estimateGenerations(fad)[1:3]

    # --- Generations From [] ---
    # Key functions: generationsFrom, plotPed, trait, affectedIndividuals, phenotypedIndividuals
    gens <- generationsFrom(fad, id = "4")

    ## ----plotPed-with-generations, message=FALSE, fig.align='center', warning = FALSE----
    plotPed(fad, family = 4, label2 = gens)

    ## ----set-trait, results='hide', message=FALSE---------------------------------
    ## Extract the cancer trait information.
    tcancer <- mbsub$cancer
    names(tcancer) <- mbsub$id
    ## Set the trait.
    ## Extract the trait information.
    head(trait(fad))

    ## We can also extract the IDs of the affected individuals.
    head(affectedIndividuals(fad))

    ## Or the IDs of the phenotyped individuals.
    head(phenotypedIndividuals(fad))

    ## ----plotPed-with-trait, message=FALSE, fig.align='center', warning = FALSE----

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_famagg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_famagg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_famagg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FAMAGG:", paste0("    famagg: ", packageVersion("FamAgg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_famagg_results.csv
    touch ${prefix}_famagg_output.rds
    echo "BIOC_FAMAGG:" > versions.yml
    echo "    famagg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FAMAGG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FAMAGG(ch_input)

    emit:
    results  = BIOC_FAMAGG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FAMAGG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FAMAGG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FAMAGG.out.versions  // channel: path(versions.yml)
}
