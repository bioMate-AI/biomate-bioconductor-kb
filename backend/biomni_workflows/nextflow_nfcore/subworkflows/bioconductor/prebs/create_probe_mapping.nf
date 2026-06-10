#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: prebs — create_probe_mapping
// Generate a custom probe sequence mapping file for a microarray platform using its Bioconductor probe package and genomic alignment coordinates.
// Input: hgu133plus2probe, output_probe_mappings.map
// Container: quay.io/biocontainers/bioconductor-prebs:1.50.0--r45hdfd78af_0
// R packages: affy, hgu133plus2probe
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PREBS_CREATE_PROBE_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-prebs:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("affy", "hgu133plus2probe")
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
    
    # Check for required input files
    if (!file.exists("output_probe_mappings.map")) {
      stop("Error: Required input file 'output_probe_mappings.map' not found in the working directory.")
    }
    
    # 1. Load the platform's probe package and convert it to a data frame
    if (!requireNamespace("hgu133plus2probe", quietly = TRUE)) {
      stop("Error: The 'hgu133plus2probe' package is required but not installed.")
    }
    library("hgu133plus2probe")
    probes <- as.data.frame(hgu133plus2probe)
    head(probes)
    
    # 2. Filter out control probes (AFFX) and compute probe IDs using xy2indices
    if (!requireNamespace("affy", quietly = TRUE)) {
      stop("Error: The 'affy' package is required but not installed.")
    }
    library("affy")
    probes <- probes[substr(probes\$Probe.Set.Name, 1, 4) != "AFFX", ]
    probes\$Probe.ID <- xy2indices(probes\$x, probes\$y, cdf="hgu133plus2cdf")
    
    # 3. Export probe sequences to a text file for alignment
    write.table(probes, file="probes.txt", quote=FALSE, row.names=FALSE, col.names=TRUE)
    
    # 4. Read the genomic alignment map file and adjust 0-based coordinates to 1-based
    probe_mappings <- read.table("output_probe_mappings.map")
    colnames(probe_mappings) <- c("Probe.ID", "strand", 
                                  "chr", "start", "seq", "match", "multiple")
    probe_mappings\$start <- probe_mappings\$start + 1 
    
    # 5. Merge the alignment coordinates with the probe information and write the final mapping file
    probes <- read.table("probes.txt", head=TRUE)
    probes <- merge(probes, probe_mappings)
    
    output_table <- data.frame(Probe.Set.Name=probes\$Probe.Set.Name, 
        Chr=probes\$chr, Chr.Strand=probes\$strand, Chr.From=probes\$start, 
        Probe.X=probes\$x, Probe.Y=probes\$y, Affy.Probe.Set.Name=probes\$Probe.Set.Name)
    
    write.table(output_table, file="HGU133Plus2_mapping.txt", 
                quote=FALSE, sep="\t", row.names=FALSE)
    
    cat("Workflow complete. Output written to 'HGU133Plus2_mapping.txt'.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PREBS_CREATE_PROBE_MAPPING":
        prebs: \$(Rscript -e 'cat(as.character(packageVersion("prebs")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_probe_mapping.csv versions.yml
    """
}

workflow BIOC_PREBS_CREATE_PROBE_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hgu133plus2probe, output_probe_mappings.map ] ]

    main:
    BIOC_PREBS_CREATE_PROBE_MAPPING(ch_input)

    emit:
    tables   = BIOC_PREBS_CREATE_PROBE_MAPPING.out.tables
    plots    = BIOC_PREBS_CREATE_PROBE_MAPPING.out.plots
    objects  = BIOC_PREBS_CREATE_PROBE_MAPPING.out.objects
    versions = BIOC_PREBS_CREATE_PROBE_MAPPING.out.versions
}
