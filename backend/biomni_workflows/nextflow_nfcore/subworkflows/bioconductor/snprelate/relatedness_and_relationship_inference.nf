#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snprelate — relatedness_and_relationship_inference
// Estimate identity-by-descent (IBD) coefficients and kinship using PLINK Method of Moments, Maximum Likelihood Estimation, or KING robust method.
// Input: genofile
// Container: quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0
// R packages: SNPRelate, gdsfmt
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPRELATE_RELATEDNESS_AND_RELATIONSHIP_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("SNPRelate", "gdsfmt")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(gdsfmt)
    library(SNPRelate)
    
    # --- Open the GDS file from the working directory ---
    genofile <- snpgdsOpen("genofile.gds")
    
    # Get sample IDs
    sample.id <- read.gdsn(index.gdsn(genofile, "sample.id"))
    
    # Get population information (with robust fallback if annotation is missing)
    pop_code <- tryCatch({
        read.gdsn(index.gdsn(genofile, path="sample.annot/pop.group"))
    }, error = function(e) {
        warning("Population annotation not found. Defaulting all samples to 'YRI'.")
        rep("YRI", length(sample.id))
    })
    
    # YRI samples selection
    YRI.id <- sample.id[pop_code == "YRI"]
    if (length(YRI.id) == 0) {
        warning("No 'YRI' samples found. Using all available samples.")
        YRI.id <- sample.id
    }
    
    # Perform LD pruning to obtain snpset.id (required for downstream IBD)
    snpset <- snpgdsLDpruning(genofile, ld.threshold=0.2, verbose=FALSE)
    snpset.id <- unlist(unname(snpset))
    
    # --- Estimate IBD coefficients using MoM ---
    ibd <- snpgdsIBDMoM(genofile, sample.id=YRI.id, snp.id=snpset.id,
        maf=0.05, missing.rate=0.05, num.thread=2)
    
    # Make a data.frame and save results
    ibd.coeff_mom <- snpgdsIBDSelection(ibd)
    write.csv(ibd.coeff_mom, "ibd_coeff_mom.csv", row.names=FALSE)
    
    # --- Estimate IBD coefficients using MLE ---
    set.seed(100)
    snp.id <- sample(snpset.id, min(1500, length(snpset.id)))  # random 1500 SNPs (or maximum available)
    ibd <- snpgdsIBDMLE(genofile, sample.id=YRI.id, snp.id=snp.id,
        maf=0.05, missing.rate=0.05, num.thread=2)
    
    # Make a data.frame and save results
    ibd.coeff_mle <- snpgdsIBDSelection(ibd)
    write.csv(ibd.coeff_mle, "ibd_coeff_mle.csv", row.names=FALSE)
    
    # --- Incorporate with pedigree information and run KING robust ---
    family.id <- tryCatch({
        fam <- read.gdsn(index.gdsn(genofile, "sample.annot/family.id"))
        fam[match(YRI.id, sample.id)]
    }, error = function(e) {
        warning("Family annotation not found. Assigning dummy family IDs.")
        rep("1", length(YRI.id))
    })
    
    ibd.robust <- snpgdsIBDKING(genofile, sample.id=YRI.id,
        family.id=family.id, num.thread=2)
    
    # --- Pairs of individuals (Select and format IBD/kinship ---
    dat <- snpgdsIBDSelection(ibd.robust)
    write.csv(dat, "ibd_king_robust.csv", row.names=FALSE)
    
    # Generate diagnostic plots
    pdf("relatedness_and_relationship_plots.pdf", width=10, height=5)
    par(mfrow=c(1, 2))
    
    # Plot MoM results
    if (exists("ibd.coeff_mom") && nrow(ibd.coeff_mom) > 0) {
        plot(ibd.coeff_mom\$k0, ibd.coeff_mom\$k1, xlim=c(0,1), ylim=c(0,1),
             xlab="k0", ylab="k1", main="YRI samples (MoM)", col="blue", pch=20)
        lines(c(0,1), c(1,0), col="red", lty=2)
    }
    
    # Plot KING robust results
    if (exists("dat") && nrow(dat) > 0) {
        plot(dat\$IBS0, dat\$kinship, xlab="Proportion of Zero IBS",
             ylab="Estimated Kinship Coefficient (KING-robust)",
             main="KING-robust Kinship vs IBS0", col="darkgreen", pch=20)
    }
    dev.off()
    
    # --- Close the GDS file ---
    snpgdsClose(genofile)

    writeLines(c(
        '"BIOC_SNPRELATE_RELATEDNESS_AND_RELATIONSHIP_INFERENCE":',
        paste0('        snprelate: ', as.character(packageVersion("snprelate")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_relatedness_and_relationship_inference.csv versions.yml
    """
}

workflow BIOC_SNPRELATE_RELATEDNESS_AND_RELATIONSHIP_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genofile ] ]

    main:
    BIOC_SNPRELATE_RELATEDNESS_AND_RELATIONSHIP_INFERENCE(ch_input)

    emit:
    tables   = BIOC_SNPRELATE_RELATEDNESS_AND_RELATIONSHIP_INFERENCE.out.tables
    plots    = BIOC_SNPRELATE_RELATEDNESS_AND_RELATIONSHIP_INFERENCE.out.plots
    objects  = BIOC_SNPRELATE_RELATEDNESS_AND_RELATIONSHIP_INFERENCE.out.objects
    versions = BIOC_SNPRELATE_RELATEDNESS_AND_RELATIONSHIP_INFERENCE.out.versions
}
