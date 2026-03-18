"""
Tool-Specific Error Patterns

定义常见生物信息学工具的错误模式和修复方案
"""

# Samtools 错误模式
SAMTOOLS_PATTERNS = {
    'SAMTOOLS_SORT_MEMORY': {
        'keywords': ['samtools', 'sort', 'memory', 'out of memory'],
        'exit_codes': [1, 137],
        'tool_name': 'samtools',
        'command': 'sort',
        'fix_type': 'increase_memory',
        'recommendation': '增加 Samtools sort 的内存限制',
        'fixable': True,
        'auto_fix_params': {
            'samtools_sort_per_thread': '4G',  # 每线程 4GB
            'max_memory': '32.GB',
        },
        'diagnostic_command': 'samtools --version',
    },
    'SAMTOOLS_INDEX_FAILED': {
        'keywords': ['samtools', 'index', 'truncated', 'corrupt'],
        'exit_codes': [1],
        'tool_name': 'samtools',
        'command': 'index',
        'fix_type': 'regenerate_bam',
        'recommendation': '重新生成 BAM 文件或使用 samtools view 修复',
        'fixable': False,
        'user_action_required': True,
        'diagnostic_command': 'samtools quickcheck file.bam',
    },
    'SAMTOOLS_VIEW_FORMAT': {
        'keywords': ['samtools', 'view', 'invalid', 'format'],
        'exit_codes': [1],
        'tool_name': 'samtools',
        'command': 'view',
        'fix_type': 'format_conversion',
        'recommendation': '检查输入文件格式，可能需要重新比对',
        'fixable': False,
        'user_action_required': True,
    },
}

# Picard 错误模式
PICARD_PATTERNS = {
    'PICARD_MARK_DUPLICATES_MEMORY': {
        'keywords': ['picard', 'MarkDuplicates', 'java.lang.OutOfMemoryError'],
        'exit_codes': [1],
        'tool_name': 'picard',
        'command': 'MarkDuplicates',
        'fix_type': 'increase_memory',
        'recommendation': '增加 Picard 的 Java heap size',
        'fixable': True,
        'auto_fix_params': {
            'picard_java_options': '-Xmx16g',  # 16GB heap
            'max_memory': '20.GB',  # 总内存稍大于 heap
        },
    },
    'PICARD_VALIDATION_ERROR': {
        'keywords': ['picard', 'ValidateSamFile', 'ERROR::INVALID'],
        'exit_codes': [1],
        'tool_name': 'picard',
        'command': 'ValidateSamFile',
        'fix_type': 'validation_fix',
        'recommendation': '忽略验证错误或修复 BAM 文件',
        'fixable': True,
        'auto_fix_params': {
            'picard_validation_stringency': 'LENIENT',  # 宽松模式
        },
    },
    'PICARD_SORT_ORDER': {
        'keywords': ['picard', 'sort order', 'queryname', 'coordinate'],
        'exit_codes': [1],
        'tool_name': 'picard',
        'command': 'SortSam',
        'fix_type': 'sort_order_fix',
        'recommendation': '添加排序步骤或调整排序顺序',
        'fixable': True,
        'auto_fix_params': {
            'picard_sort_order': 'coordinate',  # 使用坐标排序
        },
    },
}

# deepTools 错误模式
DEEPTOOLS_PATTERNS = {
    'DEEPTOOLS_BAMCOVERAGE_MEMORY': {
        'keywords': ['deeptools', 'bamCoverage', 'MemoryError'],
        'exit_codes': [1, 137],
        'tool_name': 'deeptools',
        'command': 'bamCoverage',
        'fix_type': 'increase_memory',
        'recommendation': '增加内存或减少 binSize',
        'fixable': True,
        'auto_fix_params': {
            'deeptools_bin_size': 50,  # 增大 binSize (默认 10)
            'max_memory': '32.GB',
        },
    },
    'DEEPTOOLS_EMPTY_BAM': {
        'keywords': ['deeptools', 'no reads', 'empty bam'],
        'exit_codes': [1],
        'tool_name': 'deeptools',
        'command': 'bamCoverage',
        'fix_type': 'data_validation',
        'recommendation': '检查输入 BAM 文件是否包含比对结果',
        'fixable': False,
        'user_action_required': True,
        'diagnostic_command': 'samtools view -c file.bam',
    },
}

# bcftools 错误模式
BCFTOOLS_PATTERNS = {
    'BCFTOOLS_CALL_MEMORY': {
        'keywords': ['bcftools', 'call', 'out of memory'],
        'exit_codes': [1, 137],
        'tool_name': 'bcftools',
        'command': 'call',
        'fix_type': 'increase_memory',
        'recommendation': '增加内存或分割染色体处理',
        'fixable': True,
        'auto_fix_params': {
            'max_memory': '64.GB',
            'bcftools_threads': 8,
        },
    },
    'BCFTOOLS_INDEX_MISSING': {
        'keywords': ['bcftools', 'index', 'could not load index'],
        'exit_codes': [1],
        'tool_name': 'bcftools',
        'command': 'view',
        'fix_type': 'create_index',
        'recommendation': '使用 bcftools index 创建索引',
        'fixable': True,
        'auto_fix_params': {
            'bcftools_create_index': True,
        },
    },
}

# STAR 错误模式（扩展）
STAR_PATTERNS = {
    'STAR_GENOMEGENERATE_MEMORY': {
        'keywords': ['STAR', 'genomeGenerate', 'EXITING because of FATAL ERROR'],
        'exit_codes': [1, 110],
        'tool_name': 'STAR',
        'command': 'genomeGenerate',
        'fix_type': 'increase_memory',
        'recommendation': 'STAR 基因组索引构建需要大量内存',
        'fixable': True,
        'auto_fix_params': {
            'star_index_max_memory': '64000000000',  # 64GB
            'max_memory': '64.GB',
        },
    },
    'STAR_ALIGN_GENOME_INCOMPATIBLE': {
        'keywords': ['STAR', 'EXITING', 'incompatible genome'],
        'exit_codes': [1],
        'tool_name': 'STAR',
        'command': 'align',
        'fix_type': 'regenerate_index',
        'recommendation': 'STAR 索引与当前版本不兼容，需要重新生成',
        'fixable': False,
        'user_action_required': True,
        'diagnostic_command': 'cat genome_index/Log.out',
    },
    'STAR_ALIGN_READ_LENGTH': {
        'keywords': ['STAR', 'read length', 'too short'],
        'exit_codes': [1],
        'tool_name': 'STAR',
        'command': 'align',
        'fix_type': 'adjust_parameters',
        'recommendation': '调整 --seedSearchStartLmax 参数适应短 reads',
        'fixable': True,
        'auto_fix_params': {
            'star_seed_search_start_lmax': 20,  # 适应短 reads
            'star_align_intron_min': 20,
        },
    },
}

# Bowtie2 错误模式（扩展）
BOWTIE2_PATTERNS = {
    'BOWTIE2_INDEX_CORRUPT': {
        'keywords': ['bowtie2', 'index', 'corrupt', 'mismatch'],
        'exit_codes': [1],
        'tool_name': 'bowtie2',
        'command': 'align',
        'fix_type': 'rebuild_index',
        'recommendation': 'Bowtie2 索引损坏，需要重新构建',
        'fixable': False,
        'user_action_required': True,
        'diagnostic_command': 'bowtie2-inspect genome_index',
    },
    'BOWTIE2_ALIGNMENT_RATE_LOW': {
        'keywords': ['bowtie2', 'overall alignment rate'],
        'exit_codes': [0],  # 不是错误，但比对率低
        'tool_name': 'bowtie2',
        'command': 'align',
        'fix_type': 'adjust_sensitivity',
        'recommendation': '比对率低，调整敏感度参数',
        'fixable': True,
        'auto_fix_params': {
            'bowtie2_sensitivity': '--very-sensitive',
            'bowtie2_n': 1,  # 允许 1 个 mismatch
        },
        'threshold': 50.0,  # 比对率低于 50% 触发
    },
}

# HISAT2 错误模式
HISAT2_PATTERNS = {
    'HISAT2_INDEX_MISSING': {
        'keywords': ['hisat2', 'could not locate', 'index'],
        'exit_codes': [1],
        'tool_name': 'hisat2',
        'command': 'align',
        'fix_type': 'download_index',
        'recommendation': '下载或构建 HISAT2 索引',
        'fixable': False,
        'user_action_required': True,
    },
    'HISAT2_MEMORY': {
        'keywords': ['hisat2', 'out of memory'],
        'exit_codes': [1, 137],
        'tool_name': 'hisat2',
        'command': 'align',
        'fix_type': 'increase_memory',
        'recommendation': '增加内存配额',
        'fixable': True,
        'auto_fix_params': {
            'max_memory': '32.GB',
        },
    },
}

# BWA 错误模式
BWA_PATTERNS = {
    'BWA_INDEX_MISSING': {
        'keywords': ['bwa', 'fail to open', '.bwt'],
        'exit_codes': [1],
        'tool_name': 'bwa',
        'command': 'mem',
        'fix_type': 'create_index',
        'recommendation': '使用 bwa index 创建索引',
        'fixable': True,
        'auto_fix_params': {
            'bwa_create_index': True,
        },
    },
    'BWA_MEM_THREADS': {
        'keywords': ['bwa', 'mem', 'too many threads'],
        'exit_codes': [1],
        'tool_name': 'bwa',
        'command': 'mem',
        'fix_type': 'adjust_threads',
        'recommendation': '减少线程数',
        'fixable': True,
        'auto_fix_params': {
            'bwa_threads': 8,  # 减少到 8 线程
            'max_cpus': 8,
        },
    },
}

# FastQC 错误模式
FASTQC_PATTERNS = {
    'FASTQC_ENCODING': {
        'keywords': ['fastqc', 'quality encoding', 'illumina'],
        'exit_codes': [1],
        'tool_name': 'fastqc',
        'command': 'fastqc',
        'fix_type': 'encoding_conversion',
        'recommendation': '转换 FASTQ 质量编码',
        'fixable': True,
        'auto_fix_params': {
            'fastqc_encoding': 'sanger',  # 使用 Sanger/Illumina 1.8+
        },
    },
    'FASTQC_ZIP_ERROR': {
        'keywords': ['fastqc', 'zip', 'error'],
        'exit_codes': [1],
        'tool_name': 'fastqc',
        'command': 'fastqc',
        'fix_type': 'disable_compression',
        'recommendation': '禁用压缩或检查磁盘空间',
        'fixable': True,
        'auto_fix_params': {
            'fastqc_nozip': True,
        },
    },
}

# MultiQC 错误模式
MULTIQC_PATTERNS = {
    'MULTIQC_NO_DATA': {
        'keywords': ['multiqc', 'no analysis results'],
        'exit_codes': [1],
        'tool_name': 'multiqc',
        'command': 'multiqc',
        'fix_type': 'check_inputs',
        'recommendation': '检查上游分析步骤是否成功',
        'fixable': False,
        'user_action_required': True,
    },
}

# Cutadapt 错误模式
CUTADAPT_PATTERNS = {
    'CUTADAPT_ADAPTER_NOT_FOUND': {
        'keywords': ['cutadapt', 'adapter', 'not found'],
        'exit_codes': [1],
        'tool_name': 'cutadapt',
        'command': 'cutadapt',
        'fix_type': 'adjust_adapter',
        'recommendation': '检查 adapter 序列或使用自动检测',
        'fixable': True,
        'auto_fix_params': {
            'cutadapt_adapter_auto': True,
        },
    },
}

# 合并所有工具模式
ALL_TOOL_PATTERNS = {
    **SAMTOOLS_PATTERNS,
    **PICARD_PATTERNS,
    **DEEPTOOLS_PATTERNS,
    **BCFTOOLS_PATTERNS,
    **STAR_PATTERNS,
    **BOWTIE2_PATTERNS,
    **HISAT2_PATTERNS,
    **BWA_PATTERNS,
    **FASTQC_PATTERNS,
    **MULTIQC_PATTERNS,
    **CUTADAPT_PATTERNS,
}

# 按工具分类
PATTERNS_BY_TOOL = {
    'samtools': SAMTOOLS_PATTERNS,
    'picard': PICARD_PATTERNS,
    'deeptools': DEEPTOOLS_PATTERNS,
    'bcftools': BCFTOOLS_PATTERNS,
    'STAR': STAR_PATTERNS,
    'bowtie2': BOWTIE2_PATTERNS,
    'hisat2': HISAT2_PATTERNS,
    'bwa': BWA_PATTERNS,
    'fastqc': FASTQC_PATTERNS,
    'multiqc': MULTIQC_PATTERNS,
    'cutadapt': CUTADAPT_PATTERNS,
}


def get_pattern_by_tool(tool_name: str) -> dict:
    """
    获取指定工具的错误模式

    Args:
        tool_name: 工具名称

    Returns:
        错误模式字典
    """
    return PATTERNS_BY_TOOL.get(tool_name.lower(), {})


def search_pattern(error_log: str, exit_code: int = None) -> list:
    """
    从错误日志中搜索匹配的错误模式

    Args:
        error_log: 错误日志
        exit_code: 退出码

    Returns:
        匹配的模式列表
    """
    matches = []

    for pattern_name, pattern in ALL_TOOL_PATTERNS.items():
        # 检查关键词匹配
        keywords_match = any(
            keyword.lower() in error_log.lower()
            for keyword in pattern.get('keywords', [])
        )

        # 检查退出码匹配
        exit_code_match = (
            exit_code is None or
            exit_code in pattern.get('exit_codes', [])
        )

        if keywords_match and exit_code_match:
            matches.append({
                'pattern_name': pattern_name,
                'pattern': pattern,
                'confidence': 1.0 if keywords_match and exit_code_match else 0.5,
            })

    # 按置信度排序
    matches.sort(key=lambda x: x['confidence'], reverse=True)

    return matches
