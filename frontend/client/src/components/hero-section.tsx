import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ArrowRight, MessageCircle, Zap, Workflow } from "lucide-react"
import heroBackground from "@assets/generated_images/Scientific_data_visualization_hero_background_10f26574.png"

interface HeroSectionProps {
  onStartChat?: () => void
  onExploreTools?: () => void
  onViewWorkflows?: () => void
}

export function HeroSection({
  onStartChat = () => console.log('Start chat triggered'),
  onExploreTools = () => console.log('Explore tools triggered'),
  onViewWorkflows = () => console.log('View workflows triggered')
}: HeroSectionProps) {
  return (
    <div className="relative overflow-hidden">
      {/* Background Image with Gradient Overlay */}
      <div 
        className="absolute inset-0 bg-cover bg-center bg-no-repeat"
        style={{ backgroundImage: `url(${heroBackground})` }}
      >
        <div className="absolute inset-0 bg-gradient-to-r from-primary/90 to-primary/70" />
      </div>
      
      {/* Content */}
      <div className="relative container mx-auto px-4 py-24 text-center text-white">
        <Badge variant="outline" className="mb-6 border-white/20 bg-white/10 text-white">
          <Zap className="w-3 h-3 mr-1" />
          Simplifying Bioinformatics
        </Badge>
        
        <h1 className="text-4xl md:text-6xl font-bold mb-6 leading-tight">
          Bioinformatics,
          <br />
          <span className="text-white/90">Made Simple</span>
        </h1>
        
        <p className="text-xl md:text-2xl mb-8 text-white/90 max-w-3xl mx-auto leading-relaxed">
          Transform complex bioinformatics workflows into natural conversations. 
          Chat with AI to discover tools, build pipelines, and analyze your data with ease.
        </p>
        
        <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-12">
          <Button 
            size="lg" 
            className="bg-white text-primary hover:bg-white/90 border-white/20"
            onClick={onStartChat}
            data-testid="button-start-chat"
          >
            <MessageCircle className="w-4 h-4 mr-2" />
            Start Chatting
            <ArrowRight className="w-4 h-4 ml-2" />
          </Button>
          
          <Button 
            variant="outline" 
            size="lg"
            className="border-white/20 bg-white/10 text-white hover:bg-white/20 backdrop-blur-sm"
            onClick={onExploreTools}
            data-testid="button-explore-tools"
          >
            Explore Tools
          </Button>
          
          <Button 
            variant="outline" 
            size="lg"
            className="border-white/20 bg-white/10 text-white hover:bg-white/20 backdrop-blur-sm"
            onClick={onViewWorkflows}
            data-testid="button-view-workflows"
          >
            <Workflow className="w-4 h-4 mr-2" />
            View Workflows
          </Button>
        </div>
        
        {/* Feature highlights */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-4xl mx-auto">
          <div className="text-center">
            <div className="w-12 h-12 bg-white/20 rounded-lg flex items-center justify-center mx-auto mb-3">
              <MessageCircle className="w-6 h-6 text-white" />
            </div>
            <h3 className="font-semibold mb-2">Natural Conversation</h3>
            <p className="text-white/80 text-sm">Ask questions in plain English and get tool recommendations</p>
          </div>
          
          <div className="text-center">
            <div className="w-12 h-12 bg-white/20 rounded-lg flex items-center justify-center mx-auto mb-3">
              <Workflow className="w-6 h-6 text-white" />
            </div>
            <h3 className="font-semibold mb-2">Simplified Workflows</h3>
            <p className="text-white/80 text-sm">Complex pipelines broken down into easy-to-follow steps</p>
          </div>
          
          <div className="text-center">
            <div className="w-12 h-12 bg-white/20 rounded-lg flex items-center justify-center mx-auto mb-3">
              <Zap className="w-6 h-6 text-white" />
            </div>
            <h3 className="font-semibold mb-2">Powered by AI</h3>
            <p className="text-white/80 text-sm">Access powerful bioinformatics tools through an intuitive interface</p>
          </div>
        </div>
      </div>
    </div>
  )
}