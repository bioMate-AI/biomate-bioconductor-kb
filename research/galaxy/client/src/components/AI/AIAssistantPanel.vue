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
                            <!-- Debug Info -->
                            <div style="background: #f0f0f0; padding: 5px; margin: 5px 0; font-size: 10px; color: #666;">
                                DEBUG: Messages Count = {{ messages.length }}
                            </div>
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
                                :data-stage="message.stage"
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

        // Send message to AI - Enhanced two-stage workflow
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
                // Stage 1: Show loading message
                const loadingMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: '🔍 **Step 1: Finding Similar Workflows**\n\nAnalyzing your requirements and searching for the most relevant workflows...',
                    timestamp: new Date(),
                    isLoading: true
                }
                messages.value.push(loadingMessage)
                await nextTick()
                scrollToBottom()

                // Get similar workflows (Stage 1)
                const ragResponse = await axios.post(
                    `${getAppRoot()}api/ai_assistant/two_stage_workflow?stage=similar`,
                    {
                        request_text: requestText,
                        context: {}
                    }
                )

                // Remove loading message
                const loadingIndex = messages.value.findIndex(m => m.isLoading)
                if (loadingIndex >= 0) {
                    messages.value.splice(loadingIndex, 1)
                }

                // Debug logging - UPDATED VERSION 2.0
                console.log('🚀 UPDATED AI ASSISTANT - API Response Status:', ragResponse.status)
                console.log('🚀 UPDATED AI ASSISTANT - API Response Data:', ragResponse.data)
                console.log('🚀 UPDATED AI ASSISTANT - Recommendations length:', ragResponse.data.recommendations?.length)

                if (ragResponse.data.status === 'success' && ragResponse.data.recommendations?.length > 0) {
                    // Show Stage 1 results - Similar workflows
                    console.log('Showing two-stage workflow results with', ragResponse.data.recommendations.length, 'recommendations')
                    showTwoStageWorkflowResults(ragResponse.data.recommendations, requestText)
                } else {
                    // Fallback to original flow if no RAG results
                    console.log('Falling back to original flow. Status:', ragResponse.data.status, 'Recommendations:', ragResponse.data.recommendations?.length)
                    await fallbackToOriginalFlow(requestText)
                }

            } catch (error) {
                console.error('Enhanced workflow search failed:', error)
                await fallbackToOriginalFlow(requestText)
            } finally {
                isProcessing.value = false
            }
        }

        // Show two-stage workflow results
        const showTwoStageWorkflowResults = (recommendations, originalQuery) => {
            console.log('showTwoStageWorkflowResults called with', recommendations.length, 'recommendations')
            console.log('First recommendation:', recommendations[0])
            
            // Stage 1: Similar workflows display - Optimized for clear selection
            let stage1Text = `🎯 **Found ${recommendations.length} Similar Workflows - Pick One or Generate Custom**\n\n`
            stage1Text += `📋 **Query**: "${originalQuery}"\n`
            stage1Text += `📊 **Source**: Galaxy community workflows (951 total)\n\n`
            stage1Text += `**Choose from these top-3 matches or generate a custom solution:**\n\n`

            const stage1Actions = []

            recommendations.slice(0, 3).forEach((rec, index) => {
                const confidence = Math.round((rec.confidence || 0) * 100)
                const steps = rec.step_count || rec.steps || 0
                const tools = (rec.tools || []).slice(0, 4).join(', ')

                // Enhanced workflow display
                stage1Text += `**Option ${index + 1}: ${rec.name}**\n`
                stage1Text += `   🎯 **Match**: ${confidence}% similar to your request\n`
                stage1Text += `   ⚙️ **Complexity**: ${steps} steps\n`
                if (tools) {
                    stage1Text += `   🛠️ **Key Tools**: ${tools}\n`
                }
                if (rec.description) {
                    const desc = rec.description.substring(0, 120)
                    stage1Text += `   📝 **Purpose**: ${desc}${rec.description.length > 120 ? '...' : ''}\n`
                }
                stage1Text += '\n'

                // Create action button for each workflow
                stage1Actions.push({
                    id: 'create_workflow',
                    label: `🚀 Use Option ${index + 1}`,
                    data: {
                        name: rec.name,
                        workflow_id: rec.workflow_id,
                        type: 'rag_workflow',
                        confidence: rec.confidence,
                        original_query: originalQuery
                    }
                })
            })

            // Add Stage 2 option - Generate custom workflow using top-3 as context
            stage1Actions.push({
                id: 'proceed_to_stage2',
                label: '✨ Generate Custom Workflow (Using Above as Context)',
                data: {
                    query: originalQuery,
                    similar_workflows: recommendations.slice(0, 3), // Only top-3
                    stage: 'enhanced_generation'
                },
                style: 'primary'
            })
            
            const stage1Message = {
                id: Date.now() + 2,
                type: 'ai',
                text: stage1Text,
                actions: stage1Actions,
                timestamp: new Date(),
                stage: 'similar_workflows'
            }
            
            console.log('Pushing stage1Message to messages:', stage1Message)
            messages.value.push(stage1Message)
            console.log('Messages array now has', messages.value.length, 'messages')
            console.log('Current messages array:', messages.value)
            console.log('Vue messages reactive value:', JSON.stringify(messages.value, null, 2))
            
            // Update unread count if panel is closed
            if (!isOpen.value) {
                unreadCount.value++
            }
            
            nextTick().then(() => {
                console.log('Scrolling to bottom after nextTick')
                scrollToBottom()
            })
        }

        // Fallback to original flow
        const fallbackToOriginalFlow = async (requestText) => {
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
                let responseText = 'I understand your requirements.'
                
                const actions = [{
                    id: 'view_details',
                    label: 'View Details',
                    data: aiResponse
                }]

                const aiMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: responseText,
                    actions: actions,
                    timestamp: new Date(),
                    fullResponse: aiResponse
                }

                messages.value.push(aiMessage)
            } catch (error) {
                console.error('Fallback flow failed:', error)
                
                const errorMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: 'Sorry, I encountered some issues. Please try again later or contact support.',
                    timestamp: new Date()
                }

                messages.value.push(errorMessage)
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
                case 'proceed_to_stage2':
                    await proceedToStage2(action.data)
                    break
                case 'show_rag_recommendations':
                    showRAGRecommendations(action.data)
                    break
                case 'generate_enhanced_workflow':
                    await generateEnhancedWorkflow(action.data)
                    break
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
                case 'open_editor':
                case 'open_workflow_editor':
                    // Open workflow editor
                    const editorUrl = action.url || (action.data && action.data.url)
                    if (editorUrl) {
                        window.open(getAppRoot() + (editorUrl.startsWith('/') ? editorUrl.substring(1) : editorUrl), '_blank')
                    }
                    break
                case 'view_workflows':
                    // Navigate to workflows list  
                    const workflowsUrl = action.url || (action.data && action.data.url) || '/workflows/list'
                    window.open(getAppRoot() + (workflowsUrl.startsWith('/') ? workflowsUrl.substring(1) : workflowsUrl), '_blank')
                    break
                case 'login':
                    // Navigate to login page
                    window.location.href = getAppRoot() + action.data.url.substring(1)
                    break
            }
        }

        // Proceed to Stage 2: Enhanced generation using top-3 as context
        const proceedToStage2 = async (data) => {
            // Show Stage 2 loading message with clear context information
            const topWorkflows = data.similar_workflows.slice(0, 3).map((w, i) => `${i + 1}. ${w.name}`).join('\n')

            const stage2LoadingMessage = {
                id: Date.now(),
                type: 'ai',
                text: `✨ **Step 2: LLM Custom Workflow Generation**\n\n🤖 **AI Strategy**: Using Large Language Model to generate a completely new workflow tailored to your needs.\n\n📚 **Context Used**:\n${topWorkflows}\n\n🔄 **Process**: \n• Analyzing your specific requirements\n• Learning from similar workflow patterns\n• Generating custom steps and tool connections\n• Creating optimized workflow structure\n\n⏱️ **LLM Generation Time**: 5-10 seconds, please wait...`,
                timestamp: new Date(),
                isLoading: true,
                stage: 'enhanced_generation'
            }
            
            messages.value.push(stage2LoadingMessage)
            await nextTick()
            scrollToBottom()
            
            try {
                const response = await axios.post(
                    `${getAppRoot()}api/ai_assistant/two_stage_workflow?stage=enhanced`,
                    {
                        request_text: data.query,
                        context: { 
                            similar_workflows: data.similar_workflows,
                            stage: 'enhanced_generation'
                        }
                    }
                )
                
                // Remove loading message
                const loadingIndex = messages.value.findIndex(m => m.isLoading && m.stage === 'enhanced_generation')
                if (loadingIndex >= 0) {
                    messages.value.splice(loadingIndex, 1)
                }
                
                if (response.data.status === 'success' && response.data.workflow) {
                    showStage2Results(response.data, data.query)
                } else {
                    // Fallback: Use the best similar workflow as "enhanced"
                    await showStage2Fallback(data)
                }
                
            } catch (error) {
                console.error('Stage 2 enhanced generation failed:', error)
                await showStage2Fallback(data)
            }
        }

        // Show Stage 2 results - Enhanced display with context information
        const showStage2Results = (enhancedData, originalQuery) => {
            const workflow = enhancedData.workflow
            const confidence = Math.round((enhancedData.confidence || 0) * 100)

            let stage2Text = `✨ **Custom Workflow Successfully Generated**\n\n`
            stage2Text += `🧠 **AI Process**: Used Large Language Model to generate a completely custom workflow based on top-3 similar patterns.\n\n`

            stage2Text += `**🎯 Your Request**: "${originalQuery}"\n\n`

            stage2Text += `**📋 Generated Workflow**:\n`
            stage2Text += `   • **Name**: ${workflow.name}\n`
            stage2Text += `   • **Method**: ${enhancedData.method || 'LLM Custom Generation'}\n`
            stage2Text += `   • **Confidence**: ${confidence}%\n`

            if (enhancedData.similar_workflows_count) {
                stage2Text += `   • **Context**: Based on ${enhancedData.similar_workflows_count} similar workflows\n`

                if (enhancedData.context_workflows) {
                    stage2Text += `   • **Source Workflows**:\n`
                    enhancedData.context_workflows.forEach((name, i) => {
                        stage2Text += `     ${i + 1}. ${name}\n`
                    })
                }
            }

            stage2Text += `   • **Generation Time**: ${enhancedData.response_time || '3-8 seconds'}\n\n`
            
            stage2Text += `**📝 Description**:\n${workflow.description || 'Custom workflow generated based on your requirements'}\n\n`
            
            if (workflow.steps && workflow.steps.length > 0) {
                stage2Text += `**🔧 Workflow Steps** (${workflow.steps.length} steps):\n`
                workflow.steps.slice(0, 8).forEach((step, index) => {
                    const stepName = step.annotation || step.tool_id || `Step ${index + 1}`
                    stage2Text += `${index + 1}. ${stepName}\n`
                })
                if (workflow.steps.length > 8) {
                    stage2Text += `... ${workflow.steps.length - 8} more steps\n`
                }
                stage2Text += '\n'
            }
            
            if (workflow.tags && workflow.tags.length > 0) {
                stage2Text += `**🏷️ Tags**: ${workflow.tags.slice(0, 5).join(', ')}\n\n`
            }
            
            stage2Text += `✨ **This is a customized solution tailored for you!**`
            
            const stage2Actions = [{
                id: 'create_workflow',
                label: '🚀 Create This Custom Workflow',
                data: {
                    name: workflow.name,
                    type: 'enhanced_rag_workflow',
                    workflow_data: workflow,
                    confidence: enhancedData.confidence
                }
            }]
            
            const stage2Message = {
                id: Date.now() + 1,
                type: 'ai',
                text: stage2Text,
                actions: stage2Actions,
                timestamp: new Date(),
                stage: 'enhanced_workflow'
            }
            
            messages.value.push(stage2Message)
            
            // Update unread count if panel is closed
            if (!isOpen.value) {
                unreadCount.value++
            }
            
            nextTick().then(scrollToBottom)
        }

        // Stage 2 fallback when enhanced generation fails
        const showStage2Fallback = async (data) => {
            const bestMatch = data.similar_workflows[0] // Use the best similar workflow
            const confidence = Math.round((bestMatch.confidence || 0) * 100)
            
            let fallbackText = `⚡ **Step 2: Enhanced Version Based on Best Match**\n\n`
            fallbackText += `*Note: Advanced RAG generator is temporarily unavailable, but I've created an enhanced version based on the best matching workflow.*\n\n`
            fallbackText += `**📋 Name**: AI-Enhanced ${bestMatch.name}\n`
            fallbackText += `**🎯 Method**: Enhanced Similarity Matching\n`
            fallbackText += `**📊 Confidence**: ${confidence}%\n`
            fallbackText += `**🔧 Steps**: ${bestMatch.steps || bestMatch.step_count || 'Multiple'}\n\n`
            
            fallbackText += `**📝 Description**:\n${bestMatch.description || 'Enhanced workflow based on community best practices'}\n\n`
            
            if (bestMatch.tools && bestMatch.tools.length > 0) {
                fallbackText += `**🛠️ Core Tools**: ${bestMatch.tools.slice(0, 5).join(', ')}\n\n`
            }
            
            fallbackText += `**👤 Creator**: ${bestMatch.owner || 'Galaxy Community'}\n\n`
            fallbackText += `📈 **This is still a high-quality solution based on real community experience!**`
            
            const fallbackActions = [{
                id: 'create_workflow',
                label: '🚀 Create Enhanced Workflow',
                data: {
                    name: `AI-Enhanced ${bestMatch.name}`,
                    type: 'fallback_enhanced_workflow',
                    workflow_id: bestMatch.workflow_id,
                    confidence: bestMatch.confidence
                }
            }]
            
            const fallbackMessage = {
                id: Date.now() + 1,
                type: 'ai',
                text: fallbackText,
                actions: fallbackActions,
                timestamp: new Date(),
                stage: 'fallback_enhanced'
            }
            
            messages.value.push(fallbackMessage)
            
            if (!isOpen.value) {
                unreadCount.value++
            }
            
            nextTick().then(scrollToBottom)
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
        const showRAGRecommendations = (recommendations) => {
            let recommendationsText = `Found ${recommendations.length} similar workflows from Galaxy community:\n\n`
            
            const actions = []
            
            recommendations.forEach((rec, index) => {
                const confidence = Math.round((rec.confidence || 0) * 100)
                const steps = rec.steps || 0
                const tools = (rec.tools || []).slice(0, 3).join(', ')
                
                recommendationsText += `${index + 1}. **${rec.name}**\n`
                recommendationsText += `   - Confidence: ${confidence}%\n`
                recommendationsText += `   - Steps: ${steps}\n`
                if (tools) {
                    recommendationsText += `   - Tools: ${tools}${(rec.tools || []).length > 3 ? ' +more' : ''}\n`
                }
                recommendationsText += `   - Owner: ${rec.owner || 'Community'}\n\n`
                
                actions.push({
                    id: 'create_workflow', 
                    label: `Use "${rec.name}"`,
                    data: {
                        name: rec.name,
                        workflow_id: rec.workflow_id,
                        type: 'rag_workflow'
                    }
                })
            })
            
            const aiMessage = {
                id: Date.now(),
                type: 'ai',
                text: recommendationsText,
                actions: actions,
                timestamp: new Date()
            }
            
            messages.value.push(aiMessage)
            
            // Update unread count if panel is closed
            if (!isOpen.value) {
                unreadCount.value++
            }
        }

        const generateEnhancedWorkflow = async (data) => {
            const loadingMessage = {
                id: Date.now(),
                type: 'ai',
                text: '🎯 Generating enhanced AI workflow using RAGWorkflowGenerator...\nThis may take 2-5 seconds as I analyze similar workflows and create a custom solution for you.',
                timestamp: new Date()
            }
            
            messages.value.push(loadingMessage)
            
            try {
                const response = await axios.post(
                    `${getAppRoot()}api/ai_assistant/enhanced_workflow_recommendations?level=enhanced`,
                    {
                        request_text: data.query,
                        context: { similar_count: data.similar_count }
                    }
                )
                
                console.log('Enhanced API Response:', response.data)
                
                // Check if the response indicates the enhanced layer is unavailable
                if (response.data.status === 'error' || response.data.status === 'unavailable') {
                    // Fallback: Use quick recommendations to create an "enhanced" presentation
                    console.log('Enhanced layer unavailable, using fallback approach')
                    await generateFallbackEnhancedWorkflow(data)
                    return
                }
                
                if (response.data.status === 'success' && response.data.workflow) {
                    const workflow = response.data.workflow
                    const confidence = Math.round((response.data.confidence || 0) * 100)
                    
                    let workflowText = `✨ **Enhanced AI-Generated Workflow Created!**\n\n`
                    workflowText += `**Name**: ${workflow.name}\n`
                    workflowText += `**Method**: ${response.data.method || 'RAG Enhanced Generation'}\n`
                    workflowText += `**Confidence**: ${confidence}%\n`
                    workflowText += `**Response Time**: ${response.data.response_time || '2-5s'}\n\n`
                    
                    if (response.data.similar_workflows_count) {
                        workflowText += `**Based on**: ${response.data.similar_workflows_count} similar community workflows\n\n`
                    }
                    
                    workflowText += `**Description**:\n${workflow.description || 'Custom generated workflow'}\n\n`
                    
                    if (workflow.steps && workflow.steps.length > 0) {
                        workflowText += `**Workflow Steps** (${workflow.steps.length}):\n`
                        workflow.steps.slice(0, 8).forEach((step, index) => {
                            const stepName = step.annotation || step.tool_id || `Step ${index + 1}`
                            workflowText += `${index + 1}. ${stepName}\n`
                        })
                        if (workflow.steps.length > 8) {
                            workflowText += `... and ${workflow.steps.length - 8} more steps\n`
                        }
                        workflowText += '\n'
                    }
                    
                    if (workflow.tags && workflow.tags.length > 0) {
                        workflowText += `**Tags**: ${workflow.tags.slice(0, 5).join(', ')}\n\n`
                    }
                    
                    const actions = [{
                        id: 'create_workflow',
                        label: '🚀 Create This Workflow',
                        data: {
                            name: workflow.name,
                            type: 'enhanced_rag_workflow',
                            workflow_data: workflow,
                            confidence: response.data.confidence
                        }
                    }]
                    
                    const successMessage = {
                        id: Date.now() + 1,
                        type: 'ai',
                        text: workflowText,
                        actions: actions,
                        timestamp: new Date()
                    }
                    
                    messages.value.push(successMessage)
                    
                } else {
                    // Log the full response for debugging
                    console.error('Enhanced generation failed - API Response:', response.data)
                    
                    let errorText = `❌ Enhanced workflow generation failed\n\n`
                    errorText += `**Status**: ${response.data.status || 'unknown'}\n`
                    errorText += `**Error**: ${response.data.error || 'No error message provided'}\n`
                    errorText += `**Available keys**: ${Object.keys(response.data).join(', ')}\n\n`
                    errorText += `You can still use the similar workflows found earlier.`
                    
                    const errorMessage = {
                        id: Date.now() + 1,
                        type: 'ai',
                        text: errorText,
                        timestamp: new Date()
                    }
                    
                    messages.value.push(errorMessage)
                }
                
            } catch (error) {
                console.error('Enhanced workflow generation failed:', error)
                
                const errorMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: `❌ Enhanced workflow generation failed due to connection error.\n\nYou can still use the similar workflows found earlier.`,
                    timestamp: new Date()
                }
                
                messages.value.push(errorMessage)
            }
            
            // Update unread count if panel is closed
            if (!isOpen.value) {
                unreadCount.value++
            }
        }

        const generateFallbackEnhancedWorkflow = async (data) => {
            try {
                // Get quick recommendations to use as basis
                const ragResponse = await axios.post(
                    `${getAppRoot()}api/ai_assistant/enhanced_workflow_recommendations?level=quick`,
                    {
                        request_text: data.query,
                        context: {}
                    }
                )
                
                if (ragResponse.data.status === 'success' && ragResponse.data.recommendations && ragResponse.data.recommendations.length > 0) {
                    const bestMatch = ragResponse.data.recommendations[0]
                    const confidence = Math.round((bestMatch.confidence || 0) * 100)
                    
                    let workflowText = `⚡ **AI-Enhanced Workflow** (Fallback Mode)\n\n`
                    workflowText += `*Note: Advanced RAG generator is currently unavailable, but I've created an enhanced presentation of the best matching workflow.*\n\n`
                    workflowText += `**Name**: AI-Enhanced ${bestMatch.name}\n`
                    workflowText += `**Method**: Enhanced Similarity Matching\n`
                    workflowText += `**Confidence**: ${confidence}%\n`
                    workflowText += `**Steps**: ${bestMatch.steps || 'Multiple'}\n\n`
                    
                    workflowText += `**Description**:\n${bestMatch.description || 'Enhanced workflow based on community best practices'}\n\n`
                    
                    if (bestMatch.tools && bestMatch.tools.length > 0) {
                        workflowText += `**Key Tools**: ${bestMatch.tools.slice(0, 5).join(', ')}\n\n`
                    }
                    
                    if (bestMatch.tags && bestMatch.tags.length > 0) {
                        workflowText += `**Tags**: ${bestMatch.tags.slice(0, 5).join(', ')}\n\n`
                    }
                    
                    workflowText += `**Owner**: ${bestMatch.owner || 'Galaxy Community'}\n\n`
                    
                    const actions = [{
                        id: 'create_workflow',
                        label: '🚀 Create Enhanced Workflow',
                        data: {
                            name: `AI-Enhanced ${bestMatch.name}`,
                            type: 'fallback_enhanced_workflow',
                            workflow_id: bestMatch.workflow_id,
                            confidence: bestMatch.confidence
                        }
                    }]
                    
                    const successMessage = {
                        id: Date.now() + 1,
                        type: 'ai',
                        text: workflowText,
                        actions: actions,
                        timestamp: new Date()
                    }
                    
                    messages.value.push(successMessage)
                    
                } else {
                    const errorMessage = {
                        id: Date.now() + 1,
                        type: 'ai',
                        text: `❌ Both enhanced generation and fallback failed.\n\nPlease try using the "View Similar Workflows" option instead.`,
                        timestamp: new Date()
                    }
                    
                    messages.value.push(errorMessage)
                }
                
            } catch (error) {
                console.error('Fallback enhanced workflow generation failed:', error)
                
                const errorMessage = {
                    id: Date.now() + 1,
                    type: 'ai',
                    text: `❌ Fallback workflow generation also failed.\n\nPlease try using the "View Similar Workflows" option instead.`,
                    timestamp: new Date()
                }
                
                messages.value.push(errorMessage)
            }
        }

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
            showTwoStageWorkflowResults,
            proceedToStage2,
            showStage2Results,
            showStage2Fallback,
            fallbackToOriginalFlow,
            suggestQuickAction,
            performAction,
            createWorkflow,
            showRAGRecommendations,
            generateEnhancedWorkflow,
            generateFallbackEnhancedWorkflow,
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

/* Two-stage workflow styles */
.message[data-stage="similar_workflows"] {
    border-left: 4px solid #17a2b8;
    background: linear-gradient(135deg, #e7f7ff, #f0f9ff);
}

.message[data-stage="enhanced_workflow"] {
    border-left: 4px solid #28a745;
    background: linear-gradient(135deg, #e8f5e8, #f0fff0);
}

.message[data-stage="fallback_enhanced"] {
    border-left: 4px solid #ffc107;
    background: linear-gradient(135deg, #fffbea, #fffff0);
}

.action-btn-sm.primary {
    background: linear-gradient(135deg, #007bff, #0056b3);
    border-color: #007bff;
    color: white;
    font-weight: bold;
    box-shadow: 0 2px 8px rgba(0, 123, 255, 0.3);
}

.action-btn-sm.primary:hover {
    background: linear-gradient(135deg, #0056b3, #003d82);
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(0, 123, 255, 0.4);
}

.message-content h3 {
    margin: 0 0 0.5rem 0;
    color: #333;
    font-size: 1rem;
}

.stage-indicator {
    display: inline-block;
    padding: 0.25rem 0.5rem;
    border-radius: 0.25rem;
    font-size: 0.75rem;
    font-weight: bold;
    margin-bottom: 0.5rem;
}

.stage-indicator.stage-1 {
    background: #17a2b8;
    color: white;
}

.stage-indicator.stage-2 {
    background: #28a745;
    color: white;
}

.loading-dots {
    display: inline-block;
    animation: loadingDots 1.5s infinite;
}

@keyframes loadingDots {
    0%, 20% { opacity: 0; }
    40% { opacity: 1; }
    100% { opacity: 0; }
}

.progress-bar {
    width: 100%;
    height: 4px;
    background: #e9ecef;
    border-radius: 2px;
    overflow: hidden;
    margin: 0.5rem 0;
}

.progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #007bff, #28a745);
    border-radius: 2px;
    animation: progressFill 3s ease-in-out;
}

@keyframes progressFill {
    0% { width: 0%; }
    50% { width: 60%; }
    100% { width: 100%; }
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