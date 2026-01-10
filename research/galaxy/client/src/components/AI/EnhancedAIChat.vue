<!--
Enhanced AI Chat Component for Conversational Workflow Generation

⚠️ **NEW FILE** - This is a completely new Vue component that provides an enhanced
chat interface for conversational workflow generation. It does not modify any
existing components.

Safe to add - does not modify existing functionality.
-->
<template>
    <div class="enhanced-ai-chat">
        <!-- 聊天头部 -->
        <div class="chat-header">
            <div class="ai-status">
                <i class="fa fa-robot"></i>
                <span class="ai-title">Galaxy Workflow Assistant</span>
                <span class="connection-status" :class="{ connected: isConnected }">
                    {{ isConnected ? 'Online' : 'Offline' }}
                </span>
            </div>
            
            <!-- 上下文指示器 -->
            <div v-if="conversationContext.currentTask" class="context-indicator">
                <i class="fa fa-tasks"></i>
                <span>{{ getContextDescription() }}</span>
                <b-button size="sm" variant="outline-secondary" @click="clearContext">
                    <i class="fa fa-times"></i>
                </b-button>
            </div>
        </div>

        <!-- 消息区域 -->
        <div class="messages-container" ref="messagesContainer">
            <div 
                v-for="message in messages" 
                :key="message.id"
                class="message-wrapper"
                :class="message.type"
            >
                <div class="message-bubble">
                    <div class="message-header">
                        <span class="sender">{{ message.type === 'user' ? 'You' : 'AI Assistant' }}</span>
                        <span class="timestamp">{{ formatTime(message.timestamp) }}</span>
                    </div>
                    
                    <div class="message-content">{{ message.text }}</div>
                    
                    <!-- AI 响应的特殊内容 -->
                    <div v-if="message.type === 'ai'" class="ai-response-content">
                        
                        <!-- 工作流模板展示 -->
                        <div v-if="message.workflowTemplates?.length" class="workflow-templates">
                            <h5><i class="fa fa-sitemap"></i> Generated Workflow</h5>
                            <div 
                                v-for="template in message.workflowTemplates" 
                                :key="template.id"
                                class="workflow-template-card"
                            >
                                <div class="template-header">
                                    <strong>{{ template.name }}</strong>
                                    <span class="step-count">{{ template.steps?.length || 0 }} steps</span>
                                </div>
                                <div class="template-description">{{ template.description }}</div>
                                
                                <!-- 工作流步骤预览 -->
                                <div class="workflow-steps-preview">
                                    <div 
                                        v-for="(step, index) in template.steps?.slice(0, 3)" 
                                        :key="index"
                                        class="step-preview"
                                    >
                                        <i class="fa fa-arrow-right"></i>
                                        <span>{{ step.name }}</span>
                                    </div>
                                    <div v-if="template.steps?.length > 3" class="more-steps">
                                        +{{ template.steps.length - 3 }} more steps
                                    </div>
                                </div>
                                
                                <!-- 操作按钮 -->
                                <div class="template-actions">
                                    <b-button 
                                        variant="primary" 
                                        size="sm"
                                        @click="createWorkflow(template)"
                                        :disabled="isCreatingWorkflow"
                                    >
                                        <i class="fa fa-plus"></i>
                                        {{ isCreatingWorkflow ? 'Creating...' : 'Create & Edit' }}
                                    </b-button>
                                    <b-button 
                                        variant="outline-primary" 
                                        size="sm"
                                        @click="previewWorkflow(template)"
                                    >
                                        <i class="fa fa-eye"></i>
                                        Preview
                                    </b-button>
                                    <b-button 
                                        variant="outline-secondary" 
                                        size="sm"
                                        @click="modifyWorkflow(template)"
                                    >
                                        <i class="fa fa-edit"></i>
                                        Modify
                                    </b-button>
                                </div>
                            </div>
                        </div>
                        
                        <!-- 建议操作 -->
                        <div v-if="message.suggestedActions?.length" class="suggested-actions">
                            <b-button 
                                v-for="action in message.suggestedActions"
                                :key="action.id"
                                :variant="action.primary ? 'primary' : 'outline-secondary'"
                                size="sm"
                                class="mr-2 mb-2"
                                @click="performSuggestedAction(action)"
                            >
                                {{ action.label }}
                            </b-button>
                        </div>
                        
                        <!-- 澄清问题 -->
                        <div v-if="message.clarificationQuestions?.length" class="clarification-questions">
                            <h6><i class="fa fa-question-circle"></i> I need more information:</h6>
                            <div class="quick-questions">
                                <b-button 
                                    v-for="(question, index) in message.clarificationQuestions"
                                    :key="index"
                                    variant="outline-info"
                                    size="sm"
                                    class="mb-2 mr-2"
                                    @click="sendMessage(question)"
                                >
                                    {{ question }}
                                </b-button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- 加载指示器 -->
            <div v-if="isLoading" class="loading-indicator">
                <div class="typing-indicator">
                    <span></span>
                    <span></span>
                    <span></span>
                </div>
                <span>AI is thinking...</span>
            </div>
        </div>

        <!-- 输入区域 -->
        <div class="input-area">
            <div class="input-wrapper">
                <b-form-textarea
                    v-model="currentMessage"
                    placeholder="Describe the workflow you want to create... (e.g., 'I want to analyze RNA-seq data to find differentially expressed genes')"
                    rows="2"
                    max-rows="4"
                    @keydown.enter.exact.prevent="sendMessage"
                    @keydown.enter.shift.exact="$event.target.value += '\n'"
                    :disabled="isLoading"
                />
                <b-button 
                    variant="primary" 
                    @click="sendMessage"
                    :disabled="!currentMessage.trim() || isLoading"
                    class="send-button"
                >
                    <i class="fa fa-paper-plane"></i>
                </b-button>
            </div>
            
            <!-- 快速建议 -->
            <div v-if="quickSuggestions.length && !conversationContext.currentTask" class="quick-suggestions">
                <span class="suggestions-label">Try:</span>
                <b-button 
                    v-for="suggestion in quickSuggestions"
                    :key="suggestion"
                    variant="outline-light"
                    size="sm"
                    class="mr-2"
                    @click="sendMessage(suggestion)"
                >
                    {{ suggestion }}
                </b-button>
            </div>
        </div>
    </div>
</template>

<script setup>
import { ref, reactive, onMounted, nextTick, computed } from 'vue'
import { useRouter } from 'vue-router'
import axios from 'axios'
import { getAppRoot } from '@/utils/localization'

// Props
const props = defineProps({
    initialContext: {
        type: Object,
        default: () => ({})
    }
})

// Emits
const emit = defineEmits(['workflowCreated', 'contextChanged'])

// Router
const router = useRouter()

// Reactive data
const messages = ref([])
const currentMessage = ref('')
const isLoading = ref(false)
const isConnected = ref(false)
const isCreatingWorkflow = ref(false)
const messagesContainer = ref(null)

const conversationContext = reactive({
    sessionId: `session_${Date.now()}`,
    currentTask: null,
    workflowInProgress: null,
    userPreferences: {},
    sessionHistory: []
})

const quickSuggestions = ref([
    "Analyze RNA-seq data",
    "Call variants from WGS data", 
    "Assemble a genome",
    "Quality control for sequencing data"
])

// Computed
const getContextDescription = computed(() => {
    if (conversationContext.currentTask === 'workflow_creation') {
        return 'Creating workflow...'
    }
    return conversationContext.currentTask || ''
})

// Methods
const sendMessage = async (messageText = null) => {
    const text = messageText || currentMessage.value.trim()
    if (!text) return
    
    // Add user message
    addMessage(text, 'user')
    currentMessage.value = ''
    
    isLoading.value = true
    
    try {
        const response = await axios.post(`${getAppRoot()}api/ai_assistant/chat`, {
            message: text,
            context: conversationContext,
            intent_hints: []
        })
        
        // Add AI response
        const aiMessage = {
            id: Date.now(),
            type: 'ai',
            text: response.data.response,
            timestamp: Date.now(),
            workflowTemplates: response.data.workflow_templates,
            suggestedActions: response.data.suggested_actions,
            clarificationQuestions: response.data.clarification_questions
        }
        
        messages.value.push(aiMessage)
        
        // Update context
        if (response.data.context_update) {
            Object.assign(conversationContext, response.data.context_update)
            emit('contextChanged', conversationContext)
        }
        
    } catch (error) {
        console.error('Chat error:', error)
        addMessage('Sorry, I encountered an error. Please try again.', 'ai')
    }
    
    isLoading.value = false
    await nextTick()
    scrollToBottom()
}

const addMessage = (text, type) => {
    messages.value.push({
        id: Date.now(),
        type,
        text,
        timestamp: Date.now()
    })
}

const createWorkflow = async (template) => {
    isCreatingWorkflow.value = true
    
    try {
        const response = await axios.post(`${getAppRoot()}api/ai_assistant/create_workflow`, {
            workflow_template: template
        })
        
        if (response.data.success && response.data.workflow_id) {
            // Navigate to workflow editor
            const editorUrl = `${getAppRoot()}workflow/editor?id=${response.data.workflow_id}`
            window.open(editorUrl, '_blank')
            
            emit('workflowCreated', {
                workflowId: response.data.workflow_id,
                template: template
            })
            
            addMessage(`Workflow "${template.name}" created successfully! Opening in editor...`, 'ai')
        }
    } catch (error) {
        console.error('Create workflow error:', error)
        addMessage('Failed to create workflow. Please try again.', 'ai')
    }
    
    isCreatingWorkflow.value = false
}

const previewWorkflow = (template) => {
    // TODO: Implement workflow preview modal
    console.log('Preview workflow:', template)
    addMessage('Workflow preview will open here...', 'ai')
}

const modifyWorkflow = (template) => {
    currentMessage.value = `I want to modify the workflow "${template.name}". `
    // Focus on input
    nextTick(() => {
        const textarea = document.querySelector('.input-area textarea')
        if (textarea) textarea.focus()
    })
}

const performSuggestedAction = (action) => {
    switch (action.id) {
        case 'preview':
            // Find the latest workflow template
            const lastMessage = messages.value.slice().reverse().find(m => m.workflowTemplates?.length)
            if (lastMessage?.workflowTemplates?.length) {
                previewWorkflow(lastMessage.workflowTemplates[0])
            }
            break
        case 'create':
            const createMessage = messages.value.slice().reverse().find(m => m.workflowTemplates?.length)
            if (createMessage?.workflowTemplates?.length) {
                createWorkflow(createMessage.workflowTemplates[0])
            }
            break
        case 'modify':
            sendMessage("I'd like to modify the workflow requirements")
            break
        default:
            console.log('Unknown action:', action)
    }
}

const clearContext = () => {
    conversationContext.currentTask = null
    conversationContext.workflowInProgress = null
    emit('contextChanged', conversationContext)
}

const formatTime = (timestamp) => {
    return new Date(timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

const scrollToBottom = () => {
    if (messagesContainer.value) {
        messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
    }
}

const checkConnection = async () => {
    try {
        const response = await axios.get(`${getAppRoot()}api/ai_assistant/status`)
        isConnected.value = response.data.ready
    } catch (error) {
        isConnected.value = false
    }
}

// Lifecycle
onMounted(() => {
    checkConnection()
    Object.assign(conversationContext, props.initialContext)
    
    // Add welcome message
    addMessage("Hi! I'm your Galaxy Workflow Assistant. I can help you create custom analysis workflows by chatting with you about your research needs. What would you like to analyze today?", 'ai')
})
</script>

<style scoped lang="scss">
.enhanced-ai-chat {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #f8f9fa;
}

.chat-header {
    background: white;
    border-bottom: 1px solid #dee2e6;
    padding: 1rem;
    
    .ai-status {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        
        .ai-title {
            font-weight: 600;
            color: #495057;
        }
        
        .connection-status {
            font-size: 0.875rem;
            color: #dc3545;
            
            &.connected {
                color: #28a745;
            }
        }
    }
    
    .context-indicator {
        margin-top: 0.5rem;
        padding: 0.5rem;
        background: #e3f2fd;
        border-radius: 0.25rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.875rem;
    }
}

.messages-container {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    
    .message-wrapper {
        margin-bottom: 1rem;
        
        &.user {
            display: flex;
            justify-content: flex-end;
            
            .message-bubble {
                background: #007bff;
                color: white;
                max-width: 70%;
            }
        }
        
        &.ai {
            display: flex;
            justify-content: flex-start;
            
            .message-bubble {
                background: white;
                border: 1px solid #dee2e6;
                max-width: 85%;
            }
        }
    }
    
    .message-bubble {
        padding: 0.75rem;
        border-radius: 1rem;
        box-shadow: 0 1px 2px rgba(0,0,0,0.1);
        
        .message-header {
            display: flex;
            justify-content: space-between;
            margin-bottom: 0.5rem;
            font-size: 0.75rem;
            opacity: 0.7;
        }
        
        .message-content {
            line-height: 1.4;
        }
    }
    
    .workflow-template-card {
        margin-top: 1rem;
        padding: 1rem;
        background: #f8f9fa;
        border-radius: 0.5rem;
        border: 1px solid #e9ecef;
        
        .template-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 0.5rem;
            
            .step-count {
                font-size: 0.875rem;
                color: #6c757d;
            }
        }
        
        .template-description {
            color: #6c757d;
            margin-bottom: 1rem;
        }
        
        .workflow-steps-preview {
            margin-bottom: 1rem;
            
            .step-preview {
                display: flex;
                align-items: center;
                gap: 0.5rem;
                font-size: 0.875rem;
                color: #495057;
                margin-bottom: 0.25rem;
            }
            
            .more-steps {
                font-size: 0.875rem;
                color: #6c757d;
                font-style: italic;
            }
        }
        
        .template-actions {
            display: flex;
            gap: 0.5rem;
            flex-wrap: wrap;
        }
    }
    
    .suggested-actions, .clarification-questions {
        margin-top: 1rem;
        
        h6 {
            margin-bottom: 0.5rem;
            color: #495057;
        }
        
        .quick-questions {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
        }
    }
}

.loading-indicator {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: #6c757d;
    font-style: italic;
    
    .typing-indicator {
        display: flex;
        gap: 2px;
        
        span {
            width: 4px;
            height: 4px;
            background: #6c757d;
            border-radius: 50%;
            animation: typing 1.4s infinite ease-in-out;
            
            &:nth-child(1) { animation-delay: -0.32s; }
            &:nth-child(2) { animation-delay: -0.16s; }
        }
    }
}

@keyframes typing {
    0%, 80%, 100% { opacity: 0.3; }
    40% { opacity: 1; }
}

.input-area {
    background: white;
    border-top: 1px solid #dee2e6;
    padding: 1rem;
    
    .input-wrapper {
        display: flex;
        gap: 0.5rem;
        align-items: flex-end;
        
        textarea {
            flex: 1;
        }
        
        .send-button {
            height: fit-content;
        }
    }
    
    .quick-suggestions {
        margin-top: 0.5rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        flex-wrap: wrap;
        
        .suggestions-label {
            font-size: 0.875rem;
            color: #6c757d;
        }
    }
}
</style>