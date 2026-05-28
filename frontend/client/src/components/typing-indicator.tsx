import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Card } from "@/components/ui/card"
import assistantAvatar from "@assets/generated_images/AI_assistant_avatar_8313ba2b.png"

export function TypingIndicator({ phase = 'thinking' }: { phase?: 'thinking' | 'workflow' }) {
  const label = phase === 'workflow'
    ? 'BioMate is generating the workflow for you…'
    : 'BioMate is thinking…'
  return (
    <div className="flex gap-4 p-4" data-testid="chat-response-pending">
      <Avatar className="h-8 w-8 flex-shrink-0">
        <AvatarImage src={assistantAvatar} alt="Assistant" />
        <AvatarFallback>AI</AvatarFallback>
      </Avatar>

      <Card className="p-4 bg-card">
        <div className="flex items-center gap-1">
          <div className="flex space-x-1">
            <div className="w-2 h-2 bg-muted-foreground rounded-full animate-bounce" style={{ animationDelay: '0ms' }}></div>
            <div className="w-2 h-2 bg-muted-foreground rounded-full animate-bounce" style={{ animationDelay: '150ms' }}></div>
            <div className="w-2 h-2 bg-muted-foreground rounded-full animate-bounce" style={{ animationDelay: '300ms' }}></div>
          </div>
          <span className="text-xs text-muted-foreground ml-2">{label}</span>
        </div>
      </Card>
    </div>
  )
}