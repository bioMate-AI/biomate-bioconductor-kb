# biomate/cryo-em-tools:1.0 — publication molecular rendering (PyMOL) for the STRUCTURE_OVERVIEW module.
# Backs modules/cryo_em_tools/visualization.nf, which calls
# /opt/biomate_cryo_em/scripts/structure_visualization.py.
FROM condaforge/miniforge3:24.9.2-0

# Install into a DEDICATED env (not base): pymol-open-source's deps drop libxml2.so.2
# from base, which breaks the base mamba binary itself on the next call. Isolating the
# install keeps base mamba intact. Put the env first on PATH so `python3` = the viz env.
RUN mamba create -y -n viz -c conda-forge \
        python=3.11 \
        pymol-open-source \
        numpy \
        matplotlib \
    && (mamba clean -a -y || true)
ENV PATH=/opt/conda/envs/viz/bin:$PATH

RUN mkdir -p /opt/biomate_cryo_em/scripts
COPY scripts/structure_visualization.py /opt/biomate_cryo_em/scripts/structure_visualization.py

# smoke test: the script imports + mock path works at build time
RUN python3 /opt/biomate_cryo_em/scripts/structure_visualization.py --mock --output_dir /tmp/_t --report /tmp/_t/r.json

WORKDIR /work
ENTRYPOINT []
