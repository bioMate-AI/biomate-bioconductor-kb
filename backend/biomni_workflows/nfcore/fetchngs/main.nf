// nf-core/fetchngs — user-facing parameter stub
// Download sequencing data from SRA/ENA/DDBJ/GEO/SynBio
//
// Pipeline phases:
// * 1. Input validation — accession ID format check (SRR/ERR/DRR/GSM)
// * 2. Metadata fetch — SRA/ENA metadata retrieval, sample annotation
// * 3. FASTQ download — sratools prefetch + fasterq-dump / FTP / Aspera
// * 4. Samplesheet generation — nf-core-compatible samplesheet CSV creation
// * 5. Report — MultiQC, download summary, samplesheet output

params.input             = null          // File of SRA/ENA/DDBJ/GEO accession IDs (one per line)
params.nf_core_pipeline  = null          // nf-core pipeline to auto-generate samplesheet for
params.nf_core_rnaseq_strandedness = null // Strandedness for nf-core/rnaseq samplesheet: auto | forward | reverse | unstranded
params.download_method   = 'sratools'    // Download method: sratools | ftp | aspera
params.aspera_cli        = null          // Path to Aspera CLI ascp binary
params.max_spots         = null          // Maximum number of spots per SRA sample (int, for pilots)
params.skip_fastq_download = false       // Skip FASTQ download (metadata only)
params.force_sratools_prefetch = false   // Force sratools prefetch even for FTP-available accessions
params.sra_batch_size    = 10            // Batch size for SRA download
params.outdir            = './results'
params.email             = null
params.max_memory        = '64.GB'
params.max_cpus          = 8
params.max_time          = '48.h'

// [Input Validation]
process VALIDATE_ACCESSIONS {
    script: """
    check_accessions.py --input ${params.input} \
        --download_method ${params.download_method}
    """
}

// [Metadata Fetch]
process FETCH_METADATA {
    script: """
    sra_fetch_metadata.py \
        --input ${params.input} \
        --batch_size ${params.sra_batch_size} \
        ${params.nf_core_pipeline ? "--nf_core_pipeline ${params.nf_core_pipeline}" : ''} \
        ${params.nf_core_rnaseq_strandedness ? "--strandedness ${params.nf_core_rnaseq_strandedness}" : ''} \
        --outdir ${params.outdir}
    """
}

// [FASTQ Download]
process DOWNLOAD_FASTQ {
    script: """
    download_fastq.sh \
        --method ${params.download_method} \
        ${params.aspera_cli ? "--aspera_cli ${params.aspera_cli}" : ''} \
        ${params.max_spots ? "--max_spots ${params.max_spots}" : ''} \
        ${params.skip_fastq_download ? '--skip' : ''} \
        ${params.force_sratools_prefetch ? '--force-sratools' : ''} \
        --outdir ${params.outdir}
    """
}

// [Samplesheet Generation]
process GENERATE_SAMPLESHEET {
    script: """
    generate_samplesheet.py \
        ${params.nf_core_pipeline ? "--pipeline ${params.nf_core_pipeline}" : ''} \
        ${params.nf_core_rnaseq_strandedness ? "--strandedness ${params.nf_core_rnaseq_strandedness}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Report]
process MULTIQC {
    script: """
    multiqc --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
