import { cn } from "@/lib/utils"

interface BioLoadingProps {
  className?: string
  message?: string
}

export function BioLoading({ className, message = "Processing..." }: BioLoadingProps) {
  return (
    <div className={cn("flex flex-col items-center justify-center gap-4", className)}>
      {/* DNA Helix Loader */}
      <div className="relative w-24 h-24">
        {/* Base circles */}
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-3 h-3 rounded-full bg-bio-teal animate-petri-ripple" />
        </div>
        <div className="absolute inset-0 flex items-center justify-center" style={{ animationDelay: "0.5s" }}>
          <div className="w-3 h-3 rounded-full bg-bio-green animate-petri-ripple" />
        </div>
        <div className="absolute inset-0 flex items-center justify-center" style={{ animationDelay: "1s" }}>
          <div className="w-3 h-3 rounded-full bg-bio-purple animate-petri-ripple" />
        </div>

        {/* Rotating DNA strands */}
        <div className="absolute inset-0 animate-spin" style={{ animationDuration: "3s" }}>
          <div className="absolute top-0 left-1/2 -translate-x-1/2 w-2 h-2 rounded-full bg-bio-teal" />
          <div className="absolute bottom-0 left-1/2 -translate-x-1/2 w-2 h-2 rounded-full bg-bio-green" />
        </div>
        <div className="absolute inset-0 animate-spin" style={{ animationDuration: "3s", animationDirection: "reverse" }}>
          <div className="absolute top-0 right-1/2 translate-x-1/2 w-2 h-2 rounded-full bg-bio-purple" />
          <div className="absolute bottom-0 right-1/2 translate-x-1/2 w-2 h-2 rounded-full bg-bio-orange" />
        </div>
      </div>

      {/* Message with data processing animation */}
      <div className="relative">
        <p className="text-sm text-muted-foreground">{message}</p>
        <div className="absolute bottom-0 left-0 right-0 h-0.5 animate-data-processing opacity-50" />
      </div>

      {/* Sequencing bars */}
      <div className="flex gap-1">
        {[0, 1, 2, 3, 4].map((i) => (
          <div
            key={i}
            className={cn(
              "w-1 h-8 rounded-full animate-pulse-subtle",
              i % 4 === 0 && "bg-bio-teal",
              i % 4 === 1 && "bg-bio-green",
              i % 4 === 2 && "bg-bio-purple",
              i % 4 === 3 && "bg-bio-orange"
            )}
            style={{
              animationDelay: `${i * 0.1}s`,
              animationDuration: "0.8s"
            }}
          />
        ))}
      </div>
    </div>
  )
}

interface BioProgressBarProps {
  progress: number
  className?: string
  label?: string
}

export function BioProgressBar({ progress, className, label }: BioProgressBarProps) {
  return (
    <div className={cn("w-full", className)}>
      {label && (
        <div className="flex justify-between items-center mb-2">
          <span className="text-sm font-medium">{label}</span>
          <span className="text-sm text-muted-foreground">{Math.round(progress)}%</span>
        </div>
      )}
      <div className="w-full h-2 bg-secondary rounded-full overflow-hidden">
        <div
          className="h-full bg-gradient-to-r from-bio-teal via-bio-green to-bio-purple transition-all duration-500 ease-out animate-lab-shimmer"
          style={{ width: `${progress}%` }}
        />
      </div>
    </div>
  )
}
