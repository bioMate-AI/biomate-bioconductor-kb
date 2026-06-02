#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Pedixplorer
// Routines to handle family data with a Pedigree object. The initial purpose was to create correlation
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Pedixplorer/inst/doc/Pedixplorer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Pedixplorer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PEDIXPLORER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pedixplorer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pedixplorer:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pedixplorer:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_pedixplorer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pedixplorer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pedixplorer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Pedixplorer)
    library(jsonlite)


    # --- Pedigree Creation [] ---
    # Key functions: Pedigree, sampleped, famid, ped, summary, sex
    data("sampleped")
    print(sampleped[1:10, ])
    ped <- Pedigree(sampleped[c(3, 4, 10, 35, 36), ])
    print(ped)
    ped <- Pedigree(sampleped)
    print(famid(ped(ped)))
    ped1 <- ped[famid(ped(ped)) == "1"]
    summary(ped1)
    plot(ped1, cex = 0.7)
    plot(
        ped1, title = "Pedigree 1",
        legend = TRUE, leg_loc = c(7, 16, 1.05, 1.9),
        cex = 0.7
    )
    datped2 <- sampleped[sampleped$famid == 2, ]
    datped2[datped2$id %in% 203, "sex"] <- 2
    datped2 <- datped2[-which(datped2$id %in% 209), ]

    # --- Fixped2 [] ---
    # Key functions: Pedigree, with, fix_parents, kinship, relped
    tryout <- try({
        ped2 <- Pedigree(datped2)
    })
    fixped2 <- with(datped2, fix_parents(id, dadid, momid, sex))
    fixped2
    ped2 <- Pedigree(fixped2)
    plot(ped2)
    kin2 <- kinship(ped2)
    kin2[1:9, 1:9]
    ped <- Pedigree(sampleped)
    kin_all <- kinship(ped)
    kin_all[1:9, 1:9]
    kin_all[40:43, 40:43]
    kin_all[42:46, 42:46]
    data("relped")
    relped
    ped <- Pedigree(sampleped, relped)

    kin_all <- kinship(ped)
    kin_all[24:27, 24:27]

    # --- Status [] ---
    # Key functions: rep, Pedigree, summary, status, ped, mcols, generate_colors, par
    df2 <- sampleped[sampleped$famid == 2, ]
    names(df2)
    df2$status <- c(1, 1, rep(0, 12))
    ped2 <- Pedigree(df2)
    summary(status(ped(ped2)))
    plot(ped2)
    mcols(ped2)$Names <- c(
        "John\nDalton", "Linda", "Jack", "Rachel", "Joe", "Deb",
        "Lucy", "Ken", "Barb", "Mike", "Matt",
        "Mindy", "Mark", "Marie\nCurie"
    )
    plot(ped2, label = "Names", cex = 0.7)
    mcols(ped2)$bald <- as.factor(c(0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1))
    ped2 <- generate_colors(ped2, col_aff = "bald", add_to_scale = TRUE)
    # Increase down margin for the legend
    op <- par(mai = c(1.5, 0.2, 0.2, 0.2))
    plot(
        ped2, legend = TRUE,
        leg_loc = c(0.5, 6, 3.5, 4)
    )

    # --- Inbreeding [] ---
    # Key functions: rbind.data.frame, Pedigree, rel, with, Rel, upd_famid
    indid <- 195:202
    dadid <- c(NA, NA, NA, 196, 196, NA, 197, 199)
    momid <- c(NA, NA, NA, 195, 195, NA, 198, 200)
    sex <- c(2, 1, 1, 2, 1, 2, 1, 2)
    ped3 <- data.frame(
        id = indid, dadid = dadid,
        momid = momid, sex = sex
    )

    ped4df <- rbind.data.frame(df2[-c(1, 2), 2:5], ped3)
    ## create twin relationships
    rel_df2 <- data.frame(
        id1 = "211",
        id2 = "212",
        code = 4,
        famid = "2"
    )
    new_rel <- c(rel(ped2), with(rel_df2, Rel(id1, id2, code, famid)))
    rel(ped2) <- upd_famid(new_rel)
    plot(ped2)

    # --- Generate Colors [] ---
    # Key functions: scales, generate_colors, fill, border, num, blue, green, yellow
    scales(ped1)
    ped1 <- generate_colors(
        ped1, col_aff = "num",
        add_to_scale = TRUE, is_num = TRUE,
        keep_full_scale = TRUE, breaks = 2,
        colors_aff = c("blue", "green"),
        colors_unaff = c("yellow", "brown"),
        threshold = 3, sup_thres_aff = FALSE
    )

    data(sampleped)
    ped1 <- Pedigree(sampleped)

    ped1 <- useful_inds(ped1, informative = c("1_110", "1_120"), max_dist = 1)
    print(useful(ped(ped1)))
    ped_filtered <- ped1[useful(ped(ped1))]
    plot(ped_filtered)
    ped2_rm210 <- ped2[-10]
    rel(ped2_rm210)
    rel(ped2)

    # --- Shrink1 [] ---
    # Key functions: shrink, Pedigree, unrelated, kinship, ped, avail, sessionInfo
    set.seed(200)
    shrink1_b30 <- shrink(ped1, max_bits = 30)
    print(shrink1_b30[c(2:8)])
    plot(shrink1_b30$pedObj)
    set.seed(10)
    shrink1_b25 <- shrink(ped1, max_bits = 25)
    print(shrink1_b25[c(2:8)])
    plot(shrink1_b25$pedObj)
    ped2 <- Pedigree(df2)
    set.seed(10)
    set1 <- unrelated(ped2)
    set1
    set2 <- unrelated(ped2)
    set2
    kin2 <- kinship(ped2)
    is_avail <- id(ped(ped2))[avail(ped(ped2))]
    kin2
    kin2[is_avail, is_avail]

    ## -------------------------------------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pedixplorer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pedixplorer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pedixplorer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PEDIXPLORER:", paste0("    pedixplorer: ", packageVersion("Pedixplorer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pedixplorer_results.csv
    touch ${prefix}_pedixplorer_output.rds
    echo "BIOC_PEDIXPLORER:" > versions.yml
    echo "    pedixplorer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PEDIXPLORER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_PEDIXPLORER(ch_input)

    emit:
    results  = BIOC_PEDIXPLORER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PEDIXPLORER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PEDIXPLORER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PEDIXPLORER.out.versions  // channel: path(versions.yml)
}
