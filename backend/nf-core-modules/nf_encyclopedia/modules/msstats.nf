process MSSTATS {
    publishDir "${params.result_dir}/${group}", failOnError: true
    label 'process_medium'
    debug true

    input:
        tuple val(group), path(quant_peptides), path(quant_proteins)
        path input
        path contrasts

    output:
        val group
        path "msstats/msstats.input.txt"
        path "msstats/msstats.processed.rda"
        path "results/msstats.proteins.txt"
        path "logs/msstats.log"
        path "results/msstats.stats.txt", optional: true
        path "reports/msstats.qc.pdf", optional: true

    script:
    """
    mkdir -p msstats reports logs results
    msstats.R \
        ${quant_peptides} \
        ${quant_proteins} \
        ${input} \
        ${contrasts} \
        ${params.msstats.normalization} \
        ${params.msstats.reports} \
        | tee logs/msstats.log
    [ -f QCplot.pdf ] && mv QCplot.pdf reports/msstats.qc.pdf
    echo "DONE!" # Needed for proper exit
    """

    stub:
    """
    mkdir -p msstats reports logs results
    touch msstats/msstats.input.txt
    touch msstats/msstats.processed.rda
    touch results/msstats.proteins.txt
    touch logs/msstats.log
    touch results/msstats.stats.txt
    touch reports/msstats.qc.pdf
    """
}
