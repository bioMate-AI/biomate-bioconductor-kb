# BioMate UX Fixes - Implementation Guide

This document provides technical implementation details for the top 10 UX fixes identified in the UX Review Report.

---

## Fix #1: API Response Timeout (CRITICAL)

### Current State
- `/api/chat` endpoint timing out after 30+ seconds
- No timeout handling in frontend
- Users left waiting indefinitely

### Implementation Steps

#### Backend (Priority 1)
```python
# backend/lib/galaxy/webapps/galaxy/api/chat.py

from fastapi import APIRouter, HTTPException, BackgroundTasks
from fastapi.responses import StreamingResponse
import asyncio

router = APIRouter()

@router.post("/chat")
async def chat_endpoint(request: ChatRequest, background_tasks: BackgroundTasks):
    """
    Handle chat requests with timeout and streaming support
    """
    try:
        # Set reasonable timeout (15 seconds for initial response)
        response = await asyncio.wait_for(
            process_chat_message(request),
            timeout=15.0
        )
        return response
    except asyncio.TimeoutError:
        # Return partial response with status
        return {
            "response": "I'm still processing your request. This is taking longer than expected...",
            "status": "processing",
            "requestId": request.id,
            "suggestions": ["Check status", "Try a simpler query"]
        }
    except Exception as e:
        logger.error(f"Chat error: {e}")
        raise HTTPException(status_code=500, detail="Chat processing failed")

# Add streaming endpoint for long-running operations
@router.post("/chat/stream")
async def chat_stream(request: ChatRequest):
    """
    Stream chat responses for better UX
    """
    async def generate():
        async for chunk in process_chat_streaming(request):
            yield f"data: {json.dumps(chunk)}\n\n"
    
    return StreamingResponse(generate(), media_type="text/event-stream")
```

#### Frontend (Priority 1)
```typescript
// frontend/client/src/components/chat-interface.tsx

const chatMutation = useMutation({
  mutationFn: async (content: string) => {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 20000) // 20s timeout
    
    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: content,
          context: { /* ... */ }
        }),
        signal: controller.signal
      })
      
      clearTimeout(timeoutId)
      
      if (!response.ok) {
        throw new Error(`Chat API error: ${response.statusText}`)
      }
      
      return await response.json()
    } catch (error) {
      clearTimeout(timeoutId)
      
      if (error.name === 'AbortError') {
        throw new Error('Request timed out. Please try again or simplify your query.')
      }
      throw error
    }
  },
  onError: (error) => {
    // Show user-friendly error (see Fix #3)
    toast.error(error.message || 'Failed to process your message')
  }
})
```

### Testing
```typescript
// frontend/e2e/chat-timeout.e2e.ts
test('should handle API timeout gracefully', async ({ page }) => {
  await page.goto('http://localhost:5300')
  
  // Mock slow API response
  await page.route('/api/chat', route => {
    setTimeout(() => route.fulfill({ status: 200, body: '{}' }), 25000)
  })
  
  await page.fill('textarea', 'Test message')
  await page.click('button[type="submit"]')
  
  // Should show error within 20 seconds
  await expect(page.locator('text=/timed out|try again/i')).toBeVisible({ timeout: 21000 })
})
```

---

## Fix #2: Loading States (HIGH)

### Current State
- `setIsTypingLocal(true)` called but no visible indicator
- Users don't know if system is processing

### Implementation

```typescript
// frontend/client/src/components/chat-interface.tsx

// Add loading state to UI
{isTypingLocal && (
  <div className="flex gap-4 p-4" data-testid="typing-indicator">
    <Avatar className="h-8 w-8">
      <AvatarImage src={assistantAvatar} alt="Assistant" />
    </Avatar>
    <Card className="p-4 bg-card">
      <div className="flex items-center gap-2">
        <div className="flex gap-1">
          <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
          <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
          <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
        </div>
        <span className="text-sm text-muted-foreground">
          Thinking...
        </span>
      </div>
    </Card>
  </div>
)}
```

```typescript
// frontend/client/src/components/workflow-execution-panel.tsx

// Add loading state for workflow execution
{isExecuting && (
  <div className="space-y-2">
    <Progress value={progress} className="w-full" />
    <p className="text-sm text-muted-foreground">
      Executing workflow... {Math.round(progress)}%
    </p>
  </div>
)}
```

### Testing
```typescript
test('should show typing indicator during API call', async ({ page }) => {
  await page.goto('http://localhost:5300')
  
  // Delay API response
  await page.route('/api/chat', route => {
    setTimeout(() => route.fulfill({ status: 200, body: JSON.stringify({ response: 'Test' }) }), 2000)
  })
  
  await page.fill('textarea', 'Test message')
  await page.click('button[type="submit"]')
  
  // Should show typing indicator immediately
  await expect(page.locator('[data-testid="typing-indicator"]')).toBeVisible({ timeout: 500 })
  
  // Should hide after response
  await expect(page.locator('[data-testid="typing-indicator"]')).not.toBeVisible({ timeout: 3000 })
})
```

---

## Fix #3: Error Handling (HIGH)

### Implementation

```typescript
// frontend/client/src/lib/toast.ts
import { toast as sonnerToast } from 'sonner'

export const toast = {
  error: (message: string, options?: { action?: { label: string, onClick: () => void } }) => {
    sonnerToast.error(message, {
      duration: 5000,
      action: options?.action,
      ...options
    })
  },
  success: (message: string) => {
    sonnerToast.success(message, { duration: 3000 })
  },
  info: (message: string) => {
    sonnerToast.info(message, { duration: 4000 })
  }
}
```

```typescript
// frontend/client/src/components/chat-interface.tsx

const chatMutation = useMutation({
  mutationFn: async (content: string) => { /* ... */ },
  onError: (error: Error) => {
    console.error('[ChatInterface] API Error:', error)
    
    // Determine error type and show appropriate message
    let errorMessage = 'Failed to process your message'
    let retryAction = undefined
    
    if (error.message.includes('timeout')) {
      errorMessage = 'Request timed out. The server is taking longer than expected.'
      retryAction = {
        label: 'Retry',
        onClick: () => chatMutation.mutate(lastMessage)
      }
    } else if (error.message.includes('network')) {
      errorMessage = 'Network error. Please check your connection.'
      retryAction = {
        label: 'Retry',
        onClick: () => chatMutation.mutate(lastMessage)
      }
    } else if (error.message.includes('500')) {
      errorMessage = 'Server error. Our team has been notified.'
    }
    
    toast.error(errorMessage, { action: retryAction })
    
    setIsTypingLocal(false)
  },
  onSuccess: (data) => { /* ... */ }
})
```

```typescript
// Add error boundary for React errors
// frontend/client/src/components/error-boundary.tsx

import { Component, ReactNode } from 'react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'

interface Props {
  children: ReactNode
}

interface State {
  hasError: boolean
  error?: Error
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: any) {
    console.error('ErrorBoundary caught:', error, errorInfo)
    // Send to error tracking service
  }

  render() {
    if (this.state.hasError) {
      return (
        <Card className="p-6 m-4">
          <h2 className="text-lg font-semibold mb-2">Something went wrong</h2>
          <p className="text-sm text-muted-foreground mb-4">
            We encountered an unexpected error. Please try refreshing the page.
          </p>
          <Button onClick={() => window.location.reload()}>
            Refresh Page
          </Button>
        </Card>
      )
    }

    return this.props.children
  }
}
```

---

## Fix #4: Workflow Prerequisites (HIGH)

### Implementation

```typescript
// frontend/client/src/components/workflow-prerequisites-panel.tsx

interface WorkflowPrerequisite {
  id: string
  label: string
  type: 'file' | 'parameter' | 'selection'
  required: boolean
  satisfied: boolean
  helpText?: string
  value?: any
}

export function WorkflowPrerequisitesPanel({
  prerequisites,
  onUpdate,
  onExecute
}: {
  prerequisites: WorkflowPrerequisite[]
  onUpdate: (id: string, value: any) => void
  onExecute: () => void
}) {
  const allSatisfied = prerequisites.every(p => !p.required || p.satisfied)
  
  return (
    <Card className="p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="font-semibold">Before You Run</h3>
        <Badge variant={allSatisfied ? 'success' : 'warning'}>
          {prerequisites.filter(p => p.satisfied).length} / {prerequisites.length} Ready
        </Badge>
      </div>
      
      <div className="space-y-3">
        {prerequisites.map(prereq => (
          <div key={prereq.id} className="flex items-start gap-3">
            {prereq.satisfied ? (
              <CheckCircle className="w-5 h-5 text-green-500 mt-0.5" />
            ) : (
              <Circle className="w-5 h-5 text-muted-foreground mt-0.5" />
            )}
            
            <div className="flex-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium">{prereq.label}</span>
                {prereq.required && (
                  <Badge variant="outline" className="text-xs">Required</Badge>
                )}
              </div>
              
              {prereq.helpText && (
                <p className="text-xs text-muted-foreground mt-1">
                  {prereq.helpText}
                </p>
              )}
              
              {!prereq.satisfied && prereq.type === 'file' && (
                <Button
                  size="sm"
                  variant="outline"
                  className="mt-2"
                  onClick={() => {/* Open file picker */}}
                >
                  Upload File
                </Button>
              )}
            </div>
          </div>
        ))}
      </div>
      
      <Button
        className="w-full"
        disabled={!allSatisfied}
        onClick={onExecute}
      >
        {allSatisfied ? 'Run Workflow' : 'Complete Prerequisites to Run'}
      </Button>
      
      {!allSatisfied && (
        <p className="text-xs text-center text-muted-foreground">
          Please complete all required items above
        </p>
      )}
    </Card>
  )
}
```

---

## Fix #5: Onboarding (MEDIUM)

### Implementation

```typescript
// frontend/client/src/components/onboarding-tour.tsx

import { useState, useEffect } from 'react'
import { Dialog, DialogContent } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'

interface OnboardingStep {
  title: string
  description: string
  image?: string
  target?: string // CSS selector for highlight
}

const ONBOARDING_STEPS: OnboardingStep[] = [
  {
    title: 'Welcome to BioMate!',
    description: 'BioMate helps you discover bioinformatics tools, build workflows, and analyze data through natural conversation.',
    image: '/onboarding/welcome.png'
  },
  {
    title: 'Chat with AI',
    description: 'Just type what you want to do in plain English. For example: "Analyze RNA-seq data" or "Find variant calling tools"',
    target: 'textarea'
  },
  {
    title: 'Generate Workflows',
    description: 'BioMate will create complete workflows for you. Review the steps, customize parameters, and run with one click.',
    target: '[data-testid="workflow-viewer"]'
  },
  {
    title: 'Track Progress',
    description: 'Monitor your workflow execution in real-time and download results when complete.',
    target: '[data-testid="execution-panel"]'
  }
]

export function OnboardingTour() {
  const [isOpen, setIsOpen] = useState(false)
  const [currentStep, setCurrentStep] = useState(0)
  
  useEffect(() => {
    // Check if user has seen onboarding
    const hasSeenOnboarding = localStorage.getItem('biomate_onboarding_completed')
    if (!hasSeenOnboarding) {
      setIsOpen(true)
    }
  }, [])
  
  const handleNext = () => {
    if (currentStep < ONBOARDING_STEPS.length - 1) {
      setCurrentStep(currentStep + 1)
    } else {
      handleComplete()
    }
  }
  
  const handleComplete = () => {
    localStorage.setItem('biomate_onboarding_completed', 'true')
    setIsOpen(false)
  }
  
  const handleSkip = () => {
    localStorage.setItem('biomate_onboarding_completed', 'true')
    setIsOpen(false)
  }
  
  const step = ONBOARDING_STEPS[currentStep]
  const progress = ((currentStep + 1) / ONBOARDING_STEPS.length) * 100
  
  return (
    <Dialog open={isOpen} onOpenChange={setIsOpen}>
      <DialogContent className="max-w-md">
        <div className="space-y-4">
          <Progress value={progress} className="w-full" />
          
          <div className="space-y-2">
            <h2 className="text-xl font-semibold">{step.title}</h2>
            <p className="text-sm text-muted-foreground">{step.description}</p>
          </div>
          
          {step.image && (
            <img src={step.image} alt={step.title} className="w-full rounded-lg" />
          )}
          
          <div className="flex justify-between">
            <Button variant="ghost" onClick={handleSkip}>
              Skip Tour
            </Button>
            
            <div className="flex gap-2">
              {currentStep > 0 && (
                <Button variant="outline" onClick={() => setCurrentStep(currentStep - 1)}>
                  Back
                </Button>
              )}
              <Button onClick={handleNext}>
                {currentStep < ONBOARDING_STEPS.length - 1 ? 'Next' : 'Get Started'}
              </Button>
            </div>
          </div>
          
          <p className="text-xs text-center text-muted-foreground">
            Step {currentStep + 1} of {ONBOARDING_STEPS.length}
          </p>
        </div>
      </DialogContent>
    </Dialog>
  )
}
```

---

## Fix #6: File Upload UX (MEDIUM)

### Implementation

```typescript
// frontend/client/src/components/file-upload-button.tsx

import { Upload } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { Progress } from '@/components/ui/progress'
import { useState } from 'react'

const SUPPORTED_FORMATS = ['.fastq', '.fq', '.bam', '.sam', '.vcf', '.bed', '.gtf', '.gff']
const MAX_FILE_SIZE_MB = 500

export function FileUploadButton({ onUpload }: { onUpload: (files: File[]) => void }) {
  const [uploading, setUploading] = useState(false)
  const [uploadProgress, setUploadProgress] = useState(0)
  
  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || [])
    
    // Validate files
    for (const file of files) {
      const sizeMB = file.size / (1024 * 1024)
      if (sizeMB > MAX_FILE_SIZE_MB) {
        toast.error(`File ${file.name} exceeds ${MAX_FILE_SIZE_MB}MB limit`)
        return
      }
      
      const ext = '.' + file.name.split('.').pop()?.toLowerCase()
      if (!SUPPORTED_FORMATS.includes(ext)) {
        toast.error(`File ${file.name} has unsupported format. Supported: ${SUPPORTED_FORMATS.join(', ')}`)
        return
      }
    }
    
    // Upload with progress
    setUploading(true)
    try {
      // Simulate upload progress (replace with actual upload logic)
      for (let i = 0; i <= 100; i += 10) {
        setUploadProgress(i)
        await new Promise(resolve => setTimeout(resolve, 100))
      }
      
      onUpload(files)
      toast.success(`${files.length} file(s) uploaded successfully`)
    } catch (error) {
      toast.error('Upload failed. Please try again.')
    } finally {
      setUploading(false)
      setUploadProgress(0)
    }
  }
  
  return (
    <div className="relative">
      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            variant="outline"
            size="icon"
            disabled={uploading}
            onClick={() => document.getElementById('file-input')?.click()}
          >
            <Upload className="w-4 h-4" />
          </Button>
        </TooltipTrigger>
        <TooltipContent side="top" className="max-w-xs">
          <p className="font-semibold mb-1">Upload Files</p>
          <p className="text-xs mb-2">
            Supported: {SUPPORTED_FORMATS.join(', ')}
          </p>
          <p className="text-xs text-muted-foreground">
            Max size: {MAX_FILE_SIZE_MB}MB per file
          </p>
          <p className="text-xs text-muted-foreground mt-1">
            Files are processed securely and deleted after 24 hours
          </p>
        </TooltipContent>
      </Tooltip>
      
      <input
        id="file-input"
        type="file"
        multiple
        accept={SUPPORTED_FORMATS.join(',')}
        className="hidden"
        onChange={handleFileSelect}
      />
      
      {uploading && (
        <div className="absolute top-full mt-2 w-48 p-2 bg-card border rounded-lg shadow-lg">
          <p className="text-xs mb-1">Uploading...</p>
          <Progress value={uploadProgress} className="w-full" />
        </div>
      )}
    </div>
  )
}
```

---

## Testing Strategy

### Unit Tests
```typescript
// frontend/client/src/components/__tests__/chat-interface.test.tsx

describe('ChatInterface', () => {
  it('should show loading indicator during API call', async () => {
    const { getByTestId } = render(<ChatInterface />)
    
    // Mock slow API
    server.use(
      rest.post('/api/chat', (req, res, ctx) => {
        return res(ctx.delay(2000), ctx.json({ response: 'Test' }))
      })
    )
    
    fireEvent.change(getByTestId('chat-input'), { target: { value: 'Test' } })
    fireEvent.click(getByTestId('send-button'))
    
    expect(getByTestId('typing-indicator')).toBeInTheDocument()
    
    await waitFor(() => {
      expect(queryByTestId('typing-indicator')).not.toBeInTheDocument()
    })
  })
  
  it('should show error toast on API failure', async () => {
    const { getByTestId } = render(<ChatInterface />)
    
    server.use(
      rest.post('/api/chat', (req, res, ctx) => {
        return res(ctx.status(500))
      })
    )
    
    fireEvent.change(getByTestId('chat-input'), { target: { value: 'Test' } })
    fireEvent.click(getByTestId('send-button'))
    
    await waitFor(() => {
      expect(screen.getByText(/failed to process/i)).toBeInTheDocument()
    })
  })
})
```

### E2E Tests
```typescript
// frontend/e2e/ux-improvements.e2e.ts

test('complete user journey with all UX improvements', async ({ page }) => {
  await page.goto('http://localhost:5300')
  
  // 1. Onboarding should appear for first-time users
  await expect(page.locator('text=/welcome to biomate/i')).toBeVisible()
  await page.click('button:has-text("Next")')
  await page.click('button:has-text("Get Started")')
  
  // 2. Type message and verify loading state
  await page.fill('textarea', 'Build RNA-seq QC workflow')
  await page.click('button[type="submit"]')
  await expect(page.locator('[data-testid="typing-indicator"]')).toBeVisible()
  
  // 3. Wait for response (with timeout handling)
  await expect(page.locator('text=/workflow|quality control/i')).toBeVisible({ timeout: 20000 })
  
  // 4. Verify prerequisites panel
  await expect(page.locator('text=/before you run/i')).toBeVisible()
  
  // 5. Upload file
  await page.click('button:has(svg[class*="upload"])')
  await page.setInputFiles('input[type="file"]', 'test-data/sample.fastq')
  await expect(page.locator('text=/uploaded successfully/i')).toBeVisible()
  
  // 6. Execute workflow
  await page.click('button:has-text("Run Workflow")')
  await expect(page.locator('[data-testid="execution-progress"]')).toBeVisible()
  
  // 7. Verify results
  await expect(page.locator('text=/completed|success/i')).toBeVisible({ timeout: 60000 })
})
```

---

## Monitoring and Analytics

### Add User Experience Metrics

```typescript
// frontend/client/src/lib/analytics.ts

export const trackUXMetric = (metric: string, value: number, metadata?: Record<string, any>) => {
  // Send to analytics service
  if (window.gtag) {
    window.gtag('event', metric, {
      value,
      ...metadata
    })
  }
  
  console.log('[Analytics]', metric, value, metadata)
}

// Usage examples:
trackUXMetric('chat_response_time', responseTime, { query: userMessage })
trackUXMetric('workflow_execution_time', executionTime, { workflowId })
trackUXMetric('error_rate', 1, { errorType: 'api_timeout' })
```

### Performance Monitoring

```typescript
// frontend/client/src/lib/performance.ts

export const measurePerformance = (name: string, fn: () => Promise<any>) => {
  const start = performance.now()
  
  return fn().finally(() => {
    const duration = performance.now() - start
    trackUXMetric(`performance_${name}`, duration)
    
    if (duration > 3000) {
      console.warn(`[Performance] ${name} took ${duration}ms (>3s threshold)`)
    }
  })
}
```

---

## Rollout Plan

### Phase 1: Critical Fixes (Week 1)
- [ ] Fix #1: API timeout handling
- [ ] Fix #2: Loading states
- [ ] Fix #3: Error handling
- [ ] Deploy to staging
- [ ] Run full E2E test suite
- [ ] Performance testing

### Phase 2: High Priority (Week 2)
- [ ] Fix #4: Workflow prerequisites
- [ ] Fix #6: File upload UX
- [ ] Fix #8: Connection status
- [ ] Deploy to staging
- [ ] User acceptance testing

### Phase 3: Medium Priority (Week 3-4)
- [ ] Fix #5: Onboarding
- [ ] Fix #7: Session management
- [ ] Fix #9: Navigation
- [ ] Fix #10: Suggestion clarity
- [ ] Deploy to production
- [ ] Monitor metrics

### Phase 4: Validation (Week 5)
- [ ] Collect user feedback
- [ ] Analyze UX metrics
- [ ] Iterate on improvements
- [ ] Document lessons learned

---

## Success Metrics

### Key Performance Indicators

1. **API Response Time**
   - Target: <5 seconds for 95% of requests
   - Measure: Average and P95 response time

2. **Error Rate**
   - Target: <1% of chat requests fail
   - Measure: Failed requests / total requests

3. **User Engagement**
   - Target: 80% of users complete at least one workflow
   - Measure: Workflow completion rate

4. **Time to First Workflow**
   - Target: <5 minutes from landing to first workflow execution
   - Measure: Time from page load to first "Run" click

5. **User Satisfaction**
   - Target: >4.0/5.0 average rating
   - Measure: Post-interaction survey

---

## Conclusion

These implementation guidelines provide a clear path to addressing the top UX issues identified in the review. By following this phased approach and monitoring key metrics, we can significantly improve the BioMate user experience and increase user success rates.

**Next Steps:**
1. Review and prioritize fixes with team
2. Create tickets for each fix
3. Assign ownership and set deadlines
4. Begin Phase 1 implementation
5. Schedule weekly progress reviews
