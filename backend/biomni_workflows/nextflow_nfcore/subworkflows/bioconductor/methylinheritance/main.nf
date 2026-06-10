#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylinheritance — multigenerational_methylation_inheritance
// Identify significantly conserved differentially methylated elements across multiple generations using observation and permutation analyses.
// Input: F1_control_01.txt, F1_case_01.txt, F2_control_01.txt, F2_case_01.txt
// Container: quay.io/biocontainers/bioconductor-methylinheritance:1.34.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLINHERITANCE_MULTIGENERATIONAL_METHYLATION_INHERITANCE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-methylinheritance:1.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("knitr", "methylinheritance", "methylkit")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(methylInheritance)
    library(methylKit)
    
    # Ensure output directories exist
    dir.create("demo_01", showWarnings = FALSE)
    dir.create("demo_02", showWarnings = FALSE)
    
    ## 1. Format raw methylation files into a list of methylRawList objects using methylKit
    ## The methylRawList for F1
    generation_01 <- methRead(location = list("F1_control_01.txt", "F1_case_01.txt"), 
                        sample.id = list("F1_control_01", "F1_case_01"), 
                        assembly = "hg19", treatment = c(0, 1), context = "CpG")
    
    ## The methylRawList for F2
    generation_02 <- methRead(location = list("F2_control_01.txt", "F2_case_01.txt"), 
                        sample.id = list("F2_control_01", "F2_case_01"), 
                        assembly = "hg19", treatment = c(0, 1), context = "CpG")
    
    ## A list of methylRawList ready for methylInheritance
    final_list <- list(generation_01, generation_02)
    
    ## 2. Run observation analysis to calculate conserved elements between generations
    ## The observation analysis is only done on differentially methylated sites
    runObservation(methylKitData = final_list, 
                            type = "sites",     # Only sites
                            outputDir = "demo_01",   # RDS result files are saved 
                                                     # in the directory
                            nbrCores = 1,       # Number of cores used 
                            minReads = 10,      # Minimum read coverage
                            minMethDiff = 10,   # Minimum difference in methylation 
                                                # to be considered DMS
                            qvalue = 0.01,
                            vSeed = 2101)       # Ensure reproducible results
    
    ## 4a. Load observation results from RDS files
    ## The results can be retrived using loadAllRDSResults() method
    observedResults <- loadAllRDSResults(
                        analysisResultsDir = "demo_01/",  # Directory containing
                                                          # the observation
                                                          # results
                        permutationResultsDir = NULL, 
                        doingSites = TRUE, 
                        doingTiles = FALSE)
    
    ## 3. Run permutation analysis to generate a null distribution
    ## The permutation analysis is only done on differentially methylated sites
    runPermutation(methylKitData = final_list, # multi-generational dataset
                            type = "sites",     # Only sites
                            outputDir = "demo_02",   # RDS permutation files are 
                                                     # saved in the directory
                            runObservationAnalysis = FALSE,
                            nbrCores = 1,           # Number of cores used
                            nbrPermutations = 2,    # Should be much higher for a
                                                    # real analysis
                            minReads = 10,          # Minimum read coverage
                            minMethDiff = 10,   # Minimum difference in methylation
                                                # to be considered DMS
                            qvalue = 0.01,
                            vSeed = 2101)         # Ensure reproducible results
    
    ## 4b. Load permutation results from RDS files
    ## The results can be retrived using loadAllRDSResults() method
    permutationResults <- loadAllRDSResults(
                        analysisResultsDir = NULL, 
                        permutationResultsDir = "demo_02",   # Directory containing
                                                        # the permutation
                                                        # results
                        doingSites = TRUE, 
                        doingTiles = FALSE)
    
    ## 5. Merge observation and permutation results
    ## Merge observation and permutation results
    allResults <- mergePermutationAndObservation(permutationResults = 
                                                        permutationResults,
                                        observationResults = observedResults)
    
    ## 6. Extract specific generation-level comparison results
    ## Conserved differentially methylated sites between F1 and F2 generations
    F1_and_F2_results <- extractInfo(allResults = allResults, type = "sites", 
                                        inter = "i2", position = 1)
    
    F1_and_F2 <- F1_and_F2_results
    
    ## 7. Plot results and calculate significance levels
    ## Show graph and significant level for differentially conserved sites 
    ## between F1 and F2 
    pdf("conserved_methylation_plot.pdf")
    output <- plotGraph(F1_and_F2)
    dev.off()
    
    # Save meaningful outputs to files
    write.csv(F1_and_F2_results, "F1_and_F2_conserved_sites.csv", row.names = FALSE)
    saveRDS(allResults, "all_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_METHYLINHERITANCE_MULTIGENERATIONAL_METHYLATION_INHERITANCE":
        methylinheritance: \$(Rscript -e 'cat(as.character(packageVersion("methylinheritance")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multigenerational_methylation_inheritance.csv versions.yml
    """
}

workflow BIOC_METHYLINHERITANCE_MULTIGENERATIONAL_METHYLATION_INHERITANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ F1_control_01.txt, F1_case_01.txt, F2_control_01.txt, F2_case_01.txt ] ]

    main:
    BIOC_METHYLINHERITANCE_MULTIGENERATIONAL_METHYLATION_INHERITANCE(ch_input)

    emit:
    tables   = BIOC_METHYLINHERITANCE_MULTIGENERATIONAL_METHYLATION_INHERITANCE.out.tables
    plots    = BIOC_METHYLINHERITANCE_MULTIGENERATIONAL_METHYLATION_INHERITANCE.out.plots
    objects  = BIOC_METHYLINHERITANCE_MULTIGENERATIONAL_METHYLATION_INHERITANCE.out.objects
    versions = BIOC_METHYLINHERITANCE_MULTIGENERATIONAL_METHYLATION_INHERITANCE.out.versions
}
