#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneticsPed — quantitative_genetics_animal_model
// Set up and solve mixed model equations for an animal model using pedigree data and phenotypes.
// Input: pedigree_data.csv
// Container: quay.io/biocontainers/bioconductor-geneticsped:1.72.0--r45h9e4a190_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GeneticsPed
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a Pedigree object
//  * 2. [Core Analysis] Generate the design matrix for random animal effects
//  * 3. [Core Analysis] Extend the pedigree to include all ancestors
//  * 4. [Core Analysis] Compute the inverse of the additive genetic relationship matrix
//  * 5. [Input & Preparation] Set up the coefficient matrix (LHS) and right-hand side (RHS) equations
//  * 6. [Core Analysis] Solve the mixed model equations for breeding values and fixed effects

nextflow.enable.dsl = 2

process BIOC_GENETICSPED_QUANTITATIVE_GENETICS_ANIMAL_MODEL {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(GeneticsPed)
    
    # 1. Read the user input file
    # The pipeline expects 'pedigree_data.csv' in the working directory
    ped_df <- read.csv("pedigree_data.csv", stringsAsFactors = FALSE)
    
    # Map user-defined column names to match the documented code's expected names
    if ("individual" %in% colnames(ped_df)) {
      colnames(ped_df)[colnames(ped_df) == "individual"] <- "calf"
    }
    if ("phenotype" %in% colnames(ped_df)) {
      colnames(ped_df)[colnames(ped_df) == "phenotype"] <- "pwg"
    }
    
    # 2. Create a Pedigree object
    x <- Pedigree(x=ped_df, subject="calf", ascendant=c("sire", "dam"),
                  ascendantSex=c("Male", "Female"), sex="sex")
    
    # Extract phenotype vector
    y <- x\$pwg
    
    # 3. Generate design matrices
    X <- model.matrix(~ x\$sex - 1)
    Z <- model.matrix(object=x, y=x\$pwg, id=x\$calf)
    
    # 4. Set up the initial coefficient matrix (LHS)
    LHS <- rbind(cbind(crossprod(X),    crossprod(X, Z)),
                 cbind(crossprod(Z, X), crossprod(Z)))
    
    # 5. Extend the pedigree to include all ancestors
    x <- extend(x)
    
    # 6. Compute the inverse of the additive genetic relationship matrix
    Ainv <- inverseAdditive(x=x)
    
    # Define variance components and alpha ratio
    sigma2a <- 20
    sigma2e <- 40
    alpha <- sigma2e / sigma2a
    
    # Number of individuals in the extended pedigree
    q <- nIndividual(x)
    p <- nrow(LHS) - q
    
    # Add the relationship matrix contribution to the LHS
    LHS[(p + 1):(p + q), (p + 1):(p + q)] <-
      LHS[(p + 1):(p + q), (p + 1):(p + q)] + Ainv * alpha
    
    # 7. Set up the right-hand side (RHS) equations
    RHS <- rbind(crossprod(X, y),
                 crossprod(Z, y))
    
    # 8. Solve the mixed model equations
    sol <- solve(LHS, RHS)
    
    # 9. Save results to output files
    write.csv(as.data.frame(as.matrix(sol)), "solutions.csv", row.names = TRUE)
    write.csv(as.data.frame(as.matrix(LHS)), "LHS_matrix.csv", row.names = TRUE)
    write.csv(as.data.frame(as.matrix(RHS)), "RHS_vector.csv", row.names = TRUE)
    write.csv(as.data.frame(as.matrix(Ainv)), "Ainv_matrix.csv", row.names = TRUE)
    saveRDS(x, "extended_pedigree.rds")

    writeLines(c(
        '"BIOC_GENETICSPED_QUANTITATIVE_GENETICS_ANIMAL_MODEL":',
        paste0('    GeneticsPed: ', as.character(packageVersion('GeneticsPed')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantitative_genetics_animal_model.csv versions.yml
    """
}

workflow BIOC_GENETICSPED_QUANTITATIVE_GENETICS_ANIMAL_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pedigree_data.csv ] ]

    main:
    BIOC_GENETICSPED_QUANTITATIVE_GENETICS_ANIMAL_MODEL(ch_input)

    emit:
    tables   = BIOC_GENETICSPED_QUANTITATIVE_GENETICS_ANIMAL_MODEL.out.tables
    plots    = BIOC_GENETICSPED_QUANTITATIVE_GENETICS_ANIMAL_MODEL.out.plots
    objects  = BIOC_GENETICSPED_QUANTITATIVE_GENETICS_ANIMAL_MODEL.out.objects
    versions = BIOC_GENETICSPED_QUANTITATIVE_GENETICS_ANIMAL_MODEL.out.versions
}
