#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gbscleanr — gbs_genotype_error_correction
// Convert raw VCF genotype data to GDS, perform quality control and filtering, define the breeding scheme, estimate true genotypes using HMM, and export the corre
// Input: sample.vcf
// Container: quay.io/biocontainers/bioconductor-gbscleanr:2.4.4--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GBSCLEANR_GBS_GENOTYPE_ERROR_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gbscleanr:2.4.4--r45ha27e39d_0"

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
    .bm_deps <- c("gbscleanr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library("GBScleanR")
    
    # Define input file path (must exist in the working directory)
    vcf_fn <- "sample.vcf"
    
    if (!file.exists(vcf_fn)) {
      stop("Required input file 'sample.vcf' not found in the working directory.")
    }
    
    # Define output GDS file path
    gds_fn <- "sample.gds"
    
    # Convert VCF to GDS
    gbsrVCF2GDS(vcf_fn = vcf_fn, out_fn = gds_fn, force = TRUE, verbose = FALSE)
    
    # Load GDS
    gds <- loadGDS(gds_fn, verbose = FALSE)
    
    # Summarize raw data
    nsam(gds)
    nmar(gds) 
    head(getChromosome(gds)) 
    head(getPosition(gds)) 
    head(getAllele(gds)) 
    head(getMarID(gds)) 
    head(getSamID(gds)) 
    
    geno <- getGenotype(gds)
    geno <- getRead(gds)
    
    gds <- countGenotype(gds)
    gds <- countRead(gds)
    
    # Open PDF device to save all visualizations
    pdf("gbscleanr_plots.pdf", width = 10, height = 8)
    
    # Plot histograms of raw data statistics
    print(histGBSR(gds, stats = "missing")) 
    print(histGBSR(gds, stats = "het")) 
    print(histGBSR(gds, stats = "raf")) 
    print(histGBSR(gds, stats = "dp")) 
    print(histGBSR(gds, stats = "ad_ref")) 
    print(histGBSR(gds, stats = "ad_alt")) 
    print(histGBSR(gds, stats = "rrf")) 
    print(histGBSR(gds, stats = "mean_ref")) 
    print(histGBSR(gds, stats = "sd_ref")) 
    print(histGBSR(gds, stats = "sd_ref")) 
    
    # Plot marker statistics along chromosomes and relationships
    print(plotGBSR(gds, stats = "missing"))
    print(plotGBSR(gds, stats = "geno"))
    print(pairsGBSR(gds, stats1 = "missing", stats2 = "dp"))
    
    # Apply quality control and filtering
    gds <- setCallFilter(gds, dp_count = c(5, Inf))
    gds <- setCallFilter(gds, dp_qtile = c(0, 0.9))
    gds <- setCallFilter(gds, ref_qtile = c(0, 0.9), alt_qtile = c(0, 0.9))
    gds <- setMarFilter(gds, missing = 0.2)
    gds <- thinMarker(gds, range = 150) 
    
    # Recalculate statistics on filtered node
    gds <- countGenotype(gds, node = "filt")
    gds <- countRead(gds, node = "filt")
    
    # Define replicates and parents
    sample_id <- getSamID(gds, valid = FALSE)
    gds <- setReplicates(gds, replicates = rep(1:51, each = 2))
    
    p1 <- grep("Founder1", getSamID(gds, valid = FALSE), value = TRUE)
    p2 <- grep("Founder2", getSamID(gds, valid = FALSE), value = TRUE)
    gds <- setParents(gds, parents = c(p1, p2), mono = TRUE, bi = TRUE)
    
    # Define breeding scheme
    gds <- makeScheme(gds, generation = 2, crosstype = "self")
    
    # Estimate true genotypes using HMM
    gds <- estGeno(gds, node = "filt", iter = 4)
    
    # Retrieve estimated genotypes, parent genotypes, and haplotypes
    est_geno <- getGenotype(gds, node = "cor")
    parent_geno <- getGenotype(gds, node = "parents")
    est_hap <- getHaplotype(gds)
    
    # Save retrieved objects to RDS files
    saveRDS(est_geno, "estimated_genotypes.rds")
    saveRDS(parent_geno, "parent_genotypes.rds")
    saveRDS(est_hap, "estimated_haplotypes.rds")
    
    # Export corrected genotypes to VCF
    out_fn <- "sample_est.vcf.gz"
    gbsrGDS2VCF(gds, out_fn)
    gbsrGDS2VCF(gds, out_fn, node = "cor")
    
    # Export corrected genotypes to CSV
    out_fn <- "sample_est.csv"
    gbsrGDS2CSV(gds, out_fn)
    gbsrGDS2CSV(gds, out_fn, node = "cor")
    
    # Reopen GDS connection for plotting
    gds <- reopenGDS(gds)
    
    # Plot read ratios and dosages
    print(plotReadRatio(x = gds, coord = c(3, 4), ind = 3, node = "raw", size = 2))
    print(plotReadRatio(x = gds, coord = c(3, 4), ind = 3, node = "filt", size = 2))
    print(plotDosage(x = gds, coord = c(3, 4), ind = 3, node = "raw", size = 2))
    print(plotDosage(x = gds, coord = c(3, 4), ind = 3, node = "filt", size = 2))
    
    # Close PDF device
    dev.off()
    
    # Safely close GDS connection
    closeGDS(gds)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GBSCLEANR_GBS_GENOTYPE_ERROR_CORRECTION":
        gbscleanr: \$(Rscript -e 'cat(as.character(packageVersion("gbscleanr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gbs_genotype_error_correction.csv versions.yml
    """
}

workflow BIOC_GBSCLEANR_GBS_GENOTYPE_ERROR_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.vcf ] ]

    main:
    BIOC_GBSCLEANR_GBS_GENOTYPE_ERROR_CORRECTION(ch_input)

    emit:
    tables   = BIOC_GBSCLEANR_GBS_GENOTYPE_ERROR_CORRECTION.out.tables
    plots    = BIOC_GBSCLEANR_GBS_GENOTYPE_ERROR_CORRECTION.out.plots
    objects  = BIOC_GBSCLEANR_GBS_GENOTYPE_ERROR_CORRECTION.out.objects
    versions = BIOC_GBSCLEANR_GBS_GENOTYPE_ERROR_CORRECTION.out.versions
}
