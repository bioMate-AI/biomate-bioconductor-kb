import { useEffect, useRef } from "react"
import { cn } from "@/lib/utils"
import { Dna, Microscope, FlaskConical, Activity } from "lucide-react"

interface BioHeroProps {
  className?: string
}

export function BioHero({ className }: BioHeroProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const ctx = canvas.getContext("2d")
    if (!ctx) return

    // Set canvas size
    canvas.width = canvas.offsetWidth
    canvas.height = canvas.offsetHeight

    // DNA helix particles
    const particles: Array<{
      x: number
      y: number
      baseY: number
      phase: number
      speed: number
      color: string
    }> = []

    const colors = [
      "rgba(20, 184, 166, 0.6)", // Teal - Guanine
      "rgba(16, 185, 129, 0.6)", // Green - Adenine
      "rgba(139, 92, 246, 0.6)", // Purple - Cytosine
      "rgba(249, 115, 22, 0.6)", // Orange - Thymine
    ]

    // Initialize particles
    for (let i = 0; i < 80; i++) {
      particles.push({
        x: (canvas.width / 80) * i,
        y: canvas.height / 2,
        baseY: canvas.height / 2,
        phase: (i / 80) * Math.PI * 4,
        speed: 0.02,
        color: colors[i % colors.length],
      })
    }

    let animationFrame: number

    const animate = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height)

      // Draw DNA helix strands
      particles.forEach((particle, index) => {
        particle.phase += particle.speed

        // Create helix wave
        const amplitude = 60
        particle.y = particle.baseY + Math.sin(particle.phase) * amplitude

        // Draw particle
        ctx.fillStyle = particle.color
        ctx.beginPath()
        ctx.arc(particle.x, particle.y, 3, 0, Math.PI * 2)
        ctx.fill()

        // Draw connections
        if (index > 0 && index % 2 === 0) {
          const prevParticle = particles[index - 1]
          ctx.strokeStyle = particle.color
          ctx.lineWidth = 1
          ctx.beginPath()
          ctx.moveTo(prevParticle.x, prevParticle.y)
          ctx.lineTo(particle.x, particle.y)
          ctx.stroke()
        }
      })

      animationFrame = requestAnimationFrame(animate)
    }

    animate()

    return () => {
      if (animationFrame) {
        cancelAnimationFrame(animationFrame)
      }
    }
  }, [])

  return (
    <div className={cn("relative overflow-hidden rounded-lg", className)}>
      {/* Background patterns */}
      <div className="absolute inset-0 bio-grid-bg opacity-50" />
      <div className="absolute inset-0 bio-molecule-dots" />

      {/* DNA Helix Canvas */}
      <canvas
        ref={canvasRef}
        className="absolute inset-0 w-full h-full"
        style={{ height: "200px" }}
      />

      {/* Scientific Icons */}
      <div className="relative z-10 p-8 flex items-center justify-around">
        <div className="flex flex-col items-center gap-2 text-bio-teal animate-molecule-glow">
          <Dna className="w-12 h-12" />
          <span className="text-xs font-medium">Genomics</span>
        </div>
        <div className="flex flex-col items-center gap-2 text-bio-green animate-molecule-glow" style={{ animationDelay: "0.5s" }}>
          <Microscope className="w-12 h-12" />
          <span className="text-xs font-medium">Analysis</span>
        </div>
        <div className="flex flex-col items-center gap-2 text-bio-purple animate-molecule-glow" style={{ animationDelay: "1s" }}>
          <FlaskConical className="w-12 h-12" />
          <span className="text-xs font-medium">Lab Tools</span>
        </div>
        <div className="flex flex-col items-center gap-2 text-bio-orange animate-molecule-glow" style={{ animationDelay: "1.5s" }}>
          <Activity className="w-12 h-12" />
          <span className="text-xs font-medium">Workflows</span>
        </div>
      </div>

      {/* Gradient overlay */}
      <div className="absolute inset-0 bg-gradient-to-t from-background/80 via-transparent to-background/80 pointer-events-none" />
    </div>
  )
}
