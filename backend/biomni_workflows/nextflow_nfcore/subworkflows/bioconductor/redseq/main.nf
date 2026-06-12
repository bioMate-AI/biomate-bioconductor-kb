#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: REDseq — single_end_redseq_analysis
// Build a restriction enzyme map, assign single-end sequence tags to RE sites, visualize distributions, and perform statistical testing for enriched/depleted or d
// Input: examplePattern.fa, example.REDseq, example.map
// Container: quay.io/biocontainers/bioconductor-redseq:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Celegans.UCSC.ce2, REDseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build genome-wide RE map using buildREmap
//  * 2. [Core Analysis] Assign mapped sequence tags to RE sites using assignSeq2REsite
//  * 3. [Visualization & Output] Visualize cut frequency distribution using plotCutDistribution and distance distribution using distanceHistSeq2RE
//  * 4. [Visualization & Output] Summarize assigned reads to generate a count table using summarizeByRE
//  * 5. [Core Analysis] Identify statistically significant cut sites for a single condition using binom.test.REDseq, or compare two conditions without rep

nextflow.enable.dsl = 2

process BIOC_REDSEQ_SINGLE_END_REDSEQ_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("REDseq", "BSgenome.Celegans.UCSC.ce2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(REDseq)
    library(BSgenome.Celegans.UCSC.ce2)
    
    # 1. Build genome-wide RE map using buildREmap
    REpatternFilePath <- "examplePattern.fa"
    myMap <- buildREmap(REpatternFilePath, BSgenomeName=Celegans, outfile="example.REmap")
    
    # Read user input files
    example.REDseq <- readRDS("example.REDseq")
    example.map <- readRDS("example.map")
    
    # 2. Assign mapped sequence tags to RE sites using assignSeq2REsite
    r.unique <- assignSeq2REsite(example.REDseq, example.map, cut.offset = 1, 
                                 seq.length = 36, allowed.offset = 5, min.FragmentLength = 60, 
                                 max.FragmentLength = 300, partitionMultipleRE = "unique")
    
    r.best <- assignSeq2REsite(example.REDseq, example.map, 
                               cut.offset = 1, seq.length = 36, allowed.offset = 5, 
                               min.FragmentLength = 60, max.FragmentLength = 300, partitionMultipleRE = "best")
    
    r.random <- assignSeq2REsite(example.REDseq, example.map, cut.offset = 1, 
                                 seq.length = 36, allowed.offset = 5, min.FragmentLength = 60, 
                                 max.FragmentLength = 300, partitionMultipleRE = "random")
    
    r.average <- assignSeq2REsite(example.REDseq, example.map, cut.offset = 1, 
                                  seq.length = 36, allowed.offset = 5, min.FragmentLength = 60,
                                  max.FragmentLength = 300, partitionMultipleRE = "average")
    
    r.estimate <- assignSeq2REsite(example.REDseq, example.map, cut.offset = 1, 
                                   seq.length = 36, allowed.offset = 5, min.FragmentLength = 60, 
                                   max.FragmentLength = 300, partitionMultipleRE = "estimate")
    
    # Save assigned sequence objects
    saveRDS(r.unique, "r.unique.rds")
    saveRDS(r.best, "r.best.rds")
    saveRDS(r.random, "r.random.rds")
    saveRDS(r.average, "r.average.rds")
    saveRDS(r.estimate, "r.estimate.rds")
    
    # Use the assigned sequences from the estimate partition strategy for downstream analysis
    example.assignedREDseq <- r.estimate\$passed.filter
    
    # 3. Visualize cut frequency distribution and distance distribution
    pdf("cut_distribution.pdf")
    plotCutDistribution(example.assignedREDseq, example.map, chr="2", xlim = c(3012000, 3020000))
    dev.off()
    
    pdf("distance_hist.pdf")
    distanceHistSeq2RE(example.assignedREDseq, ylim=c(0,25))
    dev.off()
    
    # 4. Summarize assigned reads to generate a count table using summarizeByRE
    REsummary <- summarizeByRE(example.assignedREDseq, by="Weight")
    write.csv(REsummary, "REsummary.csv", row.names=FALSE)
    
    # 5. Identify statistically significant cut sites for a single condition using binom.test.REDseq
    binom_res <- binom.test.REDseq(REsummary)
    write.csv(binom_res, "binom_results.csv", row.names=FALSE)
    
    # Compare two conditions without replicates using compareREDseq
    x <- cbind(c("RE1", "RE2", "RE3", "RE4"), c(10,1,100, 0), c(5,5,50, 40))
    colnames(x) <- c("REid", "control", "treated")
    compare_res <- compareREDseq(x)
    write.csv(compare_res, "compare_results.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_REDSEQ_SINGLE_END_REDSEQ_ANALYSIS":',
        paste0('    REDseq: ', as.character(packageVersion('REDseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_end_redseq_analysis.csv versions.yml
    """
}

workflow BIOC_REDSEQ_SINGLE_END_REDSEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ examplePattern.fa, example.REDseq, example.map ] ]

    main:
    BIOC_REDSEQ_SINGLE_END_REDSEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_REDSEQ_SINGLE_END_REDSEQ_ANALYSIS.out.tables
    plots    = BIOC_REDSEQ_SINGLE_END_REDSEQ_ANALYSIS.out.plots
    objects  = BIOC_REDSEQ_SINGLE_END_REDSEQ_ANALYSIS.out.objects
    versions = BIOC_REDSEQ_SINGLE_END_REDSEQ_ANALYSIS.out.versions
}
