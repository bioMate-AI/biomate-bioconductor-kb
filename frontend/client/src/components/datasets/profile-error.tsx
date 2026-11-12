/**
 * What the panel says when a profile REQUEST failed (dataset or folder). It is a statement about
 * the request, never about the file: the file was not read, so nothing is claimed about it.
 *  - forbidden   → no access (no retry: asking again gives the same answer);
 *  - unreachable → the profiler did not answer (already retried by the query) + Try again;
 *  - failed      → the request failed with that status + Try again.
 */
import { Button } from "@/components/ui/button"
import { t } from "@/lib/i18n"
import { profileFailure, ProfileRequestError } from "./datasets-api"

export function ProfileErrorState({
  error, onRetry, retrying, testId,
}: { error: unknown; onRetry: () => void; retrying?: boolean; testId: string }) {
  const reason = profileFailure(error)
  const status = error instanceof ProfileRequestError ? error.status : undefined
  return (
    <div className="flex flex-wrap items-center gap-2" data-testid={testId} data-reason={reason}>
      <p className="text-sm text-muted-foreground">
        {reason === "forbidden"
          ? t("profile_error.forbidden")
          : reason === "unreachable"
            ? t("profile_error.unreachable")
            : t("profile_error.failed", { status: status ?? "" })}
      </p>
      {reason !== "forbidden" && (
        <Button
          size="sm"
          variant="outline"
          className="h-7 text-xs"
          disabled={retrying}
          onClick={onRetry}
          data-testid={`${testId.replace(/-error$/, "")}-retry`}
        >
          {t("profile_error.retry")}
        </Button>
      )}
    </div>
  )
}
