/**
 * Request-scoped dataset selection.
 *
 * A chat session can remember many datasets, but a user who explicitly attaches
 * files to one operation has selected an exact input set. Never silently widen
 * that selection to another session file or to a later "latest" version.
 */
export interface DatasetReference {
  id: string;
  name?: string;
}

export interface SessionDatasetLike {
  id?: string | null;
  [key: string]: unknown;
}

export function selectReferencedDatasets<T extends SessionDatasetLike>(
  datasets: T[],
  references: DatasetReference[] | undefined,
): { datasets: T[]; missingIds: string[] } {
  if (!references?.length) return { datasets, missingIds: [] };

  const requested = [...new Set(
    references.map((ref) => typeof ref?.id === 'string' ? ref.id.trim() : '').filter(Boolean),
  )];
  if (!requested.length) return { datasets, missingIds: [] };

  const byId = new Map(
    datasets
      .filter((dataset) => !!dataset.id)
      .map((dataset) => [dataset.id as string, dataset]),
  );
  // Preserve the user's explicit reference order as well as the exact IDs.
  const selected = requested.flatMap((id) => {
    const dataset = byId.get(id);
    return dataset ? [dataset] : [];
  });
  const resolvedSet = new Set(selected.map((dataset) => dataset.id));
  return {
    datasets: selected,
    missingIds: requested.filter((id) => !resolvedSet.has(id)),
  };
}
