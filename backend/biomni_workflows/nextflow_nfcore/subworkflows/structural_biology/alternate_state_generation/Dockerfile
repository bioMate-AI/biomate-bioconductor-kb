# biomate/ai-tools/pore-discriminator:latest — validated inward/outward pore discriminator
# + cross-generator consensus scorer for the alternate_state_generation subworkflow.
FROM condaforge/miniforge3:24.9.2-0
RUN mamba install -y -c conda-forge python=3.11 numpy scipy && mamba clean -a -y
RUN mkdir -p /opt/biomate
COPY scripts/pore_discriminator.py scripts/robust_score.py scripts/score_alt_states.py /opt/biomate/
WORKDIR /work
ENTRYPOINT []
