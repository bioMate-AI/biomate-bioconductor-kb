import { Skeleton } from "@/components/ui/skeleton"
import { Card } from "@/components/ui/card"

export function ChatLoading() {
  return (
    <div className="flex gap-4 p-4">
      {/* Avatar skeleton */}
      <Skeleton className="h-8 w-8 rounded-full flex-shrink-0" />

      <div className="flex-1 space-y-3">
        {/* Message card skeleton */}
        <Card className="p-4 space-y-2">
          <Skeleton className="h-4 w-3/4" />
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-5/6" />
        </Card>

        {/* Recommendations skeleton */}
        <Card className="p-4 space-y-3 border-blue-200 bg-blue-50/50">
          <div className="flex items-center gap-2">
            <Skeleton className="h-4 w-4" />
            <Skeleton className="h-4 w-32" />
          </div>
          <div className="space-y-2">
            <Skeleton className="h-16 w-full rounded-lg" />
            <Skeleton className="h-16 w-full rounded-lg" />
          </div>
        </Card>
      </div>
    </div>
  )
}

export function ToolRecommendationLoading() {
  return (
    <Card className="border-blue-200 bg-blue-50/50 p-4">
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <Skeleton className="h-4 w-4" />
          <Skeleton className="h-4 w-40" />
        </div>
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <div key={i} className="border rounded-lg p-3 bg-background">
              <div className="flex items-center justify-between gap-2">
                <div className="flex-1 space-y-2">
                  <div className="flex items-center gap-2">
                    <Skeleton className="h-4 w-32" />
                    <Skeleton className="h-5 w-16" />
                  </div>
                  <Skeleton className="h-3 w-48" />
                </div>
                <Skeleton className="h-8 w-8" />
              </div>
            </div>
          ))}
        </div>
      </div>
    </Card>
  )
}
