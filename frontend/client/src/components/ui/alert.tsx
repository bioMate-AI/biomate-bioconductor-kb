import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { CheckCircle2, XCircle, AlertCircle, Info } from "lucide-react"

import { cn } from "@/lib/utils"

const alertVariants = cva(
  "relative w-full rounded-lg border p-4 [&>svg~*]:pl-7 [&>svg+div]:translate-y-[-3px] [&>svg]:absolute [&>svg]:left-4 [&>svg]:top-4",
  {
    variants: {
      variant: {
        default: "bg-background text-foreground [&>svg]:text-foreground",
        // Success: Blue (not green) for colorblind accessibility
        success: "border-blue-200 bg-blue-50 text-blue-900 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-200 [&>svg]:text-blue-600 dark:[&>svg]:text-blue-400",
        // Error/Destructive: Orange (not red) for colorblind accessibility
        destructive: "border-orange-200 bg-orange-50 text-orange-900 dark:border-orange-800 dark:bg-orange-950 dark:text-orange-200 [&>svg]:text-orange-600 dark:[&>svg]:text-orange-400",
        // Warning: Yellow
        warning: "border-yellow-200 bg-yellow-50 text-yellow-900 dark:border-yellow-800 dark:bg-yellow-950 dark:text-yellow-200 [&>svg]:text-yellow-600 dark:[&>svg]:text-yellow-400",
        // Info: Sky blue
        info: "border-sky-200 bg-sky-50 text-sky-900 dark:border-sky-800 dark:bg-sky-950 dark:text-sky-200 [&>svg]:text-sky-600 dark:[&>svg]:text-sky-400",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
)

const alertIcons = {
  success: CheckCircle2,
  destructive: XCircle,
  warning: AlertCircle,
  info: Info,
  default: Info,
}

const Alert = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement> & VariantProps<typeof alertVariants> & { showIcon?: boolean }
>(({ className, variant = "default", showIcon = true, children, ...props }, ref) => {
  const Icon = alertIcons[variant as keyof typeof alertIcons] || alertIcons.default

  return (
    <div
      ref={ref}
      role="alert"
      className={cn(alertVariants({ variant }), className)}
      {...props}
    >
      {showIcon && <Icon className="h-4 w-4" />}
      {children}
    </div>
  )
})
Alert.displayName = "Alert"

const AlertTitle = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLHeadingElement>
>(({ className, ...props }, ref) => (
  <h5
    ref={ref}
    className={cn("mb-1 font-medium leading-none tracking-tight", className)}
    {...props}
  />
))
AlertTitle.displayName = "AlertTitle"

const AlertDescription = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLParagraphElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn("text-sm [&_p]:leading-relaxed", className)}
    {...props}
  />
))
AlertDescription.displayName = "AlertDescription"

export { Alert, AlertTitle, AlertDescription }
