#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HIBAG — hla_association_testing
// Perform association tests between imputed HLA alleles (or translated amino acid sequences) and clinical phenotypes.
// Input: case_control.txt, Imputed HLA genotypes
// Container: quay.io/biocontainers/bioconductor-hibag:1.46.0--r45ha27e39d_0
// R packages: HIBAG
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIBAG_HLA_ASSOCIATION_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hibag:1.46.0--r45ha27e39d_0"

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
    .bm_deps <- c("HIBAG")
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
    
    # Load required library
    library(HIBAG)
    
    # 1. Load phenotype and covariate data
    fn <- "case_control.txt"
    dat <- read.table (fn, header= TRUE , stringsAsFactors= FALSE )
    head (dat)
    
    # 2. Format HLA alleles into a HIBAG allele object
    hla <- hlaAllele (dat \$ sample.id, H1= dat \$ A, H2= dat \$ A .1 , locus= "A" , assembly= "hg19" , prob= dat \$ prob)
    summary (hla)
    saveRDS(hla, "hla_allele_object.rds")
    
    # 3. Run association tests using dominant, additive, or recessive models
    res_default <- hlaAssocTest (hla, disease ~ h, data= dat)
    write.csv(res_default, "hla_assoc_disease_default.csv", row.names=TRUE)
    
    res_verbose_false <- hlaAssocTest (hla, disease ~ h, data= dat, verbose= FALSE )
    print ( res_verbose_false )
    write.csv(res_verbose_false, "hla_assoc_disease_verbose_false.csv", row.names=TRUE)
    
    res_prob_05 <- hlaAssocTest (hla, disease ~ h, data= dat, prob.threshold= 0.5 )
    write.csv(res_prob_05, "hla_assoc_disease_prob_0.5.csv", row.names=TRUE)
    
    res_showOR <- hlaAssocTest (hla, disease ~ h, data= dat, showOR= TRUE )
    write.csv(res_showOR, "hla_assoc_disease_showOR.csv", row.names=TRUE)
    
    res_additive <- hlaAssocTest (hla, disease ~ h, data= dat, model= "additive" )
    write.csv(res_additive, "hla_assoc_disease_additive.csv", row.names=TRUE)
    
    res_trait <- hlaAssocTest (hla, trait ~ h, data= dat)
    write.csv(res_trait, "hla_assoc_trait_default.csv", row.names=TRUE)
    
    # 4. Convert HLA alleles to amino acid sequences
    aa <- hlaConvSequence (hla, code= "P.code.merge" )
    head ( c (aa \$ value \$ allele1, aa \$ value \$ allele2))
    summary (aa)
    saveRDS(aa, "aa_sequence_object.rds")
    
    # 5. Run amino acid-level association tests
    res_aa_dominant <- hlaAssocTest (aa, disease ~ h, data= dat, model= "dominant" )
    write.csv(res_aa_dominant, "aa_assoc_disease_dominant.csv", row.names=TRUE)
    
    res_aa_dominant_prob05 <- hlaAssocTest (aa, disease ~ h, data= dat, model= "dominant" , prob.threshold= 0.5 )
    write.csv(res_aa_dominant_prob05, "aa_assoc_disease_dominant_prob0.5.csv", row.names=TRUE)
    
    res_aa_recessive <- hlaAssocTest (aa, disease ~ h, data= dat, model= "recessive" )
    write.csv(res_aa_recessive, "aa_assoc_disease_recessive.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_HIBAG_HLA_ASSOCIATION_TESTING":',
        paste0('        HIBAG: ', as.character(packageVersion("HIBAG")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hla_association_testing.csv versions.yml
    """
}

workflow BIOC_HIBAG_HLA_ASSOCIATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ case_control.txt, Imputed HLA genotypes ] ]

    main:
    BIOC_HIBAG_HLA_ASSOCIATION_TESTING(ch_input)

    emit:
    tables   = BIOC_HIBAG_HLA_ASSOCIATION_TESTING.out.tables
    plots    = BIOC_HIBAG_HLA_ASSOCIATION_TESTING.out.plots
    objects  = BIOC_HIBAG_HLA_ASSOCIATION_TESTING.out.objects
    versions = BIOC_HIBAG_HLA_ASSOCIATION_TESTING.out.versions
}
