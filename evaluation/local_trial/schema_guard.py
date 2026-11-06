"""Shared schema+rule guardrail for param values (committee finding: 'number'-typed count params were
sampled as fractions like nPerm=0.01). The schema only says type='number' (no int/float distinction),
so we combine schema (type, allowed_values) with NAME heuristics (CLAUDE.md: rules first):
  - int-like name (iter/nperm/count/size/threads/n_/num/sections/epochs...) -> integer
  - fraction-like name (rate/cutoff/threshold/frac/prop/pval/fdr/alpha/ratio/prob) -> fraction in (0,1)
  - allowed_values present -> pick/validate from the enum
  - genome enum normalization (hg38->GRCh38, mm10->GRCm38, ...)
Used by the generators (sample_valid_value) AND by validation (validate_value)."""
import re, random

INT_NAME=re.compile(r"(?i)(iter|nperm|n_?perm|nboot|nrep|thread|cpu|ncore|nread|readlen|read_length|"
                    r"kmer|k_?mer|nfeature|n_?feature|mincount|min_count|maxcount|max_count|topgene|"
                    r"topsample|num[_a-z]*|nsection|ntissue|nprofile|_count\b|count$|size$|nclust|"
                    r"n_clust|epoch|ncomp|n_comp|ndim|n_dim|window|nbin|n_bin|depth|length$|_n$|^n$)")
FRAC_NAME=re.compile(r"(?i)(rate|cutoff|threshold|thresh|frac|proportion|prop\b|pval|p_?value|qval|"
                     r"q_?value|fdr|alpha|ratio|prob|percent|pct|weight|score|lambda|eps|tol|"
                     r"lower_frequency|min_freq|max_freq|density)")
GENOME={r"\bhg38\b":"GRCh38", r"\bhg19\b":"GRCh37", r"\bmm10\b":"GRCm38", r"\bmm9\b":"GRCm37", r"\bhg18\b":"NCBI36"}

def norm_genome(s):
    if not isinstance(s,str): return s
    for k,v in GENOME.items(): s=re.sub(k, v, s, flags=re.I)
    return s

def numeric_kind(name):
    if FRAC_NAME.search(name or ""): return "frac"
    if INT_NAME.search(name or ""): return "int"
    return "int"   # default: unknown 'number' params are far more often counts than fractions

def sample_valid_value(p):
    """Schema+name-aware gold sampler used by the generators (replaces the fraction-defaulting sampler)."""
    name=p.get("name",""); t=(p.get("type") or "").lower(); av=p.get("allowed_values") or []
    if av: return norm_genome(random.choice(av)) if isinstance(av[0],str) else random.choice(av)
    if t in ("boolean","bool"): return random.choice([True,False])
    if t in ("integer","int"): return random.choice([10,20,30,50,100])
    if t in ("number","float","double"):
        return random.choice([0.01,0.05,0.1,0.5]) if numeric_kind(name)=="frac" \
               else random.choice([10,20,30,50,100])
    return None  # string/free-text: not auto-sampled

def validate_value(p, v):
    """Returns (ok, coerced_value, reason). Used post-extraction and by validate_sft.py."""
    name=p.get("name",""); t=(p.get("type") or "").lower(); av=p.get("allowed_values") or []
    if av:
        if isinstance(v,str):
            nv=norm_genome(v)
            if nv in av: return True, nv, "ok"
            low={str(x).lower():x for x in av}
            if nv.lower() in low: return True, low[nv.lower()], "enum_case"
        return (v in av), v, ("ok" if v in av else "enum_violation")
    if t in ("boolean","bool"):
        if isinstance(v,bool): return True, v, "ok"
        if str(v).lower() in ("true","1","yes"): return True, True, "coerced_bool"
        if str(v).lower() in ("false","0","no"): return True, False, "coerced_bool"
        return False, v, "not_bool"
    if t in ("number","float","double","integer","int"):
        try: f=float(v)
        except: return False, v, "not_numeric"
        if numeric_kind(name)=="int":
            if 0<f<1: return False, v, "int_param_fraction"      # nPerm=0.01 -> reject
            return True, int(f) if f==int(f) else f, "ok"
        # fraction param: probability >1 likely a percent -> /100
        if FRAC_NAME.search(name) and f>1 and any(k in name.lower() for k in ("pval","qval","fdr","alpha","prob","rate","frac","prop")):
            return True, round(f/100,6), "fdr_scale"
        return True, f, "ok"
    if isinstance(v,str): return True, norm_genome(v), "ok"
    return True, v, "ok"
