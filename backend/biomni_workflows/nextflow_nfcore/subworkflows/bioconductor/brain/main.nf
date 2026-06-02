#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BRAIN
// Package for calculating aggregated isotopic distribution and exact center-masses for chemical substa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BRAIN/inst/doc/BRAIN-vignette.R
// Upstream  : lattice
// Downstream: none
//
// Install: BiocManager::install("BRAIN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BRAIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-brain"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-brain:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-brain:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_brain_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_brain_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_brain_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BRAIN)
    library(jsonlite)

    # --- Brain Vignette.Rnw:67 76 [] ---
    # Key functions: calculateMonoisotopicMass
    #angiotensineII
    angiotensineII <- list(C=50,H=71,N=13,O=12)
    monoisotopicMassAngiotensineII <- calculateMonoisotopicMass(aC = angiotensineII)
    monoisotopicMassAngiotensineII
    #human dynein heavy chain
    # --- Brain Vignette.Rnw:91 98 [] ---
    # Key functions: calculateAverageMass
    #angiotensineII
    averageMassAngiotensineII <- calculateAverageMass(aC = angiotensineII)
    averageMassAngiotensineII
    #humandynein
    averageMassHumandynein <- calculateAverageMass(aC = humandynein)
    # --- Brain Vignette.Rnw:104 112 [] ---
    # Key functions: calculateNrPeaks
    #angiotensineII
    nrPeaksAngiotensineII <- calculateNrPeaks(aC = angiotensineII)
    nrPeaksAngiotensineII
    #human dynein heavy chain
    nrPeaksHumandynein <- calculateNrPeaks(aC = humandynein)
    # --- Brain Vignette.Rnw:119 154 [] ---
    # Key functions: calculateIsotopicProbabilities
    #angiotensineII
    #with default options
    prob1 <- calculateIsotopicProbabilities(aC = angiotensineII)
    print(length(prob1))
    #with user defined number of requested aggregated isotopic variants
    # --- Brain Vignette.Rnw:160 173 [] ---
    # Key functions: expression, useBRAIN
    #angiotensineII
    headr <- expression(paste(C[50], H[71], N[13],O[12]))
    #with default options
    res <- useBRAIN(aC= angiotensineII)
    # --- Brain Vignette.Rnw:177 192 [] ---
    # Key functions: expression, useBRAIN
    #human dynein heavy chain
    headr <- expression(paste(C[23832], H[37816], N[6528],O[7031], S[170]))
    res <- useBRAIN(aC=humandynein, stopOption="coverage", coverage=0.99)
    plot(res$masses,res$isoDistr,xlab="mass",ylab="abundances", type="h",
    xlim=c(min(res$masses)-1,max(res$masses)+1))
    # --- Brain Vignette.Rnw:201 216 [] ---
    # Key functions: useBRAIN
    #with user defined number of requested aggregated isotopic variants
    res <- useBRAIN(aC = angiotensineII, nrPeaks = 20)
    plot(res$masses,res$isoDistr,xlab="mass",ylab="abundances", type="h",
    xlim=c(min(res$masses)-1,max(res$masses)+1))
    title(headr)
    # --- Brain Vignette.Rnw:247 250 [] ---
    # Key functions: na
    ## AMINOS <- c("A", "R", "N", "D", "C", "E", "Q", "G", "H", "I", "L", "K",
    ## "M", "F", "P", "S", "T", "W", "Y", "V")
    ## !is.na(sum(match(seqVector, AMINOS)))
    # --- Brain Vignette.Rnw:258 284 [] ---
    # Key functions: frame, na
    ## nrPeaks = 1000
    ## howMany <- nrow(tabUniprot)
    ## dfUniprot <- data.frame()
    # --- Brain Vignette.Rnw:295 297 [] ---
    # Key functions: file
    uniprotBRAIN <- read.table(system.file("extdata", "uniprotBRAIN.txt", package="BRAIN"))
    nrow(uniprotBRAIN)
    # --- Brain Vignette.Rnw:310 317 [] ---
    # Key functions: bwplot, cut
    library(lattice)
    mm <- uniprot10to5$monoMass
    mmMin <- floor(min(mm)) - 1
    mmMax <- ceiling(max(mm)) + 1
    sq <- seq(from=0, to=mmMax, by=5000)
    # --- Brain Vignette.Rnw:320 323 [] ---
    # Key functions: bwplot, cut, monoMass
    bw2 <- bwplot(cut(monoMass, sq) ~ (mostAbundantPeakMass - monoMass),
    data=uniprot10to5,  ylab="monoMass (Da)", xlab="mostAbundantPeakMass - monoMass (Da)")
    plot(bw2)
    # --- Brain Vignette.Rnw:333 335 [] ---
    # Key functions: lm
    lmod <- lm(monoMass ~ mostAbundantPeakMass, data=uniprot10to5)
    summary(lmod)
    # --- Brain Vignette.Rnw:354 361 [] ---
    # Key functions: model
    icptLm <- lmod$coefficients[1]
    cffLm <- lmod$coefficients[2]
    expected <- icptLm + cffLm * uniprot10to5$mostAbundantPeakMass
    residuals <- uniprot10to5$monoMass - expected
    # --- Brain Vignette.Rnw:371 396 [] ---
    # Key functions: useBRAIN2, time, replicate


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_brain_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_brain_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_brain_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BRAIN:", paste0("    brain: ", packageVersion("BRAIN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_brain_results.csv
    touch ${prefix}_brain_output.rds
    echo "BIOC_BRAIN:" > versions.yml
    echo "    brain: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BRAIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BRAIN(ch_input)

    emit:
    results  = BIOC_BRAIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BRAIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BRAIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BRAIN.out.versions  // channel: path(versions.yml)
}
