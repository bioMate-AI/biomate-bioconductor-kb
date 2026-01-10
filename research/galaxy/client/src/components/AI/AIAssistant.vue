<template>
    <div class="ai-assistant">
        <div class="ai-header">
            <h2>
                <i class="fa fa-robot"></i>
                Galaxy AI Assistant
            </h2>
            <div class="ai-status" :class="{ 'connected': isConnected }">
                <span v-if="isConnected" class="status-indicator">●</span>
                <span v-else class="status-indicator">●</span>
                {{ isConnected ? 'Connected' : 'Disconnected' }}
            </div>
        </div>

        <div class="ai-chat-container">
            <!-- Chat Messages -->
            <div class="chat-messages" ref="chatMessages">
                <div 
                    v-for="message in messages" 
                    :key="message.id"
                    class="message"
                    :class="{ 'user': message.type === 'user', 'ai': message.type === 'ai' }"
                >
                    <div class="message-content">
                        <div class="message-header">
                            <span class="sender">{{ message.type === 'user' ? 'You' : 'AI Assistant' }}</span>
                            <span class="timestamp">{{ formatTime(message.timestamp) }}</span>
                        </div>
                        <div class="message-text">{{ message.text }}</div>
                        
                        <!-- Message Actions -->
                        <div v-if="message.actions" class="message-actions">
                            <button 
                                v-for="action in message.actions"
                                :key="action.id"
                                :class="['btn', 'btn-sm', action.primary ? 'btn-primary' : 'btn-secondary']"
                                @click="performAction(action)"
                            >
                                {{ action.label }}
                            </button>
                        </div>
                        
                        <!-- AI Response Details -->
                        <div v-if="message.type === 'ai' && message.response" class="ai-response-details">
                            
                            <!-- Intent and Confidence -->
                            <div class="response-section">
                                <h4>Detected Intent</h4>
                                <div class="intent-info">
                                    <span class="intent-badge">{{ message.response.parsed_intent }}</span>
                                    <span class="confidence">Confidence: {{ (message.response.confidence * 100).toFixed(1) }}%</span>
                                </div>
                            </div>

                            <!-- Tasks -->
                            <div v-if="message.response.decomposed_tasks.length > 0" class="response-section">
                                <h4>Analysis Steps</h4>
                                <div class="tasks-list">
                                    <div 
                                        v-for="(task, index) in message.response.decomposed_tasks" 
                                        :key="task.id"
                                        class="task-item"
                                    >
                                        <div class="task-number">{{ index + 1 }}</div>
                                        <div class="task-content">
                                            <div class="task-name">{{ task.name }}</div>
                                            <div class="task-description">{{ task.description }}</div>
                                            <div class="task-meta">
                                                <span class="task-type">{{ task.task_type }}</span>
                                                <span v-if="task.estimated_duration" class="duration">
                                                    ~{{ task.estimated_duration }}min
                                                </span>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <!-- Tool Recommendations -->
                            <div v-if="message.response.tool_recommendations.length > 0" class="response-section">
                                <h4>Recommended Tools</h4>
                                <div class="tools-list">
                                    <div 
                                        v-for="tool in message.response.tool_recommendations" 
                                        :key="tool.tool_id"
                                        class="tool-item"
                                    >
                                        <div class="tool-info">
                                            <div class="tool-name">{{ tool.tool_name }}</div>
                                            <div class="tool-reasoning">{{ tool.reasoning }}</div>
                                            <div class="tool-confidence">
                                                Confidence: {{ (tool.confidence * 100).toFixed(1) }}%
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <!-- Workflow Template -->
                            <div v-if="message.response.workflow_template" class="response-section">
                                <h4>Generated Workflow</h4>
                                <div class="workflow-info">
                                    <div class="workflow-name">{{ message.response.workflow_template.name }}</div>
                                    <div class="workflow-description">{{ message.response.workflow_template.description }}</div>
                                    <div class="workflow-steps">
                                        {{ message.response.workflow_template.steps.length }} steps
                                    </div>
                                    <div class="workflow-actions">
                                        <button 
                                            class="btn btn-primary btn-sm"
                                            @click="createWorkflow(message.response.workflow_template)"
                                        >
                                            Create Workflow
                                        </button>
                                        <button 
                                            class="btn btn-secondary btn-sm"
                                            @click="previewWorkflow(message.response.workflow_template)"
                                        >
                                            Preview
                                        </button>
                                    </div>
                                </div>
                            </div>

                            <!-- Execution Plan -->
                            <div v-if="message.response.execution_plan" class="response-section">
                                <h4>Execution Plan</h4>
                                <pre class="execution-plan">{{ message.response.execution_plan }}</pre>
                            </div>

                            <!-- Warnings -->
                            <div v-if="message.response.warnings.length > 0" class="response-section">
                                <h4>Warnings</h4>
                                <div class="warnings-list">
                                    <div 
                                        v-for="warning in message.response.warnings" 
                                        :key="warning"
                                        class="warning-item"
                                    >
                                        <i class="fa fa-exclamation-triangle"></i>
                                        {{ warning }}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Input Area -->
            <div class="chat-input-area">
                <div class="input-container">
                    <textarea
                        v-model="currentInput"
                        class="chat-input"
                        placeholder="Describe your research needs... (e.g., 'I want to analyze RNA-seq data to find differentially expressed genes')"
                        @keydown.enter.ctrl="sendMessage"
                        @keydown.enter.meta="sendMessage"
                        rows="3"
                    ></textarea>
                    <div class="input-actions">
                        <button 
                            class="btn btn-primary"
                            @click="sendMessage"
                            :disabled="!currentInput.trim() || isProcessing"
                        >
                            <i v-if="isProcessing" class="fa fa-spinner fa-spin"></i>
                            <i v-else class="fa fa-paper-plane"></i>
                            {{ isProcessing ? 'Processing...' : 'Send' }}
                        </button>
                        <button 
                            class="btn btn-secondary"
                            @click="clearChat"
                        >
                            <i class="fa fa-trash"></i>
                            Clear
                        </button>
                    </div>
                </div>
                <div class="input-hint">
                    Press Ctrl+Enter to send. Try: "Quality control and alignment of paired-end RNA-seq data"
                </div>
            </div>
        </div>

        <!-- Context Panel -->
        <div class="ai-context-panel" v-if="showContextPanel">
            <h3>Context</h3>
            
            <!-- Available Datasets -->
            <div class="context-section">
                <h4>Available Datasets</h4>
                <div v-if="availableDatasets.length === 0" class="no-data">
                    No datasets available in current history
                </div>
                <div v-else class="datasets-list">
                    <div 
                        v-for="dataset in availableDatasets" 
                        :key="dataset.id"
                        class="dataset-item"
                    >
                        <div class="dataset-name">{{ dataset.name }}</div>
                        <div class="dataset-type">{{ dataset.extension }}</div>
                    </div>
                </div>
            </div>

            <!-- Preferred Tools -->
            <div class="context-section">
                <h4>Tool Preferences</h4>
                <div class="tool-preferences">
                    <input 
                        v-model="preferredTools"
                        type="text"
                        placeholder="Preferred tools (comma-separated)"
                        class="form-control"
                    />
                </div>
            </div>

            <!-- Resource Constraints -->
            <div class="context-section">
                <h4>Resource Constraints</h4>
                <div class="resource-constraints">
                    <div class="constraint-item">
                        <label>Max Runtime (minutes):</label>
                        <input 
                            v-model.number="maxRuntime"
                            type="number"
                            class="form-control"
                            placeholder="No limit"
                        />
                    </div>
                    <div class="constraint-item">
                        <label>Priority:</label>
                        <select v-model="priority" class="form-control">
                            <option value="speed">Speed</option>
                            <option value="balanced">Balanced</option>
                            <option value="quality">Quality</option>
                        </select>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>

<script>
import { reactive, ref, computed, onMounted, nextTick } from 'vue'
import { getAppRoot } from 'onload/loadConfig'
import axios from 'axios'

export default {
    name: 'AIAssistant',
    setup() {
        // Reactive state
        const messages = ref([])
        const currentInput = ref('')
        const isProcessing = ref(false)
        const isConnected = ref(false)
        const showContextPanel = ref(true)
        const availableDatasets = ref([])
        const preferredTools = ref('')
        const maxRuntime = ref(null)
        const priority = ref('balanced')
        const chatMessages = ref(null)

        // Check AI Assistant status
        const checkStatus = async () => {
            try {
                const response = await axios.get(`${getAppRoot()}api/ai_assistant/status`)
                isConnected.value = response.data.ready
            } catch (error) {
                console.error('Failed to check AI Assistant status:', error)
                isConnected.value = false
            }
        }

        // Load available datasets from current history
        const loadAvailableDatasets = async () => {
            try {
                // This would integrate with Galaxy's history API
                // For now, mock some data
                availableDatasets.value = [
                    { id: '1', name: 'sample_R1.fastq', extension: 'fastq' },
                    { id: '2', name: 'sample_R2.fastq', extension: 'fastq' },
                    { id: '3', name: 'reference.fasta', extension: 'fasta' }
                ]
            } catch (error) {
                console.error('Failed to load datasets:', error)
            }
        }

        // Send message to AI Assistant
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
                // Prepare request data
                const requestData = {
                    request_text: requestText,
                    context: {
                        priority: priority.value,
                        max_runtime: maxRuntime.value
                    },
                    available_datasets: availableDatasets.value,
                    preferred_tools: preferredTools.value ? 
                        preferredTools.value.split(',').map(t => t.trim()) : null,
                    constraints: {
                        max_runtime_minutes: maxRuntime.value,
                        quality_priority: priority.value
                    }
                }

                const response = await axios.post(
                    `${getAppRoot()}api/ai_assistant/process_request`,
                    requestData
                )

                const aiMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: generateResponseSummary(response.data),
                    response: response.data,
                    timestamp: new Date()
                }

                messages.value.push(aiMessage)

            } catch (error) {
                console.error('Failed to process AI request:', error)
                
                const errorMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: 'Sorry, I encountered an error processing your request. Please try again.',
                    timestamp: new Date()
                }

                messages.value.push(errorMessage)
            } finally {
                isProcessing.value = false
                await nextTick()
                scrollToBottom()
            }
        }

        // Generate a summary text from AI response
        const generateResponseSummary = (response) => {
            const parts = []
            
            if (response.parsed_intent) {
                parts.push(`I understand you want to ${response.parsed_intent.toLowerCase()}.`)
            }
            
            if (response.decomposed_tasks && response.decomposed_tasks.length > 0) {
                parts.push(`I've broken this down into ${response.decomposed_tasks.length} steps.`)
            }
            
            if (response.tool_recommendations && response.tool_recommendations.length > 0) {
                parts.push(`I recommend ${response.tool_recommendations.length} tools for this analysis.`)
            }
            
            if (response.workflow_template && response.workflow_template.steps) {
                parts.push(`I've generated a complete workflow with ${response.workflow_template.steps.length} steps.`)
            }
            
            if (response.warnings && Array.isArray(response.warnings) && response.warnings.length > 0) {
                parts.push(`Please note there are ${response.warnings.length} warnings to consider.`)
            }

            return parts.length > 0 ? parts.join(' ') : 'I have processed your request successfully.'
        }

        // Clear chat history
        const clearChat = () => {
            messages.value = []
        }

        // Scroll to bottom of chat
        const scrollToBottom = () => {
            if (chatMessages.value) {
                chatMessages.value.scrollTop = chatMessages.value.scrollHeight
            }
        }

        // Format timestamp
        const formatTime = (timestamp) => {
            return new Intl.DateTimeFormat('en-US', {
                hour: '2-digit',
                minute: '2-digit'
            }).format(timestamp)
        }

        // Create workflow from template
        const createWorkflow = async (workflowTemplate) => {
            try {
                // Try the simple workflow API first (no auth required)
                const response = await axios.post(
                    `${getAppRoot()}api/ai_assistant/simple_workflow`,
                    {
                        request_text: `Create workflow: ${workflowTemplate.name}`,
                        context: { workflow_template: workflowTemplate }
                    }
                ).catch(async (error) => {
                    // If simple API fails, try the original API
                    if (error.response?.status === 404) {
                        return await axios.post(
                            `${getAppRoot()}api/ai_assistant/create_workflow`,
                            {
                                request_text: `Create workflow: ${workflowTemplate.name}`,
                                context: { workflow_template: workflowTemplate }
                            }
                        )
                    }
                    throw error
                })

                const result = response.data
                
                if (result.status === 'success' && result.workflow_id) {
                    // Show success message with action buttons
                    const successMessage = {
                        id: Date.now(),
                        type: 'ai',
                        text: `✅ Workflow "${result.workflow_name}" created successfully!`,
                        timestamp: new Date(),
                        actions: [
                            {
                                id: 'open_editor',
                                label: 'Open Workflow Editor',
                                url: result.workflow_url || `/workflow/editor?id=${result.workflow_id}`,
                                primary: true
                            },
                            {
                                id: 'view_workflows', 
                                label: 'View My Workflows',
                                url: '/workflows/list',
                                primary: false
                            }
                        ]
                    }

                    messages.value.push(successMessage)
                } else if (result.status === 'preview_success' && result.workflow_id) {
                    // Show preview message with login prompt
                    const previewMessage = {
                        id: Date.now(),
                        type: 'ai',
                        text: `${result.message}\n\n📋 Workflow Details:\n• Name: ${result.workflow_template.name}\n• Steps: ${result.workflow_template.steps}\n• Tags: ${result.workflow_template.tags.join(', ')}\n\n${result.note}`,
                        timestamp: new Date(),
                        actions: [
                            {
                                id: 'login',
                                label: '🔑 Log In to Save Workflow',
                                url: result.login_url || '/login',
                                primary: true
                            },
                            {
                                id: 'copy_template',
                                label: '📋 Copy Workflow Info',
                                data: result.workflow_template,
                                primary: false
                            }
                        ]
                    }

                    messages.value.push(previewMessage)
                } else if (result.status === 'partial_success') {
                    // Show partial success message
                    const partialMessage = {
                        id: Date.now(),
                        type: 'ai',
                        text: `⚠️ ${result.message}\n\nNote: ${result.note}`,
                        timestamp: new Date(),
                        actions: [
                            {
                                id: 'view_workflows',
                                label: 'Check My Workflows',
                                url: '/workflows/list',
                                primary: true
                            }
                        ]
                    }
                    messages.value.push(partialMessage)
                } else {
                    throw new Error(result.error || 'Unknown error creating workflow')
                }

                await nextTick()
                scrollToBottom()

            } catch (error) {
                console.error('Failed to create workflow:', error)
                
                const errorMessage = {
                    id: Date.now(),
                    type: 'ai',
                    text: '❌ Sorry, I failed to create the workflow. Please try again or check the console for details.',
                    timestamp: new Date()
                }

                messages.value.push(errorMessage)
            }
        }

        // Preview workflow
        const previewWorkflow = (workflowTemplate) => {
            // This would open a workflow preview dialog
            console.log('Preview workflow:', workflowTemplate)
        }

        // Handle action buttons
        const performAction = (action) => {
            switch (action.id) {
                case 'open_editor':
                    // Open workflow editor in new tab
                    window.open(getAppRoot() + (action.url.startsWith('/') ? action.url.substring(1) : action.url), '_blank')
                    break
                case 'view_workflows':
                    // Navigate to workflows list
                    window.open(getAppRoot() + (action.url.startsWith('/') ? action.url.substring(1) : action.url), '_blank')
                    break
                case 'login':
                    // Navigate to login page
                    window.location.href = getAppRoot() + (action.url.startsWith('/') ? action.url.substring(1) : action.url)
                    break
                case 'copy_template':
                    // Copy workflow template info to clipboard
                    const templateInfo = JSON.stringify(action.data, null, 2)
                    navigator.clipboard.writeText(templateInfo).then(() => {
                        alert('Workflow template info copied to clipboard!')
                    }).catch(() => {
                        // Fallback for older browsers
                        const textArea = document.createElement('textarea')
                        textArea.value = templateInfo
                        document.body.appendChild(textArea)
                        textArea.select()
                        document.execCommand('copy')
                        document.body.removeChild(textArea)
                        alert('Workflow template info copied to clipboard!')
                    })
                    break
                default:
                    console.log('Unknown action:', action)
            }
        }

        // Initialize component
        onMounted(() => {
            checkStatus()
            loadAvailableDatasets()
        })

        return {
            messages,
            currentInput,
            isProcessing,
            isConnected,
            showContextPanel,
            availableDatasets,
            preferredTools,
            maxRuntime,
            priority,
            chatMessages,
            sendMessage,
            clearChat,
            formatTime,
            createWorkflow,
            previewWorkflow,
            performAction
        }
    }
}
</script>

<style scoped>
.ai-assistant {
    display: flex;
    flex-direction: column;
    height: 100vh;
    background: #f8f9fa;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
}

.ai-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem;
    background: white;
    border-bottom: 1px solid #e0e0e0;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.ai-header h2 {
    margin: 0;
    color: #333;
    font-size: 1.5rem;
}

.ai-header h2 i {
    color: #007bff;
    margin-right: 0.5rem;
}

.ai-status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.9rem;
}

.status-indicator {
    font-size: 1.2rem;
    color: #dc3545;
}

.ai-status.connected .status-indicator {
    color: #28a745;
}

.ai-chat-container {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
}

.chat-messages {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.message {
    max-width: 80%;
    animation: fadeIn 0.3s ease-in;
}

.message.user {
    align-self: flex-end;
}

.message.ai {
    align-self: flex-start;
}

.message-content {
    background: white;
    border-radius: 0.5rem;
    padding: 1rem;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.message.user .message-content {
    background: #007bff;
    color: white;
}

.message-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.5rem;
    font-size: 0.8rem;
    opacity: 0.7;
}

.message-text {
    line-height: 1.5;
    margin-bottom: 1rem;
}

.ai-response-details {
    border-top: 1px solid #e0e0e0;
    padding-top: 1rem;
}

.response-section {
    margin-bottom: 1.5rem;
}

.response-section h4 {
    color: #333;
    font-size: 1rem;
    margin-bottom: 0.5rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
}

.intent-info {
    display: flex;
    align-items: center;
    gap: 1rem;
}

.intent-badge {
    background: #007bff;
    color: white;
    padding: 0.25rem 0.5rem;
    border-radius: 0.25rem;
    font-size: 0.8rem;
    text-transform: uppercase;
}

.confidence {
    font-size: 0.9rem;
    color: #666;
}

.tasks-list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
}

.task-item {
    display: flex;
    gap: 0.75rem;
    padding: 0.75rem;
    background: #f8f9fa;
    border-radius: 0.375rem;
    border-left: 3px solid #007bff;
}

.task-number {
    background: #007bff;
    color: white;
    width: 2rem;
    height: 2rem;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
    font-size: 0.9rem;
    flex-shrink: 0;
}

.task-content {
    flex: 1;
}

.task-name {
    font-weight: 600;
    color: #333;
    margin-bottom: 0.25rem;
}

.task-description {
    color: #666;
    font-size: 0.9rem;
    line-height: 1.4;
    margin-bottom: 0.5rem;
}

.task-meta {
    display: flex;
    gap: 1rem;
    font-size: 0.8rem;
}

.task-type {
    background: #e9ecef;
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
    color: #495057;
}

.duration {
    color: #6c757d;
}

.tools-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}

.tool-item {
    padding: 0.75rem;
    background: #f8f9fa;
    border-radius: 0.375rem;
    border-left: 3px solid #28a745;
}

.tool-name {
    font-weight: 600;
    color: #333;
    margin-bottom: 0.25rem;
}

.tool-reasoning {
    color: #666;
    font-size: 0.9rem;
    margin-bottom: 0.25rem;
}

.tool-confidence {
    font-size: 0.8rem;
    color: #6c757d;
}

.workflow-info {
    padding: 1rem;
    background: #f8f9fa;
    border-radius: 0.375rem;
    border-left: 3px solid #17a2b8;
}

.workflow-name {
    font-weight: 600;
    color: #333;
    margin-bottom: 0.5rem;
}

.workflow-description {
    color: #666;
    font-size: 0.9rem;
    margin-bottom: 0.5rem;
}

.workflow-steps {
    color: #6c757d;
    font-size: 0.8rem;
    margin-bottom: 1rem;
}

.workflow-actions {
    display: flex;
    gap: 0.5rem;
}

.execution-plan {
    background: #f8f9fa;
    padding: 1rem;
    border-radius: 0.375rem;
    font-family: 'Monaco', 'Consolas', monospace;
    font-size: 0.8rem;
    line-height: 1.4;
    color: #333;
    white-space: pre-wrap;
}

.warnings-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}

.warning-item {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem;
    background: #fff3cd;
    border: 1px solid #ffeaa7;
    border-radius: 0.375rem;
    color: #856404;
    font-size: 0.9rem;
}

.warning-item i {
    color: #f39c12;
}

.chat-input-area {
    padding: 1rem;
    background: white;
    border-top: 1px solid #e0e0e0;
}

.input-container {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
}

.chat-input {
    width: 100%;
    border: 1px solid #ddd;
    border-radius: 0.375rem;
    padding: 0.75rem;
    font-size: 0.9rem;
    resize: vertical;
    min-height: 3rem;
}

.chat-input:focus {
    outline: none;
    border-color: #007bff;
    box-shadow: 0 0 0 2px rgba(0, 123, 255, 0.25);
}

.input-actions {
    display: flex;
    gap: 0.5rem;
    justify-content: flex-end;
}

.input-hint {
    font-size: 0.8rem;
    color: #6c757d;
    font-style: italic;
}

.btn {
    padding: 0.5rem 1rem;
    border: none;
    border-radius: 0.375rem;
    font-size: 0.9rem;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    transition: all 0.2s;
}

.btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
}

.btn-primary {
    background: #007bff;
    color: white;
}

.btn-primary:hover:not(:disabled) {
    background: #0056b3;
}

.btn-secondary {
    background: #6c757d;
    color: white;
}

.btn-secondary:hover:not(:disabled) {
    background: #545b62;
}

.btn-sm {
    padding: 0.375rem 0.75rem;
    font-size: 0.8rem;
}

@keyframes fadeIn {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: translateY(0); }
}

/* Context Panel Styles */
.ai-context-panel {
    width: 300px;
    background: white;
    border-left: 1px solid #e0e0e0;
    padding: 1rem;
    overflow-y: auto;
}

.context-section {
    margin-bottom: 1.5rem;
}

.context-section h3,
.context-section h4 {
    color: #333;
    margin-bottom: 0.75rem;
    font-size: 1rem;
}

.datasets-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}

.dataset-item {
    padding: 0.5rem;
    background: #f8f9fa;
    border-radius: 0.25rem;
    font-size: 0.9rem;
}

.dataset-name {
    font-weight: 500;
    color: #333;
}

.dataset-type {
    color: #666;
    font-size: 0.8rem;
}

.no-data {
    color: #666;
    font-style: italic;
    text-align: center;
    padding: 1rem;
}

.form-control {
    width: 100%;
    padding: 0.5rem;
    border: 1px solid #ddd;
    border-radius: 0.25rem;
    font-size: 0.9rem;
}

.form-control:focus {
    outline: none;
    border-color: #007bff;
    box-shadow: 0 0 0 2px rgba(0, 123, 255, 0.25);
}

.constraint-item {
    margin-bottom: 0.75rem;
}

.constraint-item label {
    display: block;
    margin-bottom: 0.25rem;
    font-size: 0.9rem;
    font-weight: 500;
    color: #333;
}
</style>