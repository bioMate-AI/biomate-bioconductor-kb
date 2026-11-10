"""Prospective semantic-review sidecar gate, separate from RAW/STRICT metrics.

Exact quotations and extraction confidence cannot grant model permissions.
This validates completeness/binding of a supplied review, not its scientific truth.
Original extraction rows are never modified and numeric-prior admission is absent.
"""
import hashlib
import json
import re

CHECKS=('endpoint','entity','direction','comparator','scope','claim_origin','source_overlap',
        'compound_overlap','scaffold_overlap','target_overlap')
SCOPE=('property','assay','scaffold','closure','solvent','endpoint')


def record_sha256(record):
    return hashlib.sha256(json.dumps(record,sort_keys=True,ensure_ascii=False,
        separators=(',',':'),allow_nan=False).encode()).hexdigest()


def assess_review(record,review,source_text):
    """Return permission and reasons without repairing or reclassifying the raw row.

    source_text must be the frozen primary source whose byte hash is in the review.
    Offsets refer to that exact text, not the extraction's whitespace normalization.
    Corrected claims live in this versioned sidecar and keep the original raw hash.
    """
    reasons=[]
    def require(ok,reason):
        if not ok:reasons.append(reason)
    if not isinstance(record,dict) or not isinstance(review,dict):
        return dict(permission='quarantined',reasons=['invalid_record_or_review'])
    require(review.get('schema')=='k2_semantic_review_v1','unknown_review_schema')
    require(review.get('record_id')==record.get('id') and bool(record.get('id')),'record_identity_mismatch')
    try:raw_hash=record_sha256(record)
    except (ValueError,TypeError):raw_hash=None
    require(raw_hash is not None and review.get('raw_sha256')==raw_hash,'raw_record_hash_mismatch')
    require(review.get('review_status')=='APPROVED_SCOPED_CLAIM','semantic_review_not_approved')
    require(review.get('reviewer_type') in ('human','ai_assisted'),'reviewer_type_missing')
    require(all(isinstance(review.get(k),str) and review[k].strip() for k in
        ('reviewer_id','review_revision','reviewed_at','source_id','source_url','claim','claim_origin')),'review_provenance_incomplete')
    require(review.get('claim_origin')=='primary_result','primary_source_review_required')
    require(isinstance(source_text,str),'source_text_missing')
    if isinstance(source_text,str):
        require(review.get('source_sha256')==hashlib.sha256(source_text.encode()).hexdigest(),'source_hash_mismatch')
        start,end=review.get('quote_start'),review.get('quote_end');quote=review.get('quote')
        valid=type(start) is int and type(end) is int and 0<=start<end<=len(source_text)
        require(valid and isinstance(quote,str) and bool(quote) and source_text[start:end]==quote,'exact_source_offsets_invalid')
    checks=review.get('checks',{})
    require(isinstance(checks,dict) and all(checks.get(k)=='supported' for k in CHECKS),'semantic_or_overlap_checks_unresolved')
    require(review.get('unresolved_flags')==[],'unresolved_flags')
    scope=review.get('scope',{})
    require(isinstance(scope,dict) and all(isinstance(scope.get(k),str) and scope[k].strip() and scope[k]!='*' for k in SCOPE),'scope_incomplete')
    families=review.get('source_families')
    require(isinstance(families,list) and bool(families) and all(isinstance(v,str) and v.strip() for v in families),'source_family_mapping_missing')
    requested=review.get('requested_permission')
    require(requested in ('retrieval_context','conditional_proposal'),'unsupported_permission')
    if requested=='conditional_proposal':
        require(review.get('action')=='select_parent','unimplemented_action')
        ids=review.get('approved_parent_ids')
        require(isinstance(ids,list) and bool(ids) and all(isinstance(v,str) and v.strip() for v in ids),'parent_mapping_missing')
        require(isinstance(review.get('parent_map_sha256'),str) and
                re.fullmatch('[0-9a-f]{64}',review['parent_map_sha256']) is not None,'parent_map_hash_missing')
        require(review.get('applicability_review')=='APPROVED','applicability_not_reviewed')
    return dict(permission='quarantined' if reasons else requested,reasons=reasons,
                record_id=record.get('id'),raw_sha256=raw_hash,reviewer_type=review.get('reviewer_type'))
