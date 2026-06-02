#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regioneR
// regioneR offers a statistical framework based on customizable permutation tests to assess the associ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regioneR/inst/doc/regioneR.R
// Upstream  : knitr
// Downstream: karyoploteR, regioneReloaded
//
// Install: BiocManager::install("regioneR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regioner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regioner:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regioner:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regioner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regioner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regioner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(regioneR)
    library(jsonlite)

    # --- Genome and Chromosome Filtering [] ---
    # Key functions: getGenome, filterChromosomes, createRandomRegions
    hg19_genome <- getGenome("hg19")
    autosomal_genome <- filterChromosomes(
        hg19_genome,
        organism = "hg",
        chr.type = "autosomal"
    )
    random_regions <- createRandomRegions(
        nregions = 100,
        length.mean = 50000,
        genome = autosomal_genome
    )


    # --- Overlap Permutation Testing [] ---
    # Key functions: overlapPermTest, numOverlaps, randomizeRegions
    region_a <- createRandomRegions(
        nregions = 50,
        length.mean = 5000000,
        length.sd = 3000000
    )
    region_b <- randomizeRegions(region_a)
    overlap_count <- numOverlaps(region_a, region_b, count.once = TRUE)
    pt_results <- overlapPermTest(
        A = region_a,
        B = region_b,
        ntimes = 50,
        verbose = FALSE
    )


    # --- Custom Resampling and Permutation Testing [] ---
    # Key functions: permTest, resampleRegions, numOverlaps
    special_regions <- createRandomRegions(nregions = 30, length.mean = 10000)
    all_genes <- createRandomRegions(nregions = 500, length.mean = 20000)
    altered_regions <- createRandomRegions(nregions = 40, length.mean = 15000)
    pt_resample <- permTest(
        A = special_regions,
        ntimes = 50,
        randomize.function = resampleRegions,
        universe = all_genes,
        evaluate.function = numOverlaps,
        B = altered_regions,
        verbose = FALSE
    )


    # --- Local Z-Score Analysis [] ---
    # Key functions: localZScore, permTest, randomizeRegions, plot
    reg_a <- createRandomRegions(nregions = 20, length.mean = 10000)
    reg_b <- createRandomRegions(nregions = 20, length.mean = 10000)
    pt_res <- permTest(
        A = reg_a, ntimes = 20,
        randomize.function = randomizeRegions,
        evaluate.function = numOverlaps, B = reg_b,
        verbose = FALSE
    )
    lz_score <- localZScore(
        A = reg_a, pt = pt_res,
        window = 50000, step = 5000, B = reg_b
    )
    plot(lz_score)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regioner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regioner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regioner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONER:", paste0("    regioner: ", packageVersion("regioneR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regioner_results.csv
    touch ${prefix}_regioner_output.rds
    echo "BIOC_REGIONER:" > versions.yml
    echo "    regioner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGIONER(ch_input)

    emit:
    results  = BIOC_REGIONER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONER.out.versions  // channel: path(versions.yml)
}
