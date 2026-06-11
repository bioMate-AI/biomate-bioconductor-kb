#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LiquidAssociation — genome_wide_triplet_screening
// Screen a large set of genes to identify triplets with high liquid association and test the top candidates.
// Input: lae
// Container: quay.io/biocontainers/bioconductor-liquidassociation:1.64.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: LiquidAssociation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter genes with small variances
//  * 2. [Core Analysis] Generate all triplet combinations and calculate GLA
//  * 3. [Core Analysis] Identify triplets with large GLA estimates
//  * 4. [Core Analysis] Standardize and normalize the top triplet data using qqnorm2 and stand
//  * 5. [Core Analysis] Fit CNM and perform hypothesis testing on the selected triplet

nextflow.enable.dsl = 2

process BIOC_LIQUIDASSOCIATION_GENOME_WIDE_TRIPLET_SCREENING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    
    # Load required libraries
    library(LiquidAssociation)
    
    # 1. Read User Input
    # The pipeline expects 'lae' (matrix of expression values with samples as rows and genes as columns)
    # We support reading from lae.csv, lae.rds, or lae.tsv in the working directory.
    if (file.exists("lae.csv")) {
      lae <- as.matrix(read.csv("lae.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("lae.rds")) {
      lae <- readRDS("lae.rds")
      if (!is.matrix(lae)) lae <- as.matrix(lae)
    } else if (file.exists("lae.tsv")) {
      lae <- as.matrix(read.delim("lae.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Required input file 'lae' (lae.csv, lae.rds, or lae.tsv) not found in the working directory.")
    }
    
    # Stage 1: Filter genes with small variances
    V<-apply(lae, 2, var, na.rm=TRUE)
    ibig<-V > 0.5
    big<-which(ibig)
    bigtriplet<-lae[,big]
    
    # Stage 2: Generate all triplet combinations and calculate GLA
    num<-choose(ncol(bigtriplet),3)
    pick<-t(combn(1:ncol(bigtriplet),3))
    
    # Limit to 100 triplets or the maximum available if fewer than 100
    n_triplets <- min(100, nrow(pick))
    GLAout<-matrix(0, nrow=n_triplets, 3)
    for ( i in 1:n_triplets){
    	dat1<-bigtriplet[,pick[i,]]
    	for ( dim in 1:3 ){
    		GLAout[i,dim]<-GLA(dat1, cut=4, dim=dim)
    	}
    }
    
    # Stage 3: Identify triplets with large GLA estimates
    GLAmax<-apply(abs(GLAout),1, max)
    imax<-which(GLAmax > 0.20)
    
    # Robustness check: if no triplets exceed 0.20, select the one with the maximum GLA
    if (length(imax) == 0) {
      message("No triplets found with GLA > 0.20. Selecting the triplet with the highest GLA.")
      imax <- which.max(GLAmax)
    }
    
    pickmax<-pick[imax, , drop=FALSE]
    GLAmax<-GLAout[imax, , drop=FALSE]
    trip.order<-t(apply(t(abs(GLAmax)), 2, order, decreasing=TRUE))
    
    # Stage 4: Standardize and normalize the top triplet data using qqnorm2 and stand
    whtrip<-1
    data<-bigtriplet[,pickmax[whtrip,]]
    data<-data[,trip.order[whtrip,]]
    data<-data[!is.na(data[,1]) & !is.na(data[,2]) & !is.na(data[,3]),]
    data<-apply(data,2,qqnorm2)
    data<-apply(data,2, stand)
    
    # Stage 5: Fit CNM and perform hypothesis testing on the selected triplet
    FitCNM1<-CNM.full(data)
    sGLA1<-getsGLA(data, boots=20, perm=50, cut=4, dim=3)
    
    # Write Outputs
    # 1. Save the GLA screening results for the evaluated triplets
    gene_names <- colnames(bigtriplet)
    screening_results <- data.frame(
      Gene1 = if (!is.null(gene_names)) gene_names[pick[1:n_triplets, 1]] else pick[1:n_triplets, 1],
      Gene2 = if (!is.null(gene_names)) gene_names[pick[1:n_triplets, 2]] else pick[1:n_triplets, 2],
      Gene3 = if (!is.null(gene_names)) gene_names[pick[1:n_triplets, 3]] else pick[1:n_triplets, 3],
      GLA_dim1 = GLAout[, 1],
      GLA_dim2 = GLAout[, 2],
      GLA_dim3 = GLAout[, 3],
      Max_Abs_GLA = apply(abs(GLAout), 1, max)
    )
    write.csv(screening_results, "gla_screening_results.csv", row.names = FALSE)
    
    # 2. Save the standardized data of the selected top triplet
    write.csv(data, "selected_triplet_standardized_data.csv", row.names = TRUE)
    
    # 3. Save the CNM model fit results
    saveRDS(FitCNM1, "fit_cnm_model.rds")
    sink("fit_cnm_summary.txt")
    print(FitCNM1)
    sink()
    
    # 4. Save the sGLA hypothesis testing results
    saveRDS(sGLA1, "sgla_testing_results.rds")
    write.csv(as.data.frame(t(sGLA1)), "sgla_testing_results.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_LIQUIDASSOCIATION_GENOME_WIDE_TRIPLET_SCREENING":',
        paste0('    LiquidAssociation: ', as.character(packageVersion('LiquidAssociation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genome_wide_triplet_screening.csv versions.yml
    """
}

workflow BIOC_LIQUIDASSOCIATION_GENOME_WIDE_TRIPLET_SCREENING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lae ] ]

    main:
    BIOC_LIQUIDASSOCIATION_GENOME_WIDE_TRIPLET_SCREENING(ch_input)

    emit:
    tables   = BIOC_LIQUIDASSOCIATION_GENOME_WIDE_TRIPLET_SCREENING.out.tables
    plots    = BIOC_LIQUIDASSOCIATION_GENOME_WIDE_TRIPLET_SCREENING.out.plots
    objects  = BIOC_LIQUIDASSOCIATION_GENOME_WIDE_TRIPLET_SCREENING.out.objects
    versions = BIOC_LIQUIDASSOCIATION_GENOME_WIDE_TRIPLET_SCREENING.out.versions
}
