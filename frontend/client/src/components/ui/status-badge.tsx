import { Badge } from "@/components/ui/badge"
import { CheckCircle2, XCircle, AlertCircle, Clock, Loader2 } from "lucide-react"

type StatusType = "success" | "error" | "warning" | "info" | "pending" | "running"

interface StatusBadgeProps {
  status: StatusType
  children: React.ReactNode
  className?: string
}

const statusConfig = {
  success: {
    icon: CheckCircle2,
    className: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200 border-blue-200 dark:border-blue-800",
    iconClassName: "text-blue-600 dark:text-blue-400"
  },
  error: {
    icon: XCircle,
    className: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200 border-orange-200 dark:border-orange-800",
    iconClassName: "text-orange-600 dark:text-orange-400"
  },
  warning: {
    icon: AlertCircle,
    className: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200 border-yellow-200 dark:border-yellow-800",
    iconClassName: "text-yellow-600 dark:text-yellow-400"
  },
  info: {
    icon: AlertCircle,
    className: "bg-sky-100 text-sky-800 dark:bg-sky-900 dark:text-sky-200 border-sky-200 dark:border-sky-800",
    iconClassName: "text-sky-600 dark:text-sky-400"
  },
  pending: {
    icon: Clock,
    className: "bg-gray-100 text-gray-800 dark:bg-gray-800 dark:text-gray-200 border-gray-200 dark:border-gray-700",
    iconClassName: "text-gray-600 dark:text-gray-400"
  },
  running: {
    icon: Loader2,
    className: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200 border-purple-200 dark:border-purple-800",
    iconClassName: "text-purple-600 dark:text-purple-400 animate-spin"
  }
}

export function StatusBadge({ status, children, className = "" }: StatusBadgeProps) {
  const config = statusConfig[status]
  const Icon = config.icon

  return (
    <Badge
      variant="outline"
      className={`flex items-center gap-1.5 ${config.className} ${className}`}
    >
      <Icon className={`h-3.5 w-3.5 ${config.iconClassName}`} />
      {children}
    </Badge>
  )
}
