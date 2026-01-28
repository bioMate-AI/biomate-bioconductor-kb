# Archived Workflows - Broken External API Dependencies

These workflows have been archived because they depend on external APIs that are currently non-functional.

## Archived Workflows

### 1. predict_protein_disorder_regions (biophysics)
- **Issue**: IUPred2A API at `https://iupred2a.elte.hu/iupred2a` returns 404
- **Date Archived**: 2026-01-27
- **Fix Required**:
  - Find updated API endpoint, OR
  - Install IUPred2A locally in Docker container, OR
  - Use alternative disorder predictor (e.g., DISOPRED, VSL2)

### 2. identify_fas_functional_domains (synthetic_biology)
- **Issue**: HMMER API at EBI returns 405 Method Not Allowed
- **Date Archived**: 2026-01-27
- **Fix Required**:
  - Update API request format for current EBI HMMER endpoint, OR
  - Install HMMER locally in Docker container

## To Restore

1. Fix the external API dependency
2. Test the workflow successfully
3. Move back to `subworkflows/{domain}/`
4. Update test.yml with working parameters
5. Commit to git

## Other Workflows to Monitor

The following workflows also use external APIs and should be tested:
- literature/extract_pdf_content
- literature/extract_url_content
- literature/fetch_supplementary_info_from_doi
- genetics/identify_transcription_factor_binding_sites
- genomics/generate_gene_embeddings_with_ESM_models
- molecular_biology/get_plasmid_sequence
- database/get_genes_near_ccre
- database/region_to_ccre_screen
