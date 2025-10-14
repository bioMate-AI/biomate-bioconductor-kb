import { useState, useRef, KeyboardEvent } from "react"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Send } from "lucide-react"

interface ChatInputProps {
  onSend: (message: string) => void
  disabled?: boolean
  placeholder?: string
}

export function ChatInput({
  onSend,
  disabled = false,
  placeholder = "Type your message here..."
}: ChatInputProps) {
  const [message, setMessage] = useState("")
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  const handleSend = () => {
    if (message.trim() && !disabled) {
      onSend(message.trim())
      setMessage("")
      // Reset textarea height
      if (textareaRef.current) {
        textareaRef.current.style.height = "auto"
      }
    }
  }

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const handleInput = (e: React.FormEvent<HTMLTextAreaElement>) => {
    const target = e.currentTarget
    setMessage(target.value)

    // Auto-resize textarea
    target.style.height = "auto"
    target.style.height = `${Math.min(target.scrollHeight, 200)}px`
  }

  return (
    <div className="border-t bg-background p-4">
      <div className="flex gap-2 items-end">
        <Textarea
          ref={textareaRef}
          data-testid="chat-input"
          value={message}
          onInput={handleInput}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          disabled={disabled}
          className="min-h-[60px] max-h-[200px] resize-none"
          rows={1}
        />
        <Button
          data-testid="chat-send-button"
          onClick={handleSend}
          disabled={disabled || !message.trim()}
          size="icon"
          className="h-[60px] w-[60px] flex-shrink-0"
        >
          <Send className="w-4 h-4" />
        </Button>
      </div>
    </div>
  )
}
