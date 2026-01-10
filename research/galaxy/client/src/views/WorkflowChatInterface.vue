<!--
Workflow Chat Interface - Main View for Conversational Workflow Creation

⚠️ **NEW FILE** - This is a completely new Vue view component that provides the main
interface for conversational workflow creation. It does not modify any existing views.

Safe to add - does not modify existing functionality.
-->
<template>
    <div class="workflow-chat-interface">
        <!-- 顶部导航 -->
        <div class="interface-header">
            <h2>
                <i class="fa fa-comments"></i>
                Conversational Workflow Creator
            </h2>
            <div class="header-actions">
                <b-button 
                    variant="outline-primary" 
                    size="sm"
                    @click="showTemplateLibrary = true"
                >
                    <i class="fa fa-book"></i>
                    Template Library
                </b-button>
                <b-button 
                    variant="outline-secondary" 
                    size="sm"
                    @click="resetSession"
                >
                    <i class="fa fa-refresh"></i>
                    New Session
                </b-button>
            </div>
        </div>

        <!-- 主内容区域 -->
        <div class="interface-body">
            <!-- 左侧：AI聊天面板 -->
            <div class="chat-panel">
                <EnhancedAIChat 
                    @workflowCreated="handleWorkflowCreated"
                    @workflowGenerated="handleWorkflowGenerated"
                    @contextChanged="handleContextChange"
                />
            </div>

            <!-- 右侧：工作流预览/编辑面板 -->
            <div class="workflow-panel" v-if="currentWorkflow">
                <div class="panel-header">
                    <h4>{{ currentWorkflow.name || 'Generated Workflow' }}</h4>
                    <div class="panel-actions">
                        <b-button 
                            variant="primary" 
                            size="sm"
                            @click="openInEditor"
                        >
                            <i class="fa fa-external-link"></i>
                            Open in Editor
                        </b-button>
                        <b-button 
                            variant="outline-secondary" 
                            size="sm"
                            @click="downloadWorkflow"
                        >
                            <i class="fa fa-download"></i>
                            Download
                        </b-button>
                    </div>
                </div>

                <!-- 工作流可视化 -->
                <div class="workflow-visualization">
                    <WorkflowPreview 
                        :workflow="currentWorkflow"
                        :interactive="true"
                        @stepClick="handleStepClick"
                        @connectionClick="handleConnectionClick"
                    />
                </div>

                <!-- 步骤详情 -->
                <div class="step-details" v-if="selectedStep">
                    <h5>Step Details: {{ selectedStep.name }}</h5>
                    <div class="step-info">
                        <div class="info-row">
                            <label>Tool:</label>
                            <span>{{ selectedStep.tool_id }}</span>
                        </div>
                        <div class="info-row">
                            <label>Description:</label>
                            <span>{{ selectedStep.description }}</span>
                        </div>
                        <!-- 参数编辑 -->
                        <div class="parameters-section">
                            <h6>Parameters</h6>
                            <div 
                                v-for="(value, param) in selectedStep.parameters"
                                :key="param"
                                class="parameter-row"
                            >
                                <label>{{ param }}:</label>
                                <b-form-input 
                                    v-model="selectedStep.parameters[param]"
                                    size="sm"
                                    @change="updateStepParameter(param, $event)"
                                />
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- 空状态 -->
            <div class="empty-state" v-else>
                <div class="empty-content">
                    <i class="fa fa-sitemap fa-3x"></i>
                    <h3>Start Creating Your Workflow</h3>
                    <p>
                        Describe your analysis needs in the chat, and I'll help you 
                        create a custom workflow. Your workflow will appear here 
                        for preview and editing.
                    </p>
                    <div class="example-prompts">
                        <h5>Try these examples:</h5>
                        <div class="prompt-buttons">
                            <b-button 
                                v-for="example in examplePrompts"
                                :key="example"
                                variant="outline-primary"
                                size="sm"
                                class="mb-2 mr-2"
                                @click="sendExamplePrompt(example)"
                            >
                                {{ example }}
                            </b-button>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- 底部状态栏 -->
        <div class="interface-footer">
            <div class="status-info">
                <span v-if="conversationContext.currentTask" class="current-task">
                    <i class="fa fa-cog fa-spin"></i>
                    {{ getTaskDescription() }}
                </span>
                <span v-else class="ready-status">
                    <i class="fa fa-check-circle"></i>
                    Ready to help you create workflows
                </span>
            </div>
            
            <div class="quick-actions">
                <b-button 
                    variant="link" 
                    size="sm"
                    @click="showHelp = true"
                >
                    <i class="fa fa-question-circle"></i>
                    Help
                </b-button>
                <b-button 
                    variant="link" 
                    size="sm"
                    @click="showSettings = true"
                >
                    <i class="fa fa-cog"></i>
                    Settings
                </b-button>
            </div>
        </div>

        <!-- 模态框 -->
        <TemplateLibraryModal v-model="showTemplateLibrary" />
        <HelpModal v-model="showHelp" />
        <SettingsModal v-model="showSettings" />
    </div>
</template>

<script setup>
import { ref, reactive, computed } from 'vue'
import { useRouter } from 'vue-router'
import EnhancedAIChat from '@/components/AI/EnhancedAIChat.vue'
import WorkflowPreview from '@/components/Workflow/WorkflowPreview.vue'

// 响应式数据
const router = useRouter()
const currentWorkflow = ref(null)
const selectedStep = ref(null)
const showTemplateLibrary = ref(false)
const showHelp = ref(false)
const showSettings = ref(false)

const conversationContext = reactive({
    currentTask: null,
    sessionId: `session_${Date.now()}`
})

const examplePrompts = ref([
    "Analyze RNA-seq data for differential expression",
    "Call variants from whole genome sequencing",
    "Assemble a bacterial genome from PacBio reads",
    "Quality control and trim Illumina reads"
])

// 计算属性
const getTaskDescription = computed(() => {
    switch (conversationContext.currentTask) {
        case 'workflow_creation':
            return 'Creating workflow...'
        case 'workflow_modification':
            return 'Modifying workflow...'
        default:
            return conversationContext.currentTask || ''
    }
})

// 方法
const handleWorkflowCreated = (data) => {
    console.log('Workflow created:', data)
    // 可以显示成功消息或跳转到编辑器
}

const handleWorkflowGenerated = (workflow) => {
    currentWorkflow.value = workflow
    selectedStep.value = null
}

const handleContextChange = (context) => {
    Object.assign(conversationContext, context)
}

const handleStepClick = (step) => {
    selectedStep.value = step
}

const handleConnectionClick = (connection) => {
    console.log('Connection clicked:', connection)
}

const updateStepParameter = (paramName, value) => {
    if (selectedStep.value) {
        selectedStep.value.parameters[paramName] = value
        // 通知聊天组件参数已更改
        // 可以触发AI提供相关建议
    }
}

const openInEditor = () => {
    if (currentWorkflow.value) {
        // 创建workflow并在编辑器中打开
        const editorUrl = `/workflow/editor?template=${encodeURIComponent(JSON.stringify(currentWorkflow.value))}`
        window.open(editorUrl, '_blank')
    }
}

const downloadWorkflow = () => {
    if (currentWorkflow.value) {
        const dataStr = JSON.stringify(currentWorkflow.value, null, 2)
        const dataBlob = new Blob([dataStr], { type: 'application/json' })
        const url = URL.createObjectURL(dataBlob)
        const link = document.createElement('a')
        link.href = url
        link.download = `${currentWorkflow.value.name || 'workflow'}.ga`
        link.click()
        URL.revokeObjectURL(url)
    }
}

const sendExamplePrompt = (prompt) => {
    // 向聊天组件发送示例提示
    // 需要通过事件或ref调用聊天组件的方法
    console.log('Sending example prompt:', prompt)
}

const resetSession = () => {
    currentWorkflow.value = null
    selectedStep.value = null
    conversationContext.currentTask = null
    conversationContext.sessionId = `session_${Date.now()}`
}
</script>

<style scoped lang="scss">
.workflow-chat-interface {
    display: flex;
    flex-direction: column;
    height: 100vh;
    background: #f8f9fa;
}

.interface-header {
    background: white;
    border-bottom: 1px solid #dee2e6;
    padding: 1rem 1.5rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    
    h2 {
        margin: 0;
        color: #495057;
        font-size: 1.5rem;
        
        i {
            color: #007bff;
            margin-right: 0.5rem;
        }
    }
    
    .header-actions {
        display: flex;
        gap: 0.5rem;
    }
}

.interface-body {
    flex: 1;
    display: flex;
    overflow: hidden;
}

.chat-panel {
    width: 40%;
    min-width: 400px;
    border-right: 1px solid #dee2e6;
    background: white;
}

.workflow-panel {
    flex: 1;
    display: flex;
    flex-direction: column;
    background: white;
    
    .panel-header {
        padding: 1rem;
        border-bottom: 1px solid #dee2e6;
        display: flex;
        justify-content: space-between;
        align-items: center;
        
        h4 {
            margin: 0;
            color: #495057;
        }
        
        .panel-actions {
            display: flex;
            gap: 0.5rem;
        }
    }
    
    .workflow-visualization {
        flex: 1;
        overflow: auto;
        padding: 1rem;
    }
    
    .step-details {
        border-top: 1px solid #dee2e6;
        padding: 1rem;
        background: #f8f9fa;
        max-height: 300px;
        overflow-y: auto;
        
        .info-row {
            display: flex;
            margin-bottom: 0.5rem;
            
            label {
                font-weight: 600;
                width: 100px;
                margin-right: 1rem;
            }
        }
        
        .parameters-section {
            margin-top: 1rem;
            
            .parameter-row {
                display: flex;
                align-items: center;
                margin-bottom: 0.5rem;
                
                label {
                    width: 120px;
                    margin-right: 1rem;
                }
            }
        }
    }
}

.empty-state {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    
    .empty-content {
        text-align: center;
        max-width: 500px;
        
        i {
            color: #6c757d;
            margin-bottom: 1rem;
        }
        
        h3 {
            color: #495057;
            margin-bottom: 1rem;
        }
        
        p {
            color: #6c757d;
            margin-bottom: 2rem;
            line-height: 1.5;
        }
        
        .example-prompts {
            h5 {
                color: #495057;
                margin-bottom: 1rem;
            }
            
            .prompt-buttons {
                display: flex;
                flex-wrap: wrap;
                justify-content: center;
                gap: 0.5rem;
            }
        }
    }
}

.interface-footer {
    background: white;
    border-top: 1px solid #dee2e6;
    padding: 0.75rem 1.5rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    
    .status-info {
        .current-task {
            color: #007bff;
            font-weight: 500;
        }
        
        .ready-status {
            color: #28a745;
        }
    }
    
    .quick-actions {
        display: flex;
        gap: 1rem;
    }
}
</style>