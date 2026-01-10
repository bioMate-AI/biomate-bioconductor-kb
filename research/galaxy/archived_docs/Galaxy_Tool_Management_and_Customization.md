# Galaxy AI 工具管理和自定义详解

## 概述

Galaxy AI 工作流生成系统中的工具来源于两个主要途径：**Galaxy 原生工具箱**和**预定义的备用工具库**。本文详细解析工具的来源、结构、添加和自定义方法。

## 1. 工具来源架构

### 1.1 主要来源：Galaxy Toolbox

```python
def _build_tool_index(self):
    """从Galaxy的实际工具库构建搜索索引"""
    try:
        toolbox = self.galaxy_app.toolbox  # 获取Galaxy工具箱
        
        for tool_id, tool in toolbox.tools():  # 遍历所有工具
            if tool and hasattr(tool, 'name'):
                tool_info = self._extract_tool_info(tool)  # 提取工具信息
                self.tool_index[tool_id] = tool_info       # 建立索引
                self._index_tool_by_category(tool_id, tool_info)  # 分类索引
                
        log.info(f"Built tool index with {len(self.tool_index)} tools")
        
    except Exception as e:
        log.warning(f"Could not build tool index from Galaxy: {e}")
        self._build_fallback_index()  # 如果失败，使用备用索引
```

**工具来源优先级：**
1. **第一优先级**：从运行中的Galaxy实例的toolbox中动态提取
2. **备用方案**：使用预定义的fallback工具列表

### 1.2 工具信息提取过程

```python
def _extract_tool_info(self, tool) -> Dict[str, Any]:
    """从Galaxy工具对象提取相关信息"""
    tool_info = {
        "id": tool.id,                                    # 工具唯一标识
        "name": getattr(tool, 'name', ''),               # 工具名称
        "description": getattr(tool, 'description', ''), # 工具描述
        "version": getattr(tool, 'version', ''),         # 版本信息
        "tool_type": getattr(tool, 'tool_type', 'tool'), # 工具类型
        "inputs": [],     # 输入参数列表
        "outputs": [],    # 输出文件列表
        "requirements": [], # 依赖要求
        "edam_operations": [], # EDAM操作类别
        "edam_topics": []      # EDAM主题类别
    }
    
    # 提取输入参数信息
    if hasattr(tool, 'inputs'):
        for input_param in tool.inputs.values():
            if hasattr(input_param, 'type'):
                tool_info["inputs"].append({
                    "name": getattr(input_param, 'name', ''),
                    "type": input_param.type,
                    "format": getattr(input_param, 'format', '')
                })
    
    # 提取输出文件信息
    if hasattr(tool, 'outputs'):
        for output_name, output_param in tool.outputs.items():
            tool_info["outputs"].append({
                "name": output_name,
                "format": getattr(output_param, 'format', ''),
                "type": getattr(output_param, 'type', 'data')
            })
    
    # 提取依赖要求
    if hasattr(tool, 'requirements'):
        for req in tool.requirements:
            tool_info["requirements"].append({
                "name": getattr(req, 'name', ''),
                "type": getattr(req, 'type', ''),
                "version": getattr(req, 'version', '')
            })
    
    return tool_info
```

### 1.3 备用工具库（Fallback Tools）

当无法从Galaxy动态获取工具时，系统使用预定义的核心工具集：

```python
def _build_fallback_index(self):
    """构建备用工具索引，包含常用的生物信息学工具"""
    fallback_tools = {
        # ===== 质量控制工具 =====
        "fastqc": {
            "id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0",
            "name": "FastQC",
            "description": "Read Quality reports",
            "inputs": [{"type": "fastq"}],
            "outputs": [{"type": "html"}, {"type": "txt"}],
            "category": "quality_control"
        },
        
        "multiqc": {
            "id": "toolshed.g2.bx.psu.edu/repos/iuc/multiqc/multiqc/1.11+galaxy1",
            "name": "MultiQC", 
            "description": "Aggregate results from bioinformatics analyses",
            "inputs": [{"type": "txt"}],
            "outputs": [{"type": "html"}],
            "category": "quality_control"
        },
        
        # ===== 序列处理工具 =====
        "cutadapt": {
            "id": "toolshed.g2.bx.psu.edu/repos/lparsons/cutadapt/cutadapt/4.4+galaxy0",
            "name": "Cutadapt",
            "description": "Remove adapter sequences from sequencing reads",
            "inputs": [{"type": "fastq"}],
            "outputs": [{"type": "fastq"}],
            "category": "quality_control"
        },
        
        # ===== 序列比对工具 =====
        "bwa_mem": {
            "id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.17.2",
            "name": "BWA-MEM",
            "description": "Map sequencing reads to reference genome",
            "inputs": [{"type": "fastq"}, {"type": "fasta"}],
            "outputs": [{"type": "bam"}],
            "category": "alignment"
        },
        
        "hisat2": {
            "id": "toolshed.g2.bx.psu.edu/repos/iuc/hisat2/hisat2/2.2.1+galaxy0",
            "name": "HISAT2",
            "description": "Splice-aware alignment for RNA-seq data",
            "inputs": [{"type": "fastq"}, {"type": "fasta"}],
            "outputs": [{"type": "bam"}],
            "category": "alignment"
        },
        
        # ===== RNA-seq分析工具 =====
        "featurecounts": {
            "id": "toolshed.g2.bx.psu.edu/repos/iuc/featurecounts/featurecounts/2.0.3+galaxy0",
            "name": "featureCounts",
            "description": "Count reads mapping to genomic features",
            "inputs": [{"type": "bam"}, {"type": "gtf"}],
            "outputs": [{"type": "tabular"}],
            "category": "rna_seq"
        },
        
        "deseq2": {
            "id": "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/1.40.2+galaxy0",
            "name": "DESeq2",
            "description": "Differential gene expression analysis",
            "inputs": [{"type": "tabular"}],
            "outputs": [{"type": "tabular"}, {"type": "png"}],
            "category": "rna_seq"
        },
        
        # ===== 变异检测工具 =====
        "freebayes": {
            "id": "toolshed.g2.bx.psu.edu/repos/devteam/freebayes/freebayes/1.3.6+galaxy0",
            "name": "FreeBayes",
            "description": "Bayesian genetic variant detector",
            "inputs": [{"type": "bam"}, {"type": "fasta"}],
            "outputs": [{"type": "vcf"}],
            "category": "variant_calling"
        }
    }
```

## 2. Galaxy 工具系统架构

### 2.1 工具配置层次结构

```
Galaxy工具系统
├── tool_conf.xml           # 本地工具配置
├── shed_tool_conf.xml      # Tool Shed工具配置  
├── integrated_tool_panel.xml # 集成工具面板
└── tools/                  # 工具定义文件目录
    ├── data_source/        # 数据源工具
    ├── filters/           # 过滤和处理工具
    ├── stats/            # 统计分析工具
    ├── interactive/      # 交互式工具
    └── ...
```

### 2.2 工具配置文件结构

**tool_conf.xml** - 主工具配置文件：
```xml
<?xml version='1.0' encoding='utf-8'?>
<toolbox monitor="true">
  <section id="getext" name="Get Data">
    <tool file="data_source/upload.xml" />
    <tool file="data_source/ucsc_tablebrowser.xml" />
    <!-- 更多工具 -->
  </section>
  
  <section id="textutil" name="Text Manipulation">
    <tool file="filters/grep.xml" />
    <tool file="filters/cutWrapper.xml" />
    <!-- 更多工具 -->
  </section>
</toolbox>
```

### 2.3 单个工具定义结构

每个工具由一个XML文件定义，包含完整的工具规范：

```xml
<tool id="Grep1" name="Select" version="1.0.4" profile="20.05">
  <!-- 基本信息 -->
  <description>lines that match an expression</description>
  
  <!-- 依赖要求 -->
  <requirements>
    <requirement type="package" version="3.4">grep</requirement>
  </requirements>
  
  <!-- EDAM本体标注 -->
  <edam_operations>
    <edam_operation>operation_3695</edam_operation>
  </edam_operations>
  
  <!-- 错误处理 -->
  <stdio>
    <exit_code range="2:" level="warning" description="Select failed" />
  </stdio>
  
  <!-- 执行命令 -->
  <command><![CDATA[
    set -eo pipefail;
    #if $keep_header
      head -n 1 '$input' > '$out_file1' &&
      tail -n +2 '$input'
    #else
      cat '$input'
    #end if
    | grep -P -f '$pattern_file' $invert >> '$out_file1'
  ]]></command>
  
  <!-- 配置文件 -->
  <configfiles>
    <configfile name="pattern_file">$pattern</configfile>
  </configfiles>
  
  <!-- 输入参数 -->
  <inputs>
    <param format="txt" name="input" type="data" label="Select lines from"/>
    <param name="invert" type="select" label="that">
      <option value="">Matching</option>
      <option value="-v">NOT Matching</option>
    </param>
    <param name="pattern" type="text" value="^chr([0-9A-Za-z])+" label="the pattern"/>
    <param name="keep_header" type="boolean" label="Keep header line"/>
  </inputs>
  
  <!-- 输出文件 -->
  <outputs>
    <data format_source="input" name="out_file1" metadata_source="input"/>
  </outputs>
  
  <!-- 测试用例 -->
  <tests>
    <test>
      <param name="input" value="1.bed"/>
      <param name="pattern" value="^chr[0-9]*"/>
      <output name="out_file1" file="fs-grep.dat"/>
    </test>
  </tests>
  
  <!-- 帮助文档 -->
  <help>
    工具使用说明...
  </help>
</tool>
```

## 3. 如何新增工具

### 3.1 方法一：通过Galaxy Tool Shed安装

**推荐方式**，适用于公开可用的工具：

1. **访问工具管理界面**：
   ```
   Galaxy管理界面 → Admin → Tool Management → Install Tools
   ```

2. **搜索和安装工具**：
   ```python
   # 示例：安装FastQC工具
   Tool Shed URL: https://toolshed.g2.bx.psu.edu/
   搜索: "fastqc"
   选择: devteam/fastqc
   安装到指定section
   ```

3. **AI系统自动识别**：
   ```python
   # 重启Galaxy后，AI系统会自动发现新工具
   toolbox = self.galaxy_app.toolbox
   for tool_id, tool in toolbox.tools():
       # 新安装的工具会被自动索引
       tool_info = self._extract_tool_info(tool)
   ```

### 3.2 方法二：自定义本地工具

**适用于定制化工具或内部工具**：

#### 步骤1：创建工具定义文件

在 `tools/` 目录下创建新的工具XML文件：

```xml
<!-- tools/custom/my_analysis_tool.xml -->
<tool id="my_analysis_tool" name="My Custom Analysis" version="1.0.0">
  <description>Custom bioinformatics analysis tool</description>
  
  <requirements>
    <requirement type="package" version="3.8">python</requirement>
    <requirement type="package" version="1.5.0">pandas</requirement>
  </requirements>
  
  <command><![CDATA[
    python '$__tool_directory__/my_analysis_script.py'
    --input '$input_file'
    --output '$output_file'
    --parameter '$parameter_value'
    #if $advanced_options.use_advanced == "true"
      --advanced_param '$advanced_options.advanced_param'
    #end if
  ]]></command>
  
  <inputs>
    <param name="input_file" type="data" format="tabular" 
           label="Input data file" help="Tab-delimited input file"/>
    
    <param name="parameter_value" type="integer" value="10" min="1" max="100"
           label="Analysis parameter" help="Numerical parameter for analysis"/>
    
    <conditional name="advanced_options">
      <param name="use_advanced" type="select" label="Use advanced options">
        <option value="false">No</option>
        <option value="true">Yes</option>
      </param>
      <when value="true">
        <param name="advanced_param" type="float" value="0.05" 
               label="Advanced parameter"/>
      </when>
    </conditional>
  </inputs>
  
  <outputs>
    <data name="output_file" format="tabular" label="Analysis results"/>
  </outputs>
  
  <tests>
    <test>
      <param name="input_file" value="test_input.tab"/>
      <param name="parameter_value" value="20"/>
      <output name="output_file" file="expected_output.tab"/>
    </test>
  </tests>
  
  <help><![CDATA[
    这是一个自定义的生物信息学分析工具。
    
    **输入**：
    - 制表符分隔的数据文件
    
    **输出**：  
    - 分析结果文件
    
    **参数说明**：
    - Analysis parameter: 控制分析强度的数值参数
  ]]></help>
</tool>
```

#### 步骤2：创建执行脚本

```python
# tools/custom/my_analysis_script.py
#!/usr/bin/env python3

import argparse
import pandas as pd

def main():
    parser = argparse.ArgumentParser(description='Custom analysis tool')
    parser.add_argument('--input', required=True, help='Input file')
    parser.add_argument('--output', required=True, help='Output file') 
    parser.add_argument('--parameter', type=int, default=10, help='Analysis parameter')
    parser.add_argument('--advanced_param', type=float, default=0.05, help='Advanced parameter')
    
    args = parser.parse_args()
    
    # 读取输入数据
    data = pd.read_csv(args.input, sep='\t')
    
    # 执行分析逻辑
    result = perform_analysis(data, args.parameter, args.advanced_param)
    
    # 保存结果
    result.to_csv(args.output, sep='\t', index=False)
    
    print(f"Analysis completed. Results saved to {args.output}")

def perform_analysis(data, param, advanced_param):
    # 在这里实现你的分析逻辑
    # 这只是一个示例
    result = data.copy()
    result['analysis_score'] = data.iloc[:, 0] * param * advanced_param
    return result

if __name__ == '__main__':
    main()
```

#### 步骤3：注册到工具配置

修改 `config/tool_conf.xml`：

```xml
<toolbox monitor="true">
  <!-- 现有sections -->
  
  <!-- 添加自定义工具section -->
  <section id="custom" name="Custom Tools">
    <tool file="custom/my_analysis_tool.xml" />
  </section>
</toolbox>
```

#### 步骤4：重启Galaxy

```bash
# 重启Galaxy服务
./run.sh --reload
```

### 3.3 方法三：直接扩展AI系统的工具库

**适用于快速原型和测试**：

直接修改 `galaxy_tool_rag.py` 中的fallback工具列表：

```python
def _build_fallback_index(self):
    fallback_tools = {
        # 现有工具...
        
        # 添加新的自定义工具
        "my_custom_tool": {
            "id": "my_custom_analysis_tool",
            "name": "My Custom Analysis", 
            "description": "Custom bioinformatics analysis tool",
            "inputs": [{"type": "tabular"}],
            "outputs": [{"type": "tabular"}],
            "category": "custom_analysis"
        },
        
        # 添加新的工具类别
        "protein_analysis": {
            "id": "protein_structure_predictor", 
            "name": "Protein Structure Predictor",
            "description": "Predict protein secondary structure",
            "inputs": [{"type": "fasta"}],
            "outputs": [{"type": "txt"}, {"type": "png"}],
            "category": "protein_analysis"
        }
    }
    
    # 同时更新分类系统
    def _categorize_tool(self, tool_info):
        # 添加新的分类模式
        category_patterns = {
            # 现有分类...
            "protein_analysis": ["protein", "structure", "secondary", "folding"],
            "metabolomics": ["metabolite", "ms", "mass_spec", "metabolome"],
            "phylogenetics": ["phylogen", "tree", "evolutionary", "cladogram"]
        }
```

## 4. 工具自定义和优化

### 4.1 工具参数智能推荐

AI系统可以为工具参数提供智能推荐：

```python
def _generate_tool_parameters(self, task: Task, tool: Tool) -> Dict[str, Any]:
    """为工具生成智能参数建议"""
    parameters = {}
    
    # 基于任务类型的参数优化
    if task.task_type == TaskType.QUALITY_CONTROL:
        if "fastqc" in tool.id.lower():
            parameters.update({
                "nogroup": "true",  # 不按位置分组
                "extract": "true"   # 提取压缩文件
            })
    
    elif task.task_type == TaskType.ALIGNMENT:
        if "hisat2" in tool.id.lower():
            parameters.update({
                "threads": 4,           # 线程数
                "min_intronlen": 20,    # 最小内含子长度
                "max_intronlen": 500000 # 最大内含子长度
            })
        elif "bwa" in tool.id.lower():
            parameters.update({
                "threads": 4,       # 线程数
                "min_seed_length": 19,  # 最小种子长度
                "bandwidth": 100    # 带宽参数
            })
    
    elif task.task_type == TaskType.VARIANT_CALLING:
        if "freebayes" in tool.id.lower():
            parameters.update({
                "min_base_quality": 20,     # 最小碱基质量
                "min_mapping_quality": 30,  # 最小比对质量
                "ploidy": 2                 # 倍性
            })
    
    # 基于数据类型的参数优化
    for input_data_type in task.input_data_types:
        if input_data_type.name == "fastq":
            # 针对FASTQ数据的参数
            if "cutadapt" in tool.id.lower():
                parameters.update({
                    "minimum_length": 20,  # 最小读长
                    "quality_cutoff": 20   # 质量截断值
                })
    
    return parameters
```

### 4.2 工具兼容性增强

```python
def enhance_tool_compatibility(self):
    """增强工具间的数据类型兼容性"""
    
    # 定义数据类型转换映射
    type_conversion_map = {
        "fastqsanger": ["fastq", "fastqillumina"],
        "bam": ["sam"],
        "tabular": ["csv", "tsv", "txt"],
        "gff3": ["gff", "gtf"],
        "fasta": ["fa", "fna", "faa"]
    }
    
    # 扩展工具搜索的兼容性检查
    def _enhanced_type_compatibility(self, tool_output_type, required_input_type):
        # 直接匹配
        if tool_output_type == required_input_type:
            return True
        
        # 查找转换映射
        for base_type, compatible_types in type_conversion_map.items():
            if (tool_output_type == base_type and required_input_type in compatible_types) or \
               (required_input_type == base_type and tool_output_type in compatible_types):
                return True
        
        return False
```

### 4.3 工具性能监控

```python
class ToolPerformanceMonitor:
    """工具性能监控和优化建议"""
    
    def __init__(self):
        self.performance_data = {}
        self.usage_statistics = {}
    
    def record_tool_performance(self, tool_id: str, execution_time: float, 
                               memory_usage: float, success: bool):
        """记录工具执行性能"""
        if tool_id not in self.performance_data:
            self.performance_data[tool_id] = {
                "execution_times": [],
                "memory_usages": [], 
                "success_rate": {"success": 0, "total": 0}
            }
        
        data = self.performance_data[tool_id]
        data["execution_times"].append(execution_time)
        data["memory_usages"].append(memory_usage)
        data["success_rate"]["total"] += 1
        if success:
            data["success_rate"]["success"] += 1
    
    def get_tool_recommendations(self, task_type: str) -> List[Dict]:
        """基于性能数据推荐工具"""
        recommendations = []
        
        for tool_id, data in self.performance_data.items():
            if len(data["execution_times"]) < 5:  # 数据不足
                continue
                
            avg_time = sum(data["execution_times"]) / len(data["execution_times"])
            avg_memory = sum(data["memory_usages"]) / len(data["memory_usages"])
            success_rate = data["success_rate"]["success"] / data["success_rate"]["total"]
            
            # 综合评分
            performance_score = (success_rate * 0.5) + \
                              ((1.0 / avg_time) * 0.3) + \
                              ((1.0 / avg_memory) * 0.2)
            
            recommendations.append({
                "tool_id": tool_id,
                "performance_score": performance_score,
                "avg_execution_time": avg_time,
                "avg_memory_usage": avg_memory,
                "success_rate": success_rate
            })
        
        return sorted(recommendations, key=lambda x: x["performance_score"], reverse=True)
```

## 5. 工具发现和分类系统

### 5.1 自动工具分类

```python
def _categorize_tool(self, tool_info: Dict[str, Any]) -> List[str]:
    """基于多维特征的智能工具分类"""
    categories = []
    
    # 提取工具文本特征
    name_lower = tool_info["name"].lower()
    desc_lower = tool_info["description"].lower()
    tool_text = f"{name_lower} {desc_lower}"
    
    # 高级分类模式（支持正则表达式）
    import re
    
    advanced_patterns = {
        "quality_control": [
            r"quality|qc|fastqc|multiqc",
            r"trim|filter|clean",
            r"assessment|evaluation|report"
        ],
        "alignment": [
            r"align|map|mapping",
            r"bwa|bowtie|hisat|star|minimap",
            r"reference.*genome|genome.*reference"
        ],
        "assembly": [
            r"assembl(y|e|ing)",
            r"spades|velvet|canu|flye|unicycler",
            r"contigs?|scaffolds?|de.novo"
        ],
        "variant_calling": [
            r"variant|snp|indel|mutation",
            r"freebayes|gatk|bcftools|varscan",
            r"genotyp|call"
        ],
        "rna_seq": [
            r"rna.seq|transcriptom",
            r"expression|differential",
            r"deseq|cufflinks|htseq|salmon|kallisto"
        ],
        "annotation": [
            r"annotat|blast|interpro",
            r"functional|ontology|pathway",
            r"pfam|go|kegg"
        ],
        "phylogenetics": [
            r"phylogen|evolution|tree",
            r"muscle|clustal|mafft|raxml",
            r"alignment|multiple.*sequence"
        ],
        "metagenomics": [
            r"metagen|microbiome|16s",
            r"taxa|taxonomy|otu",
            r"qiime|mothur|usearch"
        ]
    }
    
    # 应用高级模式匹配
    for category, patterns in advanced_patterns.items():
        for pattern in patterns:
            if re.search(pattern, tool_text, re.IGNORECASE):
                categories.append(category)
                break
    
    # EDAM本体分类（如果可用）
    if tool_info.get("edam_operations"):
        edam_mapping = {
            "operation_2403": "sequence_analysis",
            "operation_3198": "read_mapping", 
            "operation_3227": "variant_calling",
            "operation_3680": "rna_seq_analysis"
        }
        
        for operation in tool_info["edam_operations"]:
            if operation in edam_mapping:
                categories.append(edam_mapping[operation])
    
    return categories if categories else ["other"]
```

### 5.2 动态工具发现

```python
def discover_new_tools(self):
    """动态发现新安装的工具"""
    current_tools = set(self.tool_index.keys())
    
    # 重新扫描Galaxy toolbox
    try:
        toolbox = self.galaxy_app.toolbox
        discovered_tools = set()
        
        for tool_id, tool in toolbox.tools():
            if tool and hasattr(tool, 'name'):
                discovered_tools.add(tool_id)
                
                # 如果是新工具，添加到索引
                if tool_id not in current_tools:
                    tool_info = self._extract_tool_info(tool)
                    self.tool_index[tool_id] = tool_info
                    self._index_tool_by_category(tool_id, tool_info)
                    log.info(f"Discovered new tool: {tool.name} ({tool_id})")
        
        # 移除已卸载的工具
        removed_tools = current_tools - discovered_tools
        for tool_id in removed_tools:
            if tool_id in self.tool_index:
                del self.tool_index[tool_id]
                log.info(f"Removed tool: {tool_id}")
        
        return len(discovered_tools - current_tools)
        
    except Exception as e:
        log.error(f"Error discovering new tools: {e}")
        return 0
```

## 6. 工具集成最佳实践

### 6.1 工具测试和验证

```python
def validate_tool_integration(tool_id: str) -> Dict[str, Any]:
    """验证工具集成的完整性"""
    validation_result = {
        "tool_id": tool_id,
        "status": "unknown",
        "issues": [],
        "recommendations": []
    }
    
    try:
        # 检查工具是否在Galaxy中可用
        toolbox = self.galaxy_app.toolbox
        tool = toolbox.get_tool(tool_id)
        
        if not tool:
            validation_result["status"] = "not_found"
            validation_result["issues"].append("Tool not found in Galaxy toolbox")
            return validation_result
        
        # 检查工具定义完整性
        required_attributes = ["name", "description", "inputs", "outputs"]
        for attr in required_attributes:
            if not hasattr(tool, attr) or not getattr(tool, attr):
                validation_result["issues"].append(f"Missing or empty {attr}")
        
        # 检查依赖项
        if hasattr(tool, 'requirements'):
            for req in tool.requirements:
                # 这里可以检查依赖是否已安装
                pass
        
        # 检查测试用例
        if hasattr(tool, 'tests') and len(tool.tests) > 0:
            validation_result["recommendations"].append("Tool has test cases - good!")
        else:
            validation_result["recommendations"].append("Consider adding test cases")
        
        validation_result["status"] = "valid" if not validation_result["issues"] else "issues"
        
    except Exception as e:
        validation_result["status"] = "error"
        validation_result["issues"].append(f"Validation error: {str(e)}")
    
    return validation_result
```

### 6.2 工具使用统计和优化

```python
class ToolUsageAnalyzer:
    """工具使用情况分析和优化建议"""
    
    def analyze_workflow_patterns(self, workflows: List[Dict]) -> Dict[str, Any]:
        """分析工作流中的工具使用模式"""
        tool_usage = {}
        tool_combinations = {}
        
        for workflow in workflows:
            workflow_tools = []
            
            for step in workflow.get("steps", []):
                tool_id = step.get("tool_id")
                if tool_id:
                    workflow_tools.append(tool_id)
                    tool_usage[tool_id] = tool_usage.get(tool_id, 0) + 1
            
            # 分析工具组合模式
            for i in range(len(workflow_tools) - 1):
                combination = (workflow_tools[i], workflow_tools[i + 1])
                tool_combinations[combination] = tool_combinations.get(combination, 0) + 1
        
        return {
            "most_used_tools": sorted(tool_usage.items(), key=lambda x: x[1], reverse=True)[:10],
            "common_combinations": sorted(tool_combinations.items(), key=lambda x: x[1], reverse=True)[:10],
            "total_unique_tools": len(tool_usage),
            "total_workflows_analyzed": len(workflows)
        }
    
    def suggest_tool_optimizations(self, usage_stats: Dict) -> List[str]:
        """基于使用统计建议工具优化"""
        suggestions = []
        
        most_used = usage_stats["most_used_tools"]
        if most_used:
            top_tool = most_used[0][0]
            suggestions.append(f"Consider optimizing parameters for {top_tool} (most used tool)")
        
        common_combos = usage_stats["common_combinations"] 
        if common_combos:
            combo = common_combos[0][0]
            suggestions.append(f"Create optimized template for {combo[0]} → {combo[1]} pipeline")
        
        return suggestions
```

## 7. 总结

### 工具来源层次：
1. **Galaxy Toolbox**（主要来源）→ 动态提取所有已安装工具
2. **Fallback Tools**（备用来源）→ 预定义核心工具集
3. **Tool Shed**（扩展来源）→ 社区贡献工具

### 添加工具的方法：
1. **Tool Shed安装**：适用于公开工具，推荐方式
2. **自定义本地工具**：适用于定制化需求
3. **直接扩展AI工具库**：适用于快速原型

### 自定义能力：
- 智能参数推荐
- 工具性能监控
- 动态分类和发现
- 兼容性增强
- 使用模式分析

这个架构设计确保了AI工作流生成系统既能利用Galaxy丰富的工具生态，又具备高度的可扩展性和定制化能力，为不同用户需求提供灵活的解决方案。

---

**文档版本**: 1.0  
**创建时间**: 2025-08-22  
**主要关注**: 工具管理、集成和自定义