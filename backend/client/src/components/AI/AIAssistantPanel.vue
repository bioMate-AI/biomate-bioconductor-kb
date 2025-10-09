<template>
    <div class="ai-assistant-panel">
        <!-- Toggle Button -->
        <button 
            class="ai-toggle-btn"
            @click="togglePanel"
            :class="{ 'active': isOpen }"
            title="Galaxy AI Assistant"
        >
            <i class="fa fa-robot"></i>
            <span v-if="hasUnreadMessages" class="notification-badge">{{ unreadCount }}</span>
        </button>

        <!-- Sliding Panel -->
        <transition name="slide">
            <div v-if="isOpen" class="ai-panel">
                <div class="ai-panel-header">
                    <h3>AI Assistant</h3>
                    <button class="close-btn" @click="togglePanel">
                        <i class="fa fa-times"></i>
                    </button>
                </div>

                <div class="ai-panel-content">
                    <!-- Quick Actions -->
                    <div class="quick-actions">
                        <h4>Quick Start</h4>
                        <div class="action-buttons">
                            <button 
                                class="action-btn"
                                @click="suggestQuickAction('rna-seq')"
                            >
                                <i class="fa fa-dna"></i>
                                RNA-seq Analysis
                            </button>
                            <button 
                                class="action-btn"
                                @click="suggestQuickAction('variant-calling')"
                            >
                                <i class="fa fa-search"></i>
                                Variant Calling
                            </button>
                            <button 
                                class="action-btn"
                                @click="suggestQuickAction('assembly')"
                            >
                                <i class="fa fa-puzzle-piece"></i>
                                Genome Assembly
                            </button>
                            <button 
                                class="action-btn"
                                @click="suggestQuickAction('quality-control')"
                            >
                                <i class="fa fa-check-circle"></i>
                                Quality Control
                            </button>
                        </div>
                    </div>

                    <!-- Chat Interface -->
                    <div class="chat-section">
                        <h4>Ask AI Assistant</h4>
                        
                        <!-- Messages -->
                        <div class="chat-messages" ref="chatContainer">
                            <div v-if="messages.length === 0" class="welcome-message">
                                <div class="welcome-icon">
                                    <i class="fa fa-robot"></i>
                                </div>
                                <p>Hello! I'm your Galaxy AI Assistant. I can help you:</p>
                                <ul>
                                    <li>Design bioinformatics workflows</li>
                                    <li>Recommend appropriate tools</li>
                                    <li>Explain analysis steps</li>
                                    <li>Optimize your pipelines</li>
                                </ul>
                                <p>Just describe what you want to analyze!</p>
                            </div>

                            <div 
                                v-for="message in messages" 
                                :key="message.id"
                                class="message"
                                :class="message.type"
                            >
                                <div class="message-content">
                                    <div class="message-text">{{ message.text }}</div>
                                    <div v-if="message.actions" class="message-actions">
                                        <button 
                                            v-for="action in message.actions"
                                            :key="action.id"
                                            class="action-btn-sm"
                                            @click="performAction(action)"
                                        >
                                            {{ action.label }}
                                        </button>
                                    </div>
                                </div>
                                <div class="message-time">
                                    {{ formatTime(message.timestamp) }}
                                </div>
                            </div>
                        </div>

                        <!-- Input -->
                        <div class="chat-input-section">
                            <div class="input-wrapper">
                                <input
                                    v-model="currentInput"
                                    type="text"
                                    placeholder="Describe your analysis needs..."
                                    @keyup.enter="sendMessage"
                                    :disabled="isProcessing"
                                    class="chat-input"
                                />
                                <button 
                                    @click="sendMessage"
                                    :disabled="!currentInput.trim() || isProcessing"
                                    class="send-btn"
                                >
                                    <i v-if="isProcessing" class="fa fa-spinner fa-spin"></i>
                                    <i v-else class="fa fa-paper-plane"></i>
                                </button>
                            </div>
                            <div class="input-hint">
                                Try: "Analyze differential gene expression from RNA-seq data"
                            </div>
                        </div>
                    </div>

                    <!-- Status -->
                    <div class="ai-status-footer">
                        <div class="status-indicator" :class="{ 'connected': isConnected }">
                            <span class="status-dot"></span>
                            {{ isConnected ? 'AI Assistant Ready' : 'Connecting...' }}
                        </div>
                        <button 
                            class="expand-btn"
                            @click="openFullInterface"
                            title="Open full AI Assistant interface"
                        >
                            <i class="fa fa-expand"></i>
                        </button>
                    </div>
                </div>
            </div>
        </transition>
    </div>
</template>

<script>
import { ref, computed, onMounted, nextTick } from 'vue'
import { getAppRoot } from 'onload/loadConfig'
import axios from 'axios'

export default {
    name: 'AIAssistantPanel',
    setup() {
        const isOpen = ref(false)
        const isConnected = ref(false)
        const isProcessing = ref(false)
        const messages = ref([])
        const currentInput = ref('')
        const chatContainer = ref(null)
        const unreadCount = ref(0)

        const hasUnreadMessages = computed(() => unreadCount.value > 0)

        // Check AI status
        const checkStatus = async () => {
            try {
                const response = await axios.get(`${getAppRoot()}api/ai_assistant/status`)
                isConnected.value = response.data.ready
            } catch (error) {
                console.error('AI Assistant status check failed:', error)
                isConnected.value = false
            }
        }

        // Toggle panel visibility
        const togglePanel = () => {
            isOpen.value = !isOpen.value
            if (isOpen.value) {
                unreadCount.value = 0
            }
        }

        // Send message to AI
        const sendMessage = async () => {
            if (!currentInput.value.trim() || isProcessing.value) return

            const userMessage = {
                id: Date.now(),
                type: 'user',
                text: currentInput.value,
                timestamp: new Date()
            }

            messages.value.push(userMessage)
            
            const requestText = currentInput.value
            currentInput.value = ''
            isProcessing.value = true

            try {
                const response = await axios.post(
                    `${getAppRoot()}api/ai_assistant/process_request`,
                    {
                        request_text: requestText,
                        context: {},
                        available_datasets: [],
                        preferred_tools: null,
                        constraints: {}
                    }
                )

                const aiResponse = response.data
                let responseText = 'I understand your request. '

                if (aiResponse.decomposed_tasks.length > 0) {
                    responseText += `I've identified ${aiResponse.decomposed_tasks.length} key steps for your analysis. `
                }

                if (aiResponse.tool_recommendations.length > 0) {
                    responseText += `I recommend ${aiResponse.tool_recommendations.length} tools that would be suitable. `
                }

                if (aiResponse.workflow_template) {
                    responseText += `I found workflow options for you. Let me show you the available choices.`
                }

                // Create action buttons based on response
                const actions = []
                
                if (aiResponse.workflow_template) {
                    actions.push({
                        id: 'show_workflow_options',
                        label: 'View Workflow Options',
                        data: aiResponse.workflow_template
                    })
                }

                if (aiResponse.tool_recommendations.length > 0) {
                    actions.push({
                        id: 'view_tools',
                        label: 'View Tools',
                        data: aiResponse.tool_recommendations
                    })
                }

                actions.push({
                    id: 'view_details',
                    label: 'View Details',
                    data: aiResponse
                })

                const aiMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: responseText,
                    actions: actions,
                    timestamp: new Date(),
                    fullResponse: aiResponse
                }

                messages.value.push(aiMessage)

                // Update unread count if panel is closed
                if (!isOpen.value) {
                    unreadCount.value++
                }

            } catch (error) {
                console.error('AI request failed:', error)
                
                const errorMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: 'Sorry, I encountered an error. Please try again or contact support.',
                    timestamp: new Date()
                }

                messages.value.push(errorMessage)
            } finally {
                isProcessing.value = false
                await nextTick()
                scrollToBottom()
            }
        }

        // Suggest quick action
        const suggestQuickAction = (actionType) => {
            const suggestions = {
                'rna-seq': 'I want to perform differential gene expression analysis on RNA-seq data',
                'variant-calling': 'I need to call variants from whole genome sequencing data',
                'assembly': 'I want to assemble a genome from long-read sequencing data',
                'quality-control': 'I need to assess the quality of my sequencing reads'
            }

            currentInput.value = suggestions[actionType] || ''
        }

        // Perform action from AI response
        const performAction = async (action) => {
            switch (action.id) {
                case 'show_workflow_options':
                    showWorkflowOptions(action.data)
                    break
                case 'create_workflow':
                    await createWorkflow(action.data)
                    break
                case 'view_tools':
                    showToolRecommendations(action.data)
                    break
                case 'view_details':
                    openFullInterface(action.data)
                    break
                case 'open_workflow_editor':
                    // Open workflow editor in new tab
                    window.open(getAppRoot() + action.data.url.substring(1), '_blank')
                    break
                case 'view_workflows':
                    // Navigate to workflows list
                    window.open(getAppRoot() + action.data.url.substring(1), '_blank')
                    break
                case 'login':
                    // Navigate to login page
                    window.location.href = getAppRoot() + action.data.url.substring(1)
                    break
            }
        }

        // Create workflow
        const createWorkflow = async (workflowData) => {
            try {
                const response = await axios.post(
                    `${getAppRoot()}api/ai_assistant/create_workflow`,
                    {
                        request_text: `Create workflow: ${workflowData.name}`,
                        context: { workflow_template: workflowData }
                    }
                )

                const result = response.data
                let messageText = ''
                let actions = []

                if (result.status === 'success') {
                    messageText = `✅ ${result.message} You can find it in Workflow menu → My Workflows.`
                    actions = [
                        {
                            id: 'open_workflow_editor',
                            label: 'Open Workflow Editor',
                            data: { url: result.workflow_url }
                        },
                        {
                            id: 'view_workflows',
                            label: 'View My Workflows',
                            data: { url: '/workflows/list' }
                        }
                    ]
                } else if (result.status === 'partial_success') {
                    messageText = `⚠️ ${result.message}\n\nError details: ${result.error}`
                } else {
                    messageText = `❌ ${result.message || result.note}`
                    if (result.error) {
                        messageText += `\n\nError: ${result.error}`
                    }
                }

                const resultMessage = {
                    id: Date.now(),
                    type: 'ai',
                    text: messageText,
                    actions: actions,
                    timestamp: new Date()
                }

                messages.value.push(resultMessage)
                await nextTick()
                scrollToBottom()

            } catch (error) {
                console.error('Workflow creation failed:', error)
                
                let errorText = 'Sorry, I couldn\'t create the workflow.'
                let actions = []
                
                if (error.response && error.response.data) {
                    if (error.response.status === 401) {
                        errorText = '🔐 You need to be logged in to create workflows. Please log in to Galaxy first.'
                        actions = [
                            {
                                id: 'login',
                                label: 'Go to Login',
                                data: { url: '/login' }
                            }
                        ]
                    } else if (error.response.data.detail) {
                        errorText += `\n\nError: ${error.response.data.detail}`
                    } else if (error.response.data.error) {
                        errorText += `\n\nError: ${error.response.data.error}`
                    }
                }
                
                const errorMessage = {
                    id: Date.now(),
                    type: 'ai',
                    text: errorText,
                    actions: actions,
                    timestamp: new Date()
                }

                messages.value.push(errorMessage)
            }
        }

        // Show workflow options
        const showWorkflowOptions = async (workflowData) => {
            try {
                // Get workflow recommendations from API
                const response = await axios.post(
                    `${getAppRoot()}api/ai_assistant/get_workflow_recommendations`,
                    {
                        request_text: `Get workflow options for: ${workflowData.name || 'analysis'}`,
                        context: { workflow_template: workflowData }
                    }
                )

                const recommendations = response.data.recommendations || []
                
                let optionsText = `I found ${recommendations.length} workflow options for you:\n\n`
                
                const actions = []
                
                recommendations.forEach((rec, index) => {
                    optionsText += `${index + 1}. **${rec.name}** (${rec.type})\n`
                    optionsText += `   - ${rec.description}\n`
                    optionsText += `   - Confidence: ${(rec.confidence * 100).toFixed(0)}%\n`
                    optionsText += `   - Status: ${rec.validation_status}\n\n`
                    
                    actions.push({
                        id: 'create_workflow',
                        label: `Use ${rec.name}`,
                        data: { 
                            ...workflowData, 
                            template_id: rec.template_id,
                            workflow_type: rec.type 
                        }
                    })
                })

                const optionsMessage = {
                    id: Date.now(),
                    type: 'ai',
                    text: optionsText,
                    actions: actions,
                    timestamp: new Date()
                }

                messages.value.push(optionsMessage)
                await nextTick()
                scrollToBottom()

            } catch (error) {
                console.error('Failed to get workflow options:', error)
                
                // Fallback to simple workflow creation
                const fallbackMessage = {
                    id: Date.now(),
                    type: 'ai',
                    text: 'I can create a basic workflow for you. Would you like to proceed?',
                    actions: [{
                        id: 'create_workflow',
                        label: 'Create Basic Workflow',
                        data: workflowData
                    }],
                    timestamp: new Date()
                }

                messages.value.push(fallbackMessage)
            }
        }

        // Show tool recommendations
        const showToolRecommendations = (tools) => {
            const toolNames = tools.map(t => t.tool_name).join(', ')
            
            const toolMessage = {
                id: Date.now(),
                type: 'ai',
                text: `Here are the recommended tools: ${toolNames}. Click "View Details" to see more information about each tool.`,
                actions: [{
                    id: 'view_details',
                    label: 'View Details',
                    data: { tool_recommendations: tools }
                }],
                timestamp: new Date()
            }

            messages.value.push(toolMessage)
        }

        // Open full AI interface
        const openFullInterface = (data = null) => {
            // This would open the full AIAssistant component
            // In a real implementation, this might be a route navigation or modal
            console.log('Opening full AI interface with data:', data)
            
            // For now, just show a message
            const message = {
                id: Date.now(),
                type: 'ai',
                text: 'Opening full AI Assistant interface... (This would navigate to the complete interface)',
                timestamp: new Date()
            }

            messages.value.push(message)
        }

        // Scroll chat to bottom
        const scrollToBottom = () => {
            if (chatContainer.value) {
                chatContainer.value.scrollTop = chatContainer.value.scrollHeight
            }
        }

        // Format time
        const formatTime = (timestamp) => {
            return new Intl.DateTimeFormat('en-US', {
                hour: '2-digit',
                minute: '2-digit'
            }).format(timestamp)
        }

        // Initialize
        onMounted(() => {
            checkStatus()
        })

        return {
            isOpen,
            isConnected,
            isProcessing,
            messages,
            currentInput,
            chatContainer,
            unreadCount,
            hasUnreadMessages,
            togglePanel,
            sendMessage,
            suggestQuickAction,
            performAction,
            createWorkflow,
            showWorkflowOptions,
            showToolRecommendations,
            openFullInterface,
            formatTime
        }
    }
}
</script>

<style scoped>
.ai-assistant-panel {
    position: fixed;
    bottom: 2rem;
    right: 2rem;
    z-index: 1000;
}

.ai-toggle-btn {
    width: 4rem;
    height: 4rem;
    border-radius: 50%;
    background: linear-gradient(135deg, #007bff, #0056b3);
    color: white;
    border: none;
    box-shadow: 0 4px 12px rgba(0, 123, 255, 0.3);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.5rem;
    transition: all 0.3s ease;
    position: relative;
}

.ai-toggle-btn:hover {
    transform: scale(1.1);
    box-shadow: 0 6px 16px rgba(0, 123, 255, 0.4);
}

.ai-toggle-btn.active {
    background: linear-gradient(135deg, #28a745, #1e7e34);
}

.notification-badge {
    position: absolute;
    top: -4px;
    right: -4px;
    background: #dc3545;
    color: white;
    border-radius: 50%;
    width: 1.5rem;
    height: 1.5rem;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.7rem;
    font-weight: bold;
}

.ai-panel {
    position: absolute;
    bottom: 5rem;
    right: 0;
    width: 400px;
    height: 600px;
    background: white;
    border-radius: 1rem;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

.ai-panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem;
    background: linear-gradient(135deg, #007bff, #0056b3);
    color: white;
}

.ai-panel-header h3 {
    margin: 0;
    font-size: 1.1rem;
}

.close-btn {
    background: none;
    border: none;
    color: white;
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0.25rem;
    border-radius: 0.25rem;
    transition: background-color 0.2s;
}

.close-btn:hover {
    background: rgba(255, 255, 255, 0.2);
}

.ai-panel-content {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

.quick-actions {
    padding: 1rem;
    border-bottom: 1px solid #e0e0e0;
}

.quick-actions h4 {
    margin: 0 0 0.75rem 0;
    font-size: 0.9rem;
    color: #333;
}

.action-buttons {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.5rem;
}

.action-btn {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.25rem;
    padding: 0.75rem 0.5rem;
    background: #f8f9fa;
    border: 1px solid #e0e0e0;
    border-radius: 0.5rem;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 0.8rem;
    text-align: center;
}

.action-btn:hover {
    background: #e9ecef;
    border-color: #007bff;
}

.action-btn i {
    font-size: 1.2rem;
    color: #007bff;
}

.chat-section {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
}

.chat-section h4 {
    margin: 0;
    padding: 1rem;
    font-size: 0.9rem;
    color: #333;
    border-bottom: 1px solid #e0e0e0;
}

.chat-messages {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.welcome-message {
    text-align: center;
    color: #666;
    padding: 1rem;
}

.welcome-icon {
    font-size: 2rem;
    color: #007bff;
    margin-bottom: 1rem;
}

.welcome-message ul {
    text-align: left;
    margin: 1rem 0;
    padding-left: 1.5rem;
}

.welcome-message li {
    margin-bottom: 0.5rem;
    font-size: 0.9rem;
}

.message {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    max-width: 80%;
    animation: fadeInUp 0.3s ease;
}

.message.user {
    align-self: flex-end;
}

.message.ai {
    align-self: flex-start;
}

.message-content {
    background: #f8f9fa;
    padding: 0.75rem;
    border-radius: 1rem;
    font-size: 0.9rem;
    line-height: 1.4;
}

.message.user .message-content {
    background: #007bff;
    color: white;
}

.message-text {
    margin-bottom: 0.5rem;
}

.message-actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.5rem;
}

.action-btn-sm {
    padding: 0.25rem 0.5rem;
    background: rgba(0, 123, 255, 0.1);
    border: 1px solid #007bff;
    border-radius: 0.25rem;
    color: #007bff;
    font-size: 0.8rem;
    cursor: pointer;
    transition: all 0.2s;
}

.action-btn-sm:hover {
    background: #007bff;
    color: white;
}

.message.user .action-btn-sm {
    background: rgba(255, 255, 255, 0.2);
    border-color: white;
    color: white;
}

.message.user .action-btn-sm:hover {
    background: white;
    color: #007bff;
}

.message-time {
    font-size: 0.7rem;
    color: #999;
    align-self: flex-end;
}

.message.user .message-time {
    align-self: flex-start;
}

.chat-input-section {
    padding: 1rem;
    border-top: 1px solid #e0e0e0;
}

.input-wrapper {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
}

.chat-input {
    flex: 1;
    border: 1px solid #ddd;
    border-radius: 1.5rem;
    padding: 0.75rem 1rem;
    font-size: 0.9rem;
    outline: none;
}

.chat-input:focus {
    border-color: #007bff;
}

.send-btn {
    width: 3rem;
    height: 3rem;
    border-radius: 50%;
    background: #007bff;
    color: white;
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.2s;
}

.send-btn:hover:not(:disabled) {
    background: #0056b3;
    transform: scale(1.05);
}

.send-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
}

.input-hint {
    font-size: 0.75rem;
    color: #999;
    font-style: italic;
    text-align: center;
}

.ai-status-footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.75rem 1rem;
    background: #f8f9fa;
    border-top: 1px solid #e0e0e0;
}

.status-indicator {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.8rem;
    color: #666;
}

.status-dot {
    width: 0.5rem;
    height: 0.5rem;
    border-radius: 50%;
    background: #dc3545;
    transition: background-color 0.3s;
}

.status-indicator.connected .status-dot {
    background: #28a745;
}

.expand-btn {
    background: none;
    border: none;
    color: #666;
    cursor: pointer;
    padding: 0.25rem;
    border-radius: 0.25rem;
    transition: all 0.2s;
}

.expand-btn:hover {
    background: #e9ecef;
    color: #007bff;
}

/* Animations */
.slide-enter-active, .slide-leave-active {
    transition: all 0.3s ease;
}

.slide-enter-from {
    opacity: 0;
    transform: translateY(20px) scale(0.95);
}

.slide-leave-to {
    opacity: 0;
    transform: translateY(20px) scale(0.95);
}

@keyframes fadeInUp {
    from {
        opacity: 0;
        transform: translateY(10px);
    }
    to {
        opacity: 1;
        transform: translateY(0);
    }
}

/* Responsive adjustments */
@media (max-width: 768px) {
    .ai-panel {
        width: 100vw;
        height: 100vh;
        bottom: 0;
        right: 0;
        border-radius: 0;
    }
    
    .ai-assistant-panel {
        bottom: 1rem;
        right: 1rem;
    }
    
    .action-buttons {
        grid-template-columns: 1fr;
    }
}
</style>