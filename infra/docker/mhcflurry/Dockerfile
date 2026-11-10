# biomate/mhcflurry — license-free peptide–MHC class I binding (MHCflurry 2, Apache-2.0).
# Used by nextflow_nfcore/subworkflows/immunology/mhc_binding_prediction. Models are baked in
# (mhcflurry-downloads fetch) because AWS Batch tasks have no reliable network at run time.
# Built by scripts/build_mhcflurry_image.sh; the final RUN is a load+predict smoke test, so a
# broken model install fails the build, not a user run.
FROM mambaorg/micromamba:1.5.8
RUN micromamba install -y -n base -c conda-forge python=3.11 pip tensorflow procps-ng \
 && micromamba clean -a -y
ARG MAMBA_DOCKERFILE_ACTIVATE=1
RUN pip install --no-cache-dir mhcflurry \
 && mhcflurry-downloads fetch models_class1_presentation
# Smoke: the class I presentation predictor loads and scores the canonical GILGFVFTL / HLA-A*02:01
# epitope as a strong binder (< 500 nM).
RUN python -c "from mhcflurry import Class1PresentationPredictor as P; \
    d=P.load().predict(peptides=['GILGFVFTL'], alleles=['HLA-A*02:01'], verbose=0); \
    assert d['affinity'].iloc[0] < 500, d; print('mhcflurry smoke ok', float(d['affinity'].iloc[0]))"
