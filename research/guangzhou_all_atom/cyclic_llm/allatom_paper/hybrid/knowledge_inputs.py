"""Validate already hash-verified knowledge configuration; never infer source identity."""
from hybrid.knowledge_parent import scope_pairs


def _families(values, name, *, nonempty=False):
    if not isinstance(values, list) or any(not isinstance(v, str) or not v.strip() for v in values):
        raise ValueError(name + ' must be an explicit list of source-family IDs')
    if len(set(values)) != len(values) or (nonempty and not values):
        raise ValueError(name + ' must contain unique source-family IDs')
    return tuple(sorted(values))


def resolve_knowledge_inputs(task, manifest, *, study, training_source_families=(),
                             forbidden_source_families=()):
    """Return (scope, allowed families, forbidden families).

    Caller must verify task bytes against the frozen task hash before this call.
    The source policy permits reviewed external literature families independently
    of the assay training families. It does not establish the scientific accuracy
    of those mappings. Study runs bind the identical policy in their manifest.
    """
    if not isinstance(task, dict):
        raise ValueError('knowledge task must be an object')
    if 'scope' not in task:
        if study:
            raise ValueError('study requires explicit reviewed knowledge source policy')
        scope = dict(scope_pairs(task))
        allowed = tuple(sorted(set(training_source_families)))
        forbidden = tuple(sorted(set(forbidden_source_families)))
    else:
        if set(task) != {'scope', 'source_policy'}:
            raise ValueError('unknown knowledge task fields')
        scope = dict(scope_pairs(task['scope']))
        policy = task['source_policy']
        if not isinstance(policy, dict) or set(policy) != {
                'review_status', 'allowed_source_families', 'forbidden_source_families'}:
            raise ValueError('invalid knowledge source policy')
        if policy['review_status'] != 'FROZEN_REVIEWED':
            raise ValueError('knowledge source policy is not reviewed')
        allowed = _families(policy['allowed_source_families'], 'allowed_source_families', nonempty=True)
        declared_forbidden = _families(policy['forbidden_source_families'], 'forbidden_source_families')
        forbidden = tuple(sorted(set(declared_forbidden) | set(forbidden_source_families)))
        if study and manifest.get('knowledge_source_policy') != policy:
            raise ValueError('knowledge source policy differs from frozen study manifest')
    if set(allowed) & set(forbidden):
        raise ValueError('knowledge source allowlist overlaps forbidden source families')
    return scope, allowed, forbidden
