#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normqpcr — reference_gene_selection
// Select and rank the most stable reference/housekeeping genes from candidate genes using geNorm or NormFinder.
// Input: qPCR.techReps.txt, example.txt
// Container: quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMQPCR_REFERENCE_GENE_SELECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0"

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
    .bm_deps <- c("normqpcr", "rcolorbrewer", "readqpcr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ReadqPCR)
    library(NormqPCR)
    
    # 1. Read raw qPCR data with technical replicates
    qPCR.example.techReps <- "qPCR.techReps.txt"
    qPCRBatch.qPCR.techReps <- read.qPCR(qPCR.example.techReps)
    
    # 2. Combine technical replicates
    combinedTechReps <- combineTechReps(qPCRBatch.qPCR.techReps)
    
    # Write combined technical replicates to output
    write.csv(exprs(combinedTechReps), file = "combined_tech_reps.csv", row.names = TRUE)
    
    # 3. Handle undetermined values and NAs using TaqMan qPCR data
    taqman.example <- "example.txt"
    qPCRBatch.taqman <- read.taqman(taqman.example)
    
    # Replace values above cutoff
    qPCRBatch.taqman.replaced <- replaceAboveCutOff(qPCRBatch.taqman, newVal = NA, cutOff = 35)
    
    # Replace NAs with 40
    qPCRBatch.taqman.replaced <- replaceNAs(qPCRBatch.taqman, newNA = 40)
    
    # Construct contrast matrix
    a <- c(0,0,1,1,0,0,1,1) # one for each sample type, with 1 representing
    b <- c(1,1,0,0,1,1,0,0) # position of sample type in samplenames vector 
    contM <- cbind(a,b)
    colnames(contM) <- c("case","control") # set the names of each sample type
    rownames(contM) <- sampleNames(qPCRBatch.taqman) # set row names
    
    sMaxM <- t(as.matrix(c(3,3))) # now make the contrast matrix
    colnames(sMaxM) <- c("case","control") # make sure these line up with samples
    
    # Replace values based on contrast matrix and max NAs allowed
    qPCRBatch.taqman.replaced <- makeAllNewVal(qPCRBatch.taqman, contM, sMaxM, newVal=NA)
    
    # Write processed TaqMan expression matrix to output
    write.csv(exprs(qPCRBatch.taqman.replaced), file = "taqman_processed.csv", row.names = TRUE)
    
    # 4. Rank reference genes using geNorm and NormFinder
    # To ensure ranking algorithms run without NA errors, we replace remaining NAs with 40
    qPCRBatch.for_ranking <- replaceNAs(qPCRBatch.taqman.replaced, newNA = 40)
    
    # Define group/class structure based on the contrast matrix
    Class <- as.factor(ifelse(contM[, "case"] == 1, "case", "control"))
    
    # geNorm reference gene selection
    tryCatch({
      res.geNorm <- selectHKs(qPCRBatch.for_ranking, 
                              method = "geNorm", 
                              Symbols = featureNames(qPCRBatch.for_ranking), 
                              minNrHK = 2, 
                              log = FALSE)
      
      # Save geNorm ranking results
      geNorm_df <- data.frame(
        Rank = seq_along(res.geNorm\$ranking),
        Gene = res.geNorm\$ranking
      )
      write.csv(geNorm_df, file = "geNorm_ranking.csv", row.names = FALSE)
    }, error = function(e) {
      message("geNorm selection failed: ", e\$message)
    })
    
    # NormFinder stability measure (rho)
    tryCatch({
      res.NormFinder.rho <- stabMeasureRho(qPCRBatch.for_ranking, 
                                           group = Class, 
                                           log = FALSE)
      
      rho_df <- data.frame(
        Gene = names(res.NormFinder.rho),
        StabilityMeasure = res.NormFinder.rho
      )
      rho_df <- rho_df[order(rho_df\$StabilityMeasure), ]
      write.csv(rho_df, file = "NormFinder_stability_rho.csv", row.names = FALSE)
    }, error = function(e) {
      message("NormFinder stabMeasureRho failed: ", e\$message)
    })
    
    # NormFinder reference gene selection (step-wise)
    tryCatch({
      res.NormFinder.select <- selectHKs(qPCRBatch.for_ranking, 
                                         group = Class, 
                                         log = FALSE, 
                                         trace = TRUE, 
                                         Symbols = featureNames(qPCRBatch.for_ranking), 
                                         minNrHKs = 12, 
                                         method = "NormFinder")
      
      NormFinder_df <- data.frame(
        Rank = seq_along(res.NormFinder.select\$ranking),
        Gene = res.NormFinder.select\$ranking
      )
      write.csv(NormFinder_df, file = "NormFinder_ranking.csv", row.names = FALSE)
    }, error = function(e) {
      message("NormFinder selectHKs failed: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORMQPCR_REFERENCE_GENE_SELECTION":
        normqpcr: \$(Rscript -e 'cat(as.character(packageVersion("normqpcr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_gene_selection.csv versions.yml
    """
}

workflow BIOC_NORMQPCR_REFERENCE_GENE_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ qPCR.techReps.txt, example.txt ] ]

    main:
    BIOC_NORMQPCR_REFERENCE_GENE_SELECTION(ch_input)

    emit:
    tables   = BIOC_NORMQPCR_REFERENCE_GENE_SELECTION.out.tables
    plots    = BIOC_NORMQPCR_REFERENCE_GENE_SELECTION.out.plots
    objects  = BIOC_NORMQPCR_REFERENCE_GENE_SELECTION.out.objects
    versions = BIOC_NORMQPCR_REFERENCE_GENE_SELECTION.out.versions
}
