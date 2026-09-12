from pathlib import Path
import numpy as np,json
root=Path(__file__).resolve().parent
with np.load(root.parent/'baseline_state_data/control_metadata.npz',allow_pickle=False) as old,np.load(root/'control_metadata.npz',allow_pickle=False) as new:
 fields=[]
 for k in old.files:
  np.testing.assert_array_equal(old[k],new[k]);fields.append(k)
 provenance=json.loads((root.parent/'baseline_state_data/provenance.json').read_text())
 assert str(new['source_etag'].item())==provenance['source_etag'];assert int(new['source_size'].item())==provenance['source_size']
 result={'all_previous_metadata_arrays_equal_current_bound_cache':fields,'current_source_etag_matches_recorded_count_extraction':True,'source_uri':str(new['source_uri'].item()),'source_etag':str(new['source_etag'].item()),'source_size':int(new['source_size'].item()),'limits':'Current metadata and recorded object identity agreement, not independent historical whole-object hashing'}
(root/'cache_verification.json').write_text(json.dumps(result,indent=2));print('Verified',len(fields),'cached arrays and source identity')
