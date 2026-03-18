"""
AutoFix User Guidance System

提供智能的用户操作指导，特别是对于无法通过参数自动修复的问题。

核心功能:
1. 问题分类（可自动修复 vs 需要用户操作 vs 无法修复）
2. 生成详细的用户操作指南
3. 提供多种解决方案（有优先级）
4. 估算操作难度和成功率
"""

from enum import Enum
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
import logging

log = logging.getLogger(__name__)


class FixStrategy(Enum):
    """修复策略"""
    AUTO_FIXABLE = "auto_fixable"           # 可以自动修复
    USER_ACTION_REQUIRED = "user_action"    # 需要用户操作
    NOT_FIXABLE = "not_fixable"             # 无法修复


class IssueCategory(Enum):
    """问题类别"""
    # 可自动修复的
    PARAMETER_MISSING = "parameter_missing"
    PARAMETER_WRONG = "parameter_wrong"
    RESOURCE_INSUFFICIENT = "resource_insufficient"

    # 需要用户操作的
    DATA_QUALITY = "data_quality"
    DATA_FORMAT = "data_format"
    MISSING_REFERENCE = "missing_reference"

    # 无法修复的
    CONTAINER_ERROR = "container_error"
    PERMISSION_ERROR = "permission_error"
    SYSTEM_ERROR = "system_error"


@dataclass
class Action:
    """用户可执行的操作"""
    priority: int                          # 优先级（1=最推荐）
    title: str                             # 操作标题
    description: str                       # 详细说明
    steps: List[str]                       # 操作步骤
    external_resources: List[str] = field(default_factory=list)  # 外部资源链接
    estimated_time: str = "未知"           # 预估时间
    estimated_download_size: str = None    # 需要下载的大小
    success_probability: float = 0.8       # 成功概率
    impact: str = ""                       # 影响说明
    recommendation_level: str = "★★★☆☆"   # 推荐等级
    note: str = None                       # 额外说明


@dataclass
class UserGuidance:
    """用户操作指导"""
    issue_type: str                        # 问题类型
    severity: str                          # 严重程度
    category: IssueCategory                # 问题类别
    fix_strategy: FixStrategy              # 修复策略

    # 问题描述
    problem_summary: str                   # 问题摘要
    problem_details: str                   # 详细描述
    affected_tasks: List[str] = field(default_factory=list)
    error_messages: List[str] = field(default_factory=list)

    # 用户操作建议
    recommended_actions: List[Action] = field(default_factory=list)

    # 参考资源
    documentation: List[str] = field(default_factory=list)

    # AutoFix尝试的操作（如果有）
    auto_attempted_fix: Dict[str, Any] = None

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典格式"""
        return {
            'issue_type': self.issue_type,
            'severity': self.severity,
            'category': self.category.value,
            'fix_strategy': self.fix_strategy.value,
            'problem': {
                'summary': self.problem_summary,
                'details': self.problem_details,
                'affected_tasks': self.affected_tasks,
                'error_messages': self.error_messages
            },
            'recommended_actions': [
                {
                    'priority': action.priority,
                    'title': action.title,
                    'description': action.description,
                    'steps': action.steps,
                    'external_resources': action.external_resources,
                    'estimated_time': action.estimated_time,
                    'estimated_download_size': action.estimated_download_size,
                    'success_probability': action.success_probability,
                    'impact': action.impact,
                    'recommendation_level': action.recommendation_level,
                    'note': action.note
                }
                for action in self.recommended_actions
            ],
            'documentation': self.documentation,
            'auto_attempted_fix': self.auto_attempted_fix
        }


# ============================================================================
# 知识库：常见问题的用户指导
# ============================================================================

GTF_FORMAT_ERROR_GUIDANCE = UserGuidance(
    issue_type="gtf_format_error",
    severity="high",
    category=IssueCategory.DATA_FORMAT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="GTF文件格式错误或缺少必需属性，导致基因注释处理失败",
    problem_details="""
GTF (Gene Transfer Format) 文件格式不符合规范，导致iCount或其他工具无法解析。

**最常见问题**：
1. **缺少 exon_number 属性** - iCount/STAR 等工具需要每个 exon 特征都有 exon_number 属性
   错误示例: [KeyError] exon_number

2. **缺少 transcript_id 或 gene_id** - 基因组工具需要这些标识符来关联特征

3. **格式不规范** - GTF 文件必须有 9 列，属性格式必须正确（`key "value";`）

**其他常见原因**:
• GTF 文件来源不可靠（非官方源、自行编辑的文件）
• 文件在传输过程中损坏
• 文件编码问题（非 UTF-8）或使用 Windows 换行符（CRLF）
• GTF 版本不匹配（GTF2 vs GTF3）

**重要**: 这不是可以通过调整参数解决的问题，必须使用符合规范的 GTF 文件。
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用GENCODE官方GTF文件（最推荐）",
            description="GENCODE是最权威的基因注释数据库，数据质量有保证，被广泛使用",
            steps=[
                "1. 访问 GENCODE 网站: https://www.gencodegenes.org/human/",
                "2. 选择适合的版本（推荐最新release版本，如release 44）",
                "3. 下载 'Comprehensive gene annotation' GTF文件",
                "4. 在Galaxy中上传新的GTF文件（工具 → Get Data → Upload File）",
                "5. 重新运行workflow并在参数中选择新的GTF文件"
            ],
            external_resources=[
                "https://www.gencodegenes.org/human/",
                "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/",
                "https://www.gencodegenes.org/pages/data_format.html"
            ],
            estimated_time="10-15分钟（含下载时间）",
            estimated_download_size="约50MB压缩，解压后约300MB",
            success_probability=0.95,
            impact="完全解决GTF格式问题，确保下游分析准确性",
            recommendation_level="★★★★★"
        ),

        Action(
            priority=2,
            title="使用Ensembl GTF文件（备选方案）",
            description="Ensembl也是权威数据源，与GENCODE数据类似但可能有细微差异",
            steps=[
                "1. 访问 Ensembl FTP: http://ftp.ensembl.org/pub/release-110/gtf/homo_sapiens/",
                "2. 下载 Homo_sapiens.GRCh38.110.gtf.gz",
                "3. 解压并上传到Galaxy",
                "4. 重新运行workflow"
            ],
            external_resources=[
                "http://ftp.ensembl.org/pub/release-110/gtf/",
                "https://www.ensembl.org/info/data/ftp/index.html"
            ],
            estimated_time="10-15分钟",
            estimated_download_size="约50MB压缩",
            success_probability=0.9,
            impact="完全解决GTF格式问题",
            recommendation_level="★★★★☆"
        ),

        Action(
            priority=3,
            title="使用 AGAT 工具修复现有 GTF 文件",
            description="AGAT (Another Gtf/Gff Analysis Toolkit) 可以自动添加缺失的属性，如 exon_number",
            steps=[
                "1. 安装 AGAT 工具:",
                "   conda install -c bioconda agat",
                "   或 mamba install -c bioconda agat",
                "",
                "2. 修复 GTF 文件（自动添加缺失的 exon_number 等属性）:",
                "   agat_convert_sp_gxf2gxf.pl --gff genes.gtf --output genes_fixed.gtf",
                "",
                "3. 验证修复结果:",
                "   agat_sp_statistics.pl --gff genes_fixed.gtf",
                "   检查输出中的 'exon' feature 是否有 exon_number 属性",
                "",
                "4. 上传修复后的文件到 Galaxy 并重新运行 workflow"
            ],
            external_resources=[
                "https://github.com/NBISweden/AGAT",
                "https://agat.readthedocs.io/en/latest/tools/agat_convert_sp_gxf2gxf.html"
            ],
            estimated_time="5-15分钟（取决于文件大小）",
            success_probability=0.85,
            impact="修复大部分格式问题，添加缺失的标准属性",
            recommendation_level="★★★★☆",
            note="适合需要保留现有 GTF 文件内容的情况"
        ),

        Action(
            priority=4,
            title="跳过GTF处理（临时方案，不推荐）",
            description="如果不需要精确的基因注释，可以暂时跳过GTF处理继续分析",
            steps=[
                "AutoFix已自动添加 skip_filter_gtf=true 参数",
                "重新运行workflow即可",
                "注意：这会跳过GTF格式验证，可能影响结果准确性"
            ],
            estimated_time="立即生效",
            success_probability=0.5,
            impact="⚠️ 可能导致下游分析结果不准确或丢失部分注释信息",
            recommendation_level="★★☆☆☆",
            note="仅作为临时方案，强烈建议最终使用正确的GTF文件"
        )
    ],

    documentation=[
        "https://nf-co.re/clipseq/docs/usage#reference-genome-files",
        "https://www.gencodegenes.org/pages/data_format.html",
        "https://icount.readthedocs.io/en/latest/reference.html"
    ],

    auto_attempted_fix={
        'action': 'Added parameter: skip_filter_gtf=true',
        'note': '这只是临时方案，建议使用正确的GTF文件以确保结果质量'
    }
)


# ========== FASTQ 文件问题指导 ==========

FASTQ_QUALITY_ERROR_GUIDANCE = UserGuidance(
    issue_type="fastq_quality_error",
    severity="medium",
    category=IssueCategory.DATA_QUALITY,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="FASTQ文件质量值编码不正确",
    problem_details="""
FASTQ文件的质量值（Quality Score）有不同的编码格式：
• Phred+33 (Sanger, Illumina 1.8+): 最常用，范围 !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJ
• Phred+64 (Illumina 1.3-1.7): 旧版本，范围 @ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefgh

如果编码格式不匹配，会导致质量过滤、比对等步骤失败。

常见错误信息:
• "quality score out of range"
• "invalid Phred quality"
• "quality values must be in range [0-93]"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用 FastQC 检查质量值编码",
            description="FastQC 可以自动检测 FASTQ 文件的质量值编码格式",
            steps=[
                "1. 在 Galaxy 中运行 FastQC 工具",
                "2. 查看报告中的 'Basic Statistics' 部分",
                "3. 确认 'Encoding' 字段显示的编码格式",
                "4. 如果是 Phred+64，继续下一步转换"
            ],
            estimated_time="5分钟",
            success_probability=1.0,
            impact="准确识别编码格式",
            recommendation_level="★★★★★"
        ),

        Action(
            priority=2,
            title="使用 seqtk 转换质量值编码",
            description="将 Phred+64 转换为标准的 Phred+33",
            steps=[
                "1. 在 Galaxy 中搜索 'seqtk' 工具",
                "2. 选择 'seqtk seq - common transformation of FASTA/Q'",
                "3. 上传你的 FASTQ 文件",
                "4. 在参数中选择 'Convert Phred quality encoding'",
                "5. 设置 From: Phred+64, To: Phred+33",
                "6. 运行转换，使用转换后的文件重新运行 workflow"
            ],
            external_resources=[
                "https://github.com/lh3/seqtk",
                "https://usegalaxy.org/root?tool_id=toolshed.g2.bx.psu.edu/repos/iuc/seqtk/seqtk_seq/1.3.1"
            ],
            estimated_time="10-20分钟（取决于文件大小）",
            success_probability=0.95,
            impact="完全解决质量值编码问题",
            recommendation_level="★★★★★"
        ),

        Action(
            priority=3,
            title="使用 FASTX-Toolkit 转换（备选）",
            description="另一个质量值转换工具",
            steps=[
                "1. 搜索 'FASTQ Quality Converter' 工具",
                "2. 上传 FASTQ 文件",
                "3. 选择输入格式（Illumina 1.3-1.7）和输出格式（Sanger）",
                "4. 运行转换"
            ],
            estimated_time="10-20分钟",
            success_probability=0.9,
            impact="解决质量值编码问题",
            recommendation_level="★★★★☆"
        )
    ]
)


# ========== BAM 文件问题指导 ==========

BAM_FILE_CORRUPT_GUIDANCE = UserGuidance(
    issue_type="bam_file_corrupt",
    severity="high",
    category=IssueCategory.DATA_FORMAT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="BAM文件损坏或不完整",
    problem_details="""
BAM (Binary Alignment/Map) 文件是压缩的二进制格式，容易在传输过程中损坏。

常见损坏原因:
• 网络传输中断导致文件不完整
• 存储设备故障
• 压缩/解压缩过程出错
• BAM索引(.bai)文件缺失或不匹配

常见错误信息:
• "invalid BAM binary header"
• "EOF marker is absent"
• "truncated file"
• "[bam_header_read] invalid BAM binary header"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用 samtools 验证 BAM 文件完整性",
            description="在重新上传前，先在本地验证文件",
            steps=[
                "1. 在本地终端运行: samtools quickcheck your_file.bam",
                "2. 如果没有输出，文件是完整的",
                "3. 如果有错误信息，文件已损坏，需要重新生成",
                "4. 也可以运行: samtools view -H your_file.bam 查看头部信息"
            ],
            external_resources=[
                "http://www.htslib.org/doc/samtools-quickcheck.html",
                "http://www.htslib.org/doc/samtools.html"
            ],
            estimated_time="1-2分钟",
            success_probability=1.0,
            impact="确认文件是否损坏",
            recommendation_level="★★★★★"
        ),

        Action(
            priority=2,
            title="重新生成或下载 BAM 文件",
            description="如果文件损坏，需要重新获取",
            steps=[
                "1. 如果是从公共数据库下载的，重新下载:",
                "   • 使用 wget 或 curl 带 --continue 参数",
                "   • 或使用 Aspera 高速下载工具",
                "2. 如果是自己生成的:",
                "   • 重新运行比对流程（如 BWA, STAR 等）",
                "   • 确保比对完成后正确排序和索引",
                "3. 验证新文件: samtools quickcheck new_file.bam"
            ],
            estimated_time="取决于文件大小和网络速度",
            success_probability=0.95,
            impact="获得完整的BAM文件",
            recommendation_level="★★★★★"
        ),

        Action(
            priority=3,
            title="使用可靠的传输方式上传到 Galaxy",
            description="避免传输过程中再次损坏",
            steps=[
                "1. 对于大文件（>1GB），使用 FTP 上传:",
                "   • Galaxy FTP 服务器通常更稳定",
                "   • 支持断点续传",
                "2. 计算文件的 MD5 校验和:",
                "   • 本地: md5sum your_file.bam",
                "   • 上传后在 Galaxy 中验证校验和是否一致",
                "3. 上传后立即验证:",
                "   • 在 Galaxy 中运行 samtools view 查看文件"
            ],
            estimated_time="取决于文件大小和网络",
            success_probability=0.9,
            impact="确保文件完整上传",
            recommendation_level="★★★★☆"
        ),

        Action(
            priority=4,
            title="生成 BAM 索引文件(.bai)",
            description="有时只是索引文件缺失，而不是BAM损坏",
            steps=[
                "1. 在 Galaxy 中搜索 'samtools index' 工具",
                "2. 选择你的 BAM 文件",
                "3. 运行索引生成",
                "4. 重新运行原 workflow"
            ],
            estimated_time="5-10分钟",
            success_probability=0.7,
            impact="如果只是索引问题，可以快速解决",
            recommendation_level="★★★☆☆",
            note="如果BAM本身损坏，生成索引也会失败"
        )
    ]
)


# ========== VCF 文件问题指导 ==========

VCF_FORMAT_ERROR_GUIDANCE = UserGuidance(
    issue_type="vcf_format_error",
    severity="medium",
    category=IssueCategory.DATA_FORMAT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="VCF文件格式不规范",
    problem_details="""
VCF (Variant Call Format) 文件有严格的格式要求（VCF 4.0+规范）。

常见格式问题:
• 缺少必需的头部信息（##fileformat, ##contig等）
• 列数不匹配（必须有9列或更多）
• 染色体名称不一致（chr1 vs 1）
• INFO/FORMAT字段未在头部声明
• ALT等位基因格式错误

常见错误信息:
• "malformed VCF header"
• "INFO/FORMAT field not declared in header"
• "invalid variant record"
• "chromosome not found in reference"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用 VCFtools 验证 VCF 格式",
            description="VCFtools 可以检查 VCF 文件是否符合规范",
            steps=[
                "1. 在本地安装 VCFtools:",
                "   conda install -c bioconda vcftools",
                "2. 验证文件:",
                "   vcf-validator your_file.vcf",
                "3. 查看详细的错误信息",
                "4. 或使用在线验证器:",
                "   https://vcfvalidator.readthedocs.io/"
            ],
            external_resources=[
                "http://vcftools.sourceforge.net/",
                "https://vcfvalidator.readthedocs.io/",
                "https://samtools.github.io/hts-specs/VCFv4.3.pdf"
            ],
            estimated_time="5分钟",
            success_probability=1.0,
            impact="识别具体的格式问题",
            recommendation_level="★★★★★"
        ),

        Action(
            priority=2,
            title="使用 bcftools 修复常见问题",
            description="bcftools 可以自动修复一些格式问题",
            steps=[
                "1. 重新格式化 VCF:",
                "   bcftools view your_file.vcf -o fixed.vcf",
                "2. 添加缺失的头部信息:",
                "   bcftools reheader --header new_header.txt your_file.vcf",
                "3. 标准化变异表示:",
                "   bcftools norm -f reference.fa your_file.vcf -o normalized.vcf",
                "4. 排序:",
                "   bcftools sort your_file.vcf -o sorted.vcf"
            ],
            external_resources=[
                "http://samtools.github.io/bcftools/bcftools.html"
            ],
            estimated_time="10-20分钟",
            success_probability=0.8,
            impact="自动修复常见格式问题",
            recommendation_level="★★★★☆"
        ),

        Action(
            priority=3,
            title="统一染色体命名",
            description="确保染色体名称与参考基因组一致",
            steps=[
                "1. 检查参考基因组的染色体命名（chr1 或 1）",
                "2. 如果需要添加 'chr' 前缀:",
                "   awk '{if($0 !~ /^#/) print \"chr\"$0; else print $0}' input.vcf > output.vcf",
                "3. 如果需要移除 'chr' 前缀:",
                "   sed 's/^chr//' input.vcf > output.vcf",
                "4. 或使用 bcftools:",
                "   bcftools annotate --rename-chrs chr_name_conv.txt input.vcf"
            ],
            estimated_time="5-10分钟",
            success_probability=0.95,
            impact="解决染色体命名不匹配问题",
            recommendation_level="★★★★☆"
        ),

        Action(
            priority=4,
            title="从源头重新生成 VCF",
            description="如果格式问题严重，考虑重新进行变异calling",
            steps=[
                "1. 使用标准的变异calling工具:",
                "   • GATK HaplotypeCaller",
                "   • bcftools mpileup + call",
                "   • FreeBayes",
                "2. 这些工具会生成符合规范的VCF文件",
                "3. 确保使用最新版本的工具"
            ],
            estimated_time="根据数据量而定",
            success_probability=1.0,
            impact="获得完全符合规范的VCF",
            recommendation_level="★★★☆☆"
        )
    ]
)


# ========== FASTA 编码问题指导 ==========

FASTA_ENCODING_ERROR_GUIDANCE = UserGuidance(
    issue_type="fasta_encoding_error",
    severity="medium",
    category=IssueCategory.DATA_FORMAT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="FASTA文件编码或换行符问题",
    problem_details="""
FASTA文件在不同操作系统间传输时可能出现编码和换行符问题。

常见问题:
• Windows换行符（CRLF）vs Unix换行符（LF）
• 非UTF-8编码（如GBK, Latin-1）
• 序列行过长或过短
• 包含不可见字符（BOM, 空格）

常见错误信息:
• "invalid FASTA format - unexpected line endings"
• "encoding error"
• "invalid character in sequence"
• "samtools faidx failed"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="检查并转换文件编码",
            description="确保文件是UTF-8编码，Unix换行符",
            steps=[
                "1. 在Linux/Mac上检查文件编码:",
                "   file -i your_file.fasta",
                "2. 转换为UTF-8:",
                "   iconv -f GBK -t UTF-8 input.fasta > output.fasta",
                "3. 转换换行符（DOS to Unix）:",
                "   dos2unix your_file.fasta",
                "   或: sed -i 's/\\r$//' your_file.fasta"
            ],
            estimated_time="1-2分钟",
            success_probability=0.95,
            impact="解决编码和换行符问题",
            recommendation_level="★★★★★"
        ),

        Action(
            priority=2,
            title="使用 seqtk 重新格式化",
            description="seqtk 可以自动处理编码和格式问题",
            steps=[
                "1. 安装 seqtk:",
                "   conda install -c bioconda seqtk",
                "2. 重新格式化 FASTA:",
                "   seqtk seq -l 80 input.fasta > output.fasta",
                "   (-l 80 表示每行80个碱基)",
                "3. 验证输出文件:",
                "   head output.fasta"
            ],
            external_resources=[
                "https://github.com/lh3/seqtk"
            ],
            estimated_time="5分钟",
            success_probability=0.9,
            impact="标准化FASTA格式",
            recommendation_level="★★★★☆"
        ),

        Action(
            priority=3,
            title="从官方源重新下载",
            description="如果是参考基因组，从官方源下载更可靠",
            steps=[
                "1. UCSC Genome Browser:",
                "   http://hgdownload.soe.ucsc.edu/downloads.html",
                "2. Ensembl:",
                "   http://ftp.ensembl.org/pub/current_fasta/",
                "3. NCBI RefSeq:",
                "   https://ftp.ncbi.nlm.nih.gov/refseq/",
                "4. 这些源提供标准格式的FASTA文件"
            ],
            estimated_time="10-30分钟（下载时间）",
            success_probability=1.0,
            impact="获得标准格式的文件",
            recommendation_level="★★★★★"
        )
    ]
)


STAR_MEMORY_ERROR_GUIDANCE = UserGuidance(
    issue_type="star_memory_error",
    severity="high",
    category=IssueCategory.RESOURCE_INSUFFICIENT,
    fix_strategy=FixStrategy.AUTO_FIXABLE,  # 大部分情况可自动修复

    problem_summary="STAR索引生成内存不足",
    problem_details="""
STAR (Spliced Transcripts Alignment to a Reference) 工具在生成基因组索引时
需要大量内存。对于人类基因组，通常需要30-35GB内存。

错误代码 110 通常表示内存耗尽（OOM - Out of Memory）。

AutoFix已自动将STAR内存配额增加到32GB，这应该能解决大部分情况。
如果问题仍然存在，可能需要使用预构建的索引。
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用AutoFix增加的内存配额（已完成）",
            description="AutoFix已自动将STAR内存增加到32GB",
            steps=[
                "✅ 已添加参数: star_index_max_memory = 32GB",
                "重新运行workflow即可",
                "对于人类基因组，32GB通常足够"
            ],
            estimated_time="已自动完成",
            success_probability=0.9,
            impact="解决90%的STAR内存问题",
            recommendation_level="★★★★★"
        ),

        Action(
            priority=2,
            title="使用预构建的STAR索引（如果32GB仍不够）",
            description="下载预先构建好的STAR索引，完全避免现场生成",
            steps=[
                "1. 从iGenomes下载预构建索引:",
                "   https://support.illumina.com/sequencing/sequencing_software/igenome.html",
                "2. 或从STAR官方获取:",
                "   https://github.com/alexdobin/STAR/tree/master/genomes",
                "3. 解压并上传到Galaxy",
                "4. 在workflow参数中使用预构建索引"
            ],
            external_resources=[
                "https://support.illumina.com/sequencing/sequencing_software/igenome.html",
                "https://github.com/alexdobin/STAR"
            ],
            estimated_time="20-30分钟",
            estimated_download_size="约30GB（人类基因组）",
            success_probability=0.99,
            impact="完全避免STAR索引生成，节省时间和内存",
            recommendation_level="★★★★☆"
        )
    ],

    documentation=[
        "https://github.com/alexdobin/STAR/blob/master/doc/STARmanual.pdf",
        "https://nf-co.re/clipseq/docs/usage#star-index"
    ],

    auto_attempted_fix={
        'action': 'Increased STAR memory to 32GB',
        'params': {'star_index_max_memory': '32000000000'}
    }
)


MISSING_REFERENCE_GENOME_GUIDANCE = UserGuidance(
    issue_type="missing_reference_genome",
    severity="high",
    category=IssueCategory.MISSING_REFERENCE,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="缺少参考基因组文件",
    problem_details="""
Workflow需要参考基因组（FASTA文件），但未提供或无法访问。

参考基因组是序列比对的基础，必须提供正确的基因组文件。
""",

    recommended_actions=[
        Action(
            priority=1,
            title="从官方源下载参考基因组",
            description="获取高质量、广泛使用的参考基因组",
            steps=[
                "人类基因组 (GRCh38/hg38):",
                "  下载: https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_44/GRCh38.primary_assembly.genome.fa.gz",
                "",
                "小鼠基因组 (GRCm39):",
                "  下载: https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_M33/GRCm39.primary_assembly.genome.fa.gz",
                "",
                "下载后:",
                "1. 解压缩文件（gunzip *.fa.gz）",
                "2. 在Galaxy中上传FASTA文件",
                "3. 在workflow参数中选择该文件"
            ],
            external_resources=[
                "https://www.gencodegenes.org/",
                "https://ftp.ebi.ac.uk/pub/databases/gencode/",
                "https://www.ncbi.nlm.nih.gov/genome/"
            ],
            estimated_time="15-30分钟",
            estimated_download_size="约900MB压缩（人类基因组），解压后约3GB",
            success_probability=0.95,
            impact="提供workflow所需的基础数据",
            recommendation_level="★★★★★"
        )
    ],

    documentation=[
        "https://www.gencodegenes.org/pages/data_access.html",
        "https://nf-co.re/clipseq/docs/usage#reference-genome"
    ]
)


# ============================================================================
# Phase 1 Day 1: 新增文件格式相关 User Guidance
# ============================================================================

BED_FORMAT_ERROR_GUIDANCE = UserGuidance(
    issue_type="bed_format_error",
    severity="high",
    category=IssueCategory.DATA_FORMAT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="BED文件格式错误，导致基因组区域分析失败",
    problem_details="""
BED (Browser Extensible Data) 文件格式不符合规范，导致工具无法解析。

**最常见问题**：
1. **列数不对** - 标准BED格式至少需要3列（chr, start, end），BED6需要6列，BED12需要12列
   错误示例: 只有2列数据

2. **染色体名称不匹配** - 染色体名称必须与参考基因组一致
   错误示例: "chr1" vs "1", "chrM" vs "MT"

3. **坐标错误** - start必须小于end，坐标必须是非负整数
   错误示例: start=1000, end=500

4. **格式混乱** - 包含header行、注释行未正确标记、使用Tab vs 空格分隔

**重要**: BED文件是0-based坐标系统，与GTF/GFF的1-based不同。
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用UCSC Genome Browser下载标准BED文件（最推荐）",
            description="UCSC是最权威的基因组数据源之一，提供标准的BED格式文件",
            steps=[
                "1. 访问 UCSC Table Browser: https://genome.ucsc.edu/cgi-bin/hgTables",
                "2. 选择物种（如Human）和基因组版本（如hg38）",
                "3. 选择track（如'GENCODE v44'）",
                "4. 输出格式选择'BED - browser extensible data'",
                "5. 点击'get output'下载文件",
                "6. 在Galaxy中上传新的BED文件",
                "7. 重新运行workflow"
            ],
            estimated_time="5-10分钟",
            success_probability=0.95,
            impact="获取标准格式的BED文件，确保兼容性",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="使用bedtools验证和修复BED文件",
            description="bedtools是专业的BED文件处理工具，可以自动验证和修复格式问题",
            steps=[
                "1. 安装bedtools:",
                "   conda install -c bioconda bedtools",
                "",
                "2. 验证BED文件格式:",
                "   bedtools --version  # 确保安装成功",
                "   head -20 your_file.bed  # 检查前20行",
                "",
                "3. 排序BED文件:",
                "   bedtools sort -i your_file.bed > sorted.bed",
                "",
                "4. 合并重叠区域（如果需要）:",
                "   bedtools merge -i sorted.bed > merged.bed",
                "",
                "5. 验证染色体名称:",
                "   cut -f1 your_file.bed | sort | uniq",
                "   # 确保与参考基因组一致",
                "",
                "6. 上传修复后的文件到Galaxy"
            ],
            estimated_time="10-15分钟",
            success_probability=0.85,
            impact="修复大部分格式问题，标准化BED文件",
            recommendation_level="★★★★☆"
        ),
        Action(
            priority=3,
            title="转换GTF/GFF到BED格式",
            description="如果有GTF/GFF文件，可以转换为标准BED格式",
            steps=[
                "如果您有GTF/GFF文件，可以转换为BED:",
                "",
                "使用bedtools:",
                "  bedtools gtf2bed < genes.gtf > genes.bed",
                "",
                "或使用AGAT:",
                "  agat_convert_sp_gff2bed.pl --gff genes.gtf -o genes.bed",
                "",
                "或使用Python脚本:",
                "  # 简单的GTF到BED转换",
                "  import sys",
                "  for line in open('genes.gtf'):",
                "      if line.startswith('#'): continue",
                "      fields = line.strip().split('\\t')",
                "      print(f\"{fields[0]}\\t{fields[3]}\\t{fields[4]}\")"
            ],
            estimated_time="5分钟",
            success_probability=0.9,
            impact="从已有的annotation文件生成BED",
            recommendation_level="★★★☆☆"
        ),
    ]
)


GFF_FORMAT_ERROR_GUIDANCE = UserGuidance(
    issue_type="gff_format_error",
    severity="high",
    category=IssueCategory.DATA_FORMAT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="GFF/GFF3文件格式错误，导致基因注释解析失败",
    problem_details="""
GFF (General Feature Format) 文件格式不符合规范。

**最常见问题**：
1. **缺少必需字段** - GFF需要9列：seqid, source, type, start, end, score, strand, phase, attributes
2. **父子关系错误** - GFF3的Parent字段引用不存在的ID
3. **属性格式错误** - GFF3属性必须是"key=value"，用分号分隔
4. **版本混淆** - GFF2 vs GFF3 格式差异

**GFF3 vs GTF**:
- GFF3: 属性用"=" (例如: ID=gene001)
- GTF: 属性用空格和引号 (例如: gene_id "ENSG00000...")
""",

    recommended_actions=[
        Action(
            priority=1,
            title="从Ensembl下载标准GFF3文件",
            description="Ensembl提供权威的、标准化的GFF3文件，数据质量有保证",
            steps=[
                "1. 访问 Ensembl FTP: http://ftp.ensembl.org/pub/",
                "2. 导航到对应物种，例如:",
                "   release-110/gff3/homo_sapiens/",
                "3. 下载 Homo_sapiens.GRCh38.110.gff3.gz",
                "4. 解压: gunzip Homo_sapiens.GRCh38.110.gff3.gz",
                "5. 上传到Galaxy",
                "6. 重新运行workflow"
            ],
            estimated_time="10-15分钟",
            success_probability=0.95,
            impact="获取标准的GFF3文件",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="使用AGAT工具验证和修复GFF文件",
            description="AGAT是专业的GFF/GTF处理工具，可以自动修复格式和结构问题",
            steps=[
                "1. 安装AGAT:",
                "   conda install -c bioconda agat",
                "",
                "2. 验证GFF文件:",
                "   agat_sp_statistics.pl --gff your_file.gff",
                "",
                "3. 修复常见问题:",
                "   agat_convert_sp_gxf2gxf.pl --gff your_file.gff \\",
                "       --output fixed.gff3",
                "",
                "4. 检查父子关系:",
                "   agat_sp_fix_features_locations_duplicated.pl \\",
                "       --gff fixed.gff3 --output final.gff3",
                "",
                "5. 验证修复结果:",
                "   agat_sp_statistics.pl --gff final.gff3"
            ],
            estimated_time="10-20分钟",
            success_probability=0.85,
            impact="自动修复大部分GFF格式问题",
            recommendation_level="★★★★☆"
        ),
        Action(
            priority=3,
            title="转换GTF到GFF3格式",
            description="如果有GTF文件，可以转换为GFF3格式",
            steps=[
                "如果您有GTF文件，可以转换:",
                "",
                "使用AGAT:",
                "  agat_convert_sp_gff2gff.pl --gtf genes.gtf \\",
                "      --output genes.gff3",
                "",
                "使用gffread:",
                "  gffread genes.gtf -o- > genes.gff3"
            ],
            estimated_time="5分钟",
            success_probability=0.9,
            impact="从GTF生成GFF3文件",
            recommendation_level="★★★☆☆"
        ),
    ]
)


FASTA_FORMAT_ERROR_GUIDANCE = UserGuidance(
    issue_type="fasta_format_error",
    severity="high",
    category=IssueCategory.DATA_FORMAT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="FASTA序列文件格式错误",
    problem_details="""
FASTA序列文件格式不规范。

**最常见问题**：
1. **缺少标题行** - 每条序列必须以">"开头的标题行
2. **序列中有非法字符** - DNA应只包含ATCGN，蛋白质只包含20种氨基酸
3. **换行符问题** - 序列行过长或使用Windows换行符(CRLF)
4. **重复的序列ID** - 序列名称必须唯一
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用seqkit验证和修复FASTA文件",
            description="seqkit是强大的FASTA处理工具，可以验证和修复序列格式问题",
            steps=[
                "1. 安装seqkit:",
                "   conda install -c bioconda seqkit",
                "",
                "2. 验证FASTA格式:",
                "   seqkit stats your_sequences.fasta",
                "",
                "3. 检查非法字符:",
                "   seqkit seq --validate-seq your_sequences.fasta",
                "",
                "4. 重新格式化（每行60个字符）:",
                "   seqkit seq -w 60 your_sequences.fasta > formatted.fasta",
                "",
                "5. 去除重复序列:",
                "   seqkit rmdup -s < your_sequences.fasta > dedup.fasta",
                "",
                "6. 标准化序列名（如果需要）:",
                "   seqkit replace -p ' .+' your_sequences.fasta > clean.fasta"
            ],
            estimated_time="5-10分钟",
            success_probability=0.9,
            impact="修复FASTA格式问题",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="从NCBI/Ensembl重新下载参考序列",
            description="从官方数据源获取标准格式的参考序列文件",
            steps=[
                "NCBI RefSeq:",
                "  访问: https://www.ncbi.nlm.nih.gov/genome/",
                "",
                "Ensembl:",
                "  访问: http://ftp.ensembl.org/pub/release-110/fasta/",
                "",
                "下载对应物种的基因组FASTA文件"
            ],
            estimated_time="10-20分钟",
            success_probability=0.95,
            impact="获取标准的参考序列",
            recommendation_level="★★★★☆"
        ),
    ]
)


# ============================================================================
# Phase 1 Day 1: 数据质量相关 User Guidance
# ============================================================================

FASTQ_ENCODING_ERROR_GUIDANCE = UserGuidance(
    issue_type="fastq_encoding_error",
    severity="high",
    category=IssueCategory.DATA_FORMAT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="FASTQ质量编码错误（Phred33 vs Phred64）",
    problem_details="""
FASTQ文件使用了错误的质量编码格式。

**常见编码**：
- **Phred+33** (Sanger, Illumina 1.8+): ASCII 33-126, 质量值0-93
- **Phred+64** (Illumina 1.3-1.7): ASCII 64-126, 质量值0-62

**问题表现**：
- 工具报错"Invalid quality score"
- 质量值超出预期范围
- ASCII字符不在有效范围内
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用FastQC检测编码格式",
            description="FastQC可以自动检测FASTQ文件的质量编码格式",
            steps=[
                "1. 运行FastQC:",
                "   fastqc your_reads.fastq.gz",
                "",
                "2. 查看报告中的'Encoding'字段:",
                "   - Sanger / Illumina 1.9 → Phred+33",
                "   - Illumina 1.5 → Phred+64",
                "",
                "3. 根据检测结果选择正确的编码参数"
            ],
            estimated_time="5分钟",
            success_probability=0.95,
            impact="确认正确的质量编码格式",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="使用seqtk转换质量编码",
            description="将非标准的质量编码转换为Phred+33标准格式",
            steps=[
                "1. 安装seqtk:",
                "   conda install -c bioconda seqtk",
                "",
                "2. Phred64 → Phred33:",
                "   seqtk seq -Q64 -V old.fastq > new.fastq",
                "",
                "3. 验证转换结果:",
                "   fastqc new.fastq"
            ],
            estimated_time="10-15分钟（取决于文件大小）",
            success_probability=0.9,
            impact="转换为标准Phred+33编码",
            recommendation_level="★★★★☆"
        ),
    ]
)


DUPLICATE_READS_HIGH_GUIDANCE = UserGuidance(
    issue_type="duplicate_reads_high",
    severity="medium",
    category=IssueCategory.DATA_QUALITY,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="测序数据重复率过高",
    problem_details="""
PCR重复率超过正常范围，可能影响下游分析准确性。

**正常重复率**：
- DNA-seq: < 20%
- RNA-seq: < 30%
- ChIP-seq: < 40%
- ATAC-seq: < 50%

**可能原因**：
1. PCR循环数过多
2. 起始DNA/RNA量太少
3. 测序深度过高
4. 文库复杂度低
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用Picard MarkDuplicates标记重复",
            description="标记PCR重复reads，改善数据质量",
            steps=[
                "1. 标记重复reads:",
                "   picard MarkDuplicates \\",
                "       I=aligned.bam \\",
                "       O=marked.bam \\",
                "       M=metrics.txt \\",
                "       REMOVE_DUPLICATES=false",
                "",
                "2. 查看重复率统计:",
                "   cat metrics.txt",
                "",
                "3. 决定是否移除重复:",
                "   - DNA-seq: 建议移除",
                "   - RNA-seq: 通常保留",
                "   - ChIP-seq: 根据实验设计决定"
            ],
            estimated_time="20-40分钟",
            success_probability=0.95,
            impact="标记和统计重复reads",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="优化实验设计（预防措施）",
            description="从源头减少PCR重复，提高文库质量",
            steps=[
                "下次实验时:",
                "1. 增加起始DNA/RNA量",
                "2. 减少PCR循环数",
                "3. 使用UMI（Unique Molecular Identifiers）",
                "4. 优化文库构建protocol"
            ],
            estimated_time="N/A（用于未来实验）",
            success_probability=0.8,
            impact="从源头降低重复率",
            recommendation_level="★★★☆☆"
        ),
    ]
)


LOW_MAPPING_RATE_GUIDANCE = UserGuidance(
    issue_type="low_mapping_rate",
    severity="high",
    category=IssueCategory.DATA_QUALITY,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="比对率过低，大部分reads无法比对到参考基因组",
    problem_details="""
比对率显著低于预期值。

**正常比对率**：
- DNA-seq: > 95%
- RNA-seq: > 70-80%
- ChIP-seq: > 70%

**可能原因**：
1. 参考基因组不匹配（物种错误、版本错误）
2. 样本污染（细菌、真菌等）
3. 数据质量差（adapter未去除、质量值低）
4. rRNA污染（RNA-seq）
""",

    recommended_actions=[
        Action(
            priority=1,
            title="检查参考基因组是否正确",
            description="确认参考基因组与样本物种匹配",
            steps=[
                "1. 确认物种和基因组版本:",
                "   - 样本物种 vs 参考基因组",
                "   - hg19 vs hg38 vs GRCh37 vs GRCh38",
                "",
                "2. 如果不确定，可以:",
                "   - 用BLAST比对部分unmapped reads",
                "   - 查看实验记录确认物种",
                "",
                "3. 更换正确的参考基因组重新比对"
            ],
            estimated_time="5-10分钟（分析）+ 30-60分钟（重新比对）",
            success_probability=0.9,
            impact="使用正确的参考基因组",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="使用Kraken2检测污染",
            description="使用分类学工具识别样本中的污染来源",
            steps=[
                "1. 安装Kraken2:",
                "   conda install -c bioconda kraken2",
                "",
                "2. 下载数据库（或使用预构建的）:",
                "   kraken2-build --download-taxonomy --db kraken_db",
                "",
                "3. 对unmapped reads进行分类:",
                "   kraken2 --db kraken_db \\",
                "       --report report.txt \\",
                "       unmapped.fastq",
                "",
                "4. 查看report.txt找出污染源",
                "",
                "5. 根据结果决定:",
                "   - 过滤污染reads",
                "   - 或重新准备样本"
            ],
            estimated_time="30-60分钟",
            success_probability=0.85,
            impact="检测并去除污染",
            recommendation_level="★★★★☆"
        ),
        Action(
            priority=3,
            title="检查数据质量并重新trim",
            description="过滤低质量reads和接头序列",
            steps=[
                "1. 运行FastQC查看质量:",
                "   fastqc unmapped.fastq",
                "",
                "2. 检查是否有adapter残留",
                "",
                "3. 使用Trim Galore重新修剪:",
                "   trim_galore --fastqc \\",
                "       --illumina \\",
                "       input.fastq.gz",
                "",
                "4. 用修剪后的reads重新比对"
            ],
            estimated_time="20-40分钟",
            success_probability=0.7,
            impact="提高reads质量",
            recommendation_level="★★★☆☆"
        ),
    ]
)


# ============================================================================
# Day 2: 资源问题 & 工具特定错误指导
# ============================================================================

MEMORY_OOM_KILLER_GUIDANCE = UserGuidance(
    issue_type="memory_oom_killer",
    severity="high",
    category=IssueCategory.RESOURCE_INSUFFICIENT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="内存不足导致进程被OOM Killer杀死",
    problem_details="""
Linux OOM (Out of Memory) Killer 在系统内存耗尽时会自动终止内存占用最高的进程。

**常见原因**：
1. **工作流内存配置过低** - process.memory 设置不足
2. **输入数据过大** - FASTQ/BAM文件超出预期
3. **工具内存泄漏** - 某些生信工具版本存在内存泄漏
4. **多任务并发** - 多个任务同时运行导致内存峰值
5. **AWS Batch实例类型不当** - 选择了低内存实例

**典型报错**：
- "Killed" (exit code 137)
- "Out of memory"
- "Cannot allocate memory"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="增加Nextflow进程内存配置（推荐优先尝试）",
            description="通过增加内存配额解决OOM问题",
            steps=[
                "1. 查看失败任务的内存使用: cat workflow-trace.txt | grep FAILED",
                "2. 找到内存不足的进程名称（如 STAR_ALIGN）",
                "3. 在Galaxy workflow参数中增加内存:",
                "   - 找到 'process_memory' 或 'star_memory' 等参数",
                "   - 当前值如果是 '16.GB'，改为 '32.GB' 或 '64.GB'",
                "4. 重新运行workflow",
                "5. 注意: 确保AWS Batch计算环境支持更大内存实例",
            ],
            estimated_time="5-10分钟",
            success_probability=0.90,
            impact="解决大多数OOM问题，适用于数据量大的场景",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="优化AWS Batch实例类型（适合持续高内存需求）",
            description="使用高内存实例类型（如r5系列）来运行大内存任务",
            steps=[
                "1. 登录AWS Batch控制台",
                "2. 检查当前Compute Environment使用的实例类型",
                "3. 如果是 r5.xlarge (32GB)，升级为:",
                "   - r5.2xlarge (64GB) - 中等数据",
                "   - r5.4xlarge (128GB) - 大规模数据",
                "   - r5.8xlarge (256GB) - 超大数据",
                "4. 更新Compute Environment配置",
                "5. 等待新实例类型生效（约5分钟）",
                "6. 重新运行workflow",
            ],
            estimated_time="15-20分钟",
            success_probability=0.95,
            impact="彻底解决内存问题，但会增加AWS成本",
            recommendation_level="★★★★☆"
        ),
        Action(
            priority=3,
            title="使用数据分片策略（适合超大文件）",
            description="将大文件拆分成小文件分批处理，降低内存需求",
            steps=[
                "1. 识别导致OOM的大文件（通常是 >50GB 的FASTQ/BAM）",
                "2. 使用split命令分割文件:",
                "   split -l 40000000 input.fastq input_part_",
                "3. 分别处理每个分片",
                "4. 使用samtools merge或cat合并结果",
                "5. 这种方法可以在低内存实例上处理超大文件",
            ],
            estimated_time="30-60分钟",
            success_probability=0.80,
            impact="绕过内存限制，但增加处理复杂度",
            recommendation_level="★★★☆☆"
        ),
    ]
)


DISK_QUOTA_EXCEEDED_GUIDANCE = UserGuidance(
    issue_type="disk_quota_exceeded",
    severity="high",
    category=IssueCategory.RESOURCE_INSUFFICIENT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="磁盘空间不足导致workflow失败",
    problem_details="""
工作目录或临时目录磁盘空间耗尽，导致无法写入中间结果或最终输出。

**常见原因**：
1. **中间文件累积** - Nextflow工作目录未清理
2. **输出文件过大** - BAM/CRAM文件占用大量空间
3. **AWS EBS卷容量不足** - 默认20GB卷太小
4. **临时文件未删除** - /tmp目录被占满

**典型报错**：
- "No space left on device"
- "Disk quota exceeded"
- "Cannot write to disk"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="清理Nextflow工作目录（快速释放空间）",
            description="删除Nextflow临时文件，释放磁盘空间",
            steps=[
                "1. 进入Galaxy jobs目录:",
                "   cd database/jobs_directory/nextflow_workflows/",
                "2. 查看各workflow占用空间:",
                "   du -sh workflow_*/ | sort -h",
                "3. 删除已完成workflow的工作目录:",
                "   nextflow clean -f -k  # 保留最新的",
                "   # 或手动删除: rm -rf workflow_XXX/work/",
                "4. 重新运行当前workflow",
            ],
            estimated_time="5分钟",
            success_probability=0.85,
            impact="快速释放空间，适合临时解决",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="扩展AWS EBS卷容量（长期解决方案）",
            description="增加AWS EBS存储卷大小，从根本上解决空间不足问题",
            steps=[
                "1. 登录AWS EC2控制台",
                "2. 找到运行Galaxy的实例",
                "3. 选择附加的EBS卷（通常是 /dev/sda1）",
                "4. 点击 Actions → Modify Volume",
                "5. 增加容量: 20GB → 100GB 或 200GB",
                "6. 等待卷修改完成（约5分钟）",
                "7. SSH到实例，扩展文件系统:",
                "   sudo growpart /dev/nvme0n1 1",
                "   sudo resize2fs /dev/nvme0n1p1",
                "8. 验证: df -h",
            ],
            estimated_time="15-20分钟",
            success_probability=0.98,
            impact="彻底解决磁盘空间问题",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=3,
            title="配置AWS S3作为工作目录（适合大规模数据）",
            description="使用S3无限存储空间，避免本地磁盘限制",
            steps=[
                "1. 修改nextflow.config:",
                "   workDir = 's3://your-bucket/nextflow-work'",
                "2. 确保EC2实例有S3访问权限（IAM Role）",
                "3. 重新运行workflow",
                "4. S3存储几乎无限，且自动清理旧数据",
            ],
            estimated_time="10分钟",
            success_probability=0.90,
            impact="利用S3无限存储，避免本地磁盘限制",
            recommendation_level="★★★★☆"
        ),
    ]
)


CPU_TIMEOUT_GUIDANCE = UserGuidance(
    issue_type="cpu_timeout",
    severity="medium",
    category=IssueCategory.RESOURCE_INSUFFICIENT,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="任务执行超时导致被强制终止",
    problem_details="""
任务运行时间超过配置的最大时间限制（time limit），被系统强制终止。

**常见原因**：
1. **CPU核心数不足** - 单核运行多线程工具
2. **数据量超预期** - 大FASTQ文件处理时间长
3. **超时配置过严格** - 默认1小时不够用
4. **AWS Batch任务超时** - Job Definition中的timeout设置

**典型报错**：
- "DUE TO TIME LIMIT"
- "TIMEOUT"
- "Execution cancelled -- Job runtime exceeded"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="增加任务超时时间（简单有效）",
            description="延长超时限制，给任务更多时间完成",
            steps=[
                "1. 在Galaxy workflow参数中找到 'max_time' 或 'time' 参数",
                "2. 当前值如果是 '1.h'，改为 '4.h' 或 '8.h'",
                "3. 对于特别耗时的任务（如变异检测），可以设置 '24.h'",
                "4. 重新运行workflow",
            ],
            estimated_time="5分钟",
            success_probability=0.90,
            impact="解决大多数超时问题",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="增加CPU核心数加速处理",
            description="使用更多CPU核心并行处理，缩短运行时间",
            steps=[
                "1. 在workflow参数中找到 'cpus' 或 'process_cpus' 参数",
                "2. 当前值如果是 '2'，改为 '8' 或 '16'",
                "3. 确保AWS Batch实例类型支持更多核心:",
                "   - c5.2xlarge (8核)",
                "   - c5.4xlarge (16核)",
                "4. 重新运行workflow",
            ],
            estimated_time="10分钟",
            success_probability=0.85,
            impact="显著加速任务，减少运行时间",
            recommendation_level="★★★★☆"
        ),
    ]
)


STAR_ALIGNMENT_ERROR_GUIDANCE = UserGuidance(
    issue_type="star_alignment_error",
    severity="high",
    category=IssueCategory.TOOL_SPECIFIC,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="STAR比对工具运行失败",
    problem_details="""
STAR (Spliced Transcripts Alignment to a Reference) 是RNA-seq数据比对的常用工具，可能因索引、内存或参数问题失败。

**常见错误类型**：
1. **索引不匹配** - Genome index版本与STAR版本不兼容
2. **内存不足** - Human genome需要至少32GB RAM
3. **输入文件损坏** - FASTQ文件不完整
4. **参数冲突** - --outSAMtype与--quantMode冲突

**典型报错**：
- "Genome index is too old"
- "not enough memory to allocate"
- "BAM EOF marker is missing"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="使用正确版本的STAR索引（推荐）",
            description="确保STAR索引版本与STAR程序版本匹配",
            steps=[
                "1. 检查当前STAR版本: STAR --version",
                "2. 从iGenomes或UCSC下载匹配的索引:",
                "   - STAR 2.7.x → 使用最新索引",
                "   - STAR 2.5.x → 使用旧版索引",
                "3. 在workflow参数中指定索引路径:",
                "   star_index = '/path/to/correct/star_index'",
                "4. 重新运行workflow",
            ],
            estimated_time="10-30分钟（下载索引需时间）",
            success_probability=0.95,
            impact="解决版本不兼容问题",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="增加STAR内存配置",
            description="为STAR分配足够的内存（人类基因组需要至少32GB）",
            steps=[
                "1. Human genome比对至少需要32GB RAM",
                "2. 在workflow参数中设置:",
                "   star_memory = '64.GB'  # 推荐",
                "3. 确保AWS Batch使用高内存实例（r5.2xlarge或更大）",
                "4. 重新运行workflow",
            ],
            estimated_time="5分钟",
            success_probability=0.90,
            impact="避免OOM错误",
            recommendation_level="★★★★☆"
        ),
        Action(
            priority=3,
            title="调整STAR参数避免冲突",
            description="检查并修正冲突的STAR参数组合",
            steps=[
                "1. 检查错误日志中的参数冲突提示",
                "2. 常见修复:",
                "   - 移除 --quantMode 如果不需要基因定量",
                "   - 使用 --outSAMtype BAM SortedByCoordinate（推荐）",
                "   - 添加 --limitBAMsortRAM 限制排序内存",
                "3. 在workflow的extra_star_params中添加修正参数",
            ],
            estimated_time="10分钟",
            success_probability=0.80,
            recommendation_level="★★★☆☆"
        ),
    ]
)


BOWTIE2_ALIGNMENT_ERROR_GUIDANCE = UserGuidance(
    issue_type="bowtie2_alignment_error",
    severity="medium",
    category=IssueCategory.TOOL_SPECIFIC,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="Bowtie2比对工具运行失败",
    problem_details="""
Bowtie2是DNA序列比对工具，常用于ChIP-seq、ATAC-seq等实验。

**常见问题**：
1. **索引文件缺失** - .bt2索引文件不完整
2. **配对端FASTQ不匹配** - R1和R2行数不一致
3. **输入格式错误** - 期望FASTQ但收到FASTA

**典型报错**：
- "Could not locate index file"
- "Paired reads have different names"
- "Invalid quality value"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="验证和重新构建Bowtie2索引",
            description="确保Bowtie2索引文件完整且版本兼容",
            steps=[
                "1. 检查索引文件是否完整（需要6个.bt2文件）:",
                "   ls genome.*.bt2  # 应该有 .1.bt2, .2.bt2, ..., .rev.2.bt2",
                "2. 如果缺失，重新构建索引:",
                "   bowtie2-build genome.fa genome",
                "3. 在workflow中指定正确索引路径",
                "4. 重新运行workflow",
            ],
            estimated_time="20-40分钟（构建索引需时间）",
            success_probability=0.95,
            impact="解决索引问题",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="修复配对端FASTQ文件",
            description="确保R1和R2文件正确配对且格式一致",
            steps=[
                "1. 检查R1和R2文件行数:",
                "   wc -l sample_R1.fastq sample_R2.fastq",
                "2. 如果不一致，使用repair.sh修复:",
                "   repair.sh in1=R1.fq in2=R2.fq out1=fixed_R1.fq out2=fixed_R2.fq",
                "3. 重新上传修复后的FASTQ文件",
                "4. 重新运行workflow",
            ],
            estimated_time="15-30分钟",
            success_probability=0.90,
            impact="确保配对端数据一致性",
            recommendation_level="★★★★☆"
        ),
    ]
)


SAMTOOLS_SORT_ERROR_GUIDANCE = UserGuidance(
    issue_type="samtools_sort_error",
    severity="medium",
    category=IssueCategory.TOOL_SPECIFIC,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="Samtools排序操作失败",
    problem_details="""
Samtools sort用于对BAM文件按坐标或读名排序，可能因内存或临时文件问题失败。

**常见问题**：
1. **内存不足** - 大BAM文件需要更多RAM
2. **临时目录满** - /tmp空间耗尽
3. **损坏的BAM** - 输入BAM文件不完整

**典型报错**：
- "failed to write"
- "No space left on device"
- "truncated file"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="增加排序内存并指定临时目录",
            description="为samtools sort分配足够的内存和临时空间",
            steps=[
                "1. 在workflow参数中设置samtools内存:",
                "   samtools_sort_memory = '8G'  # 每线程内存",
                "2. 指定有足够空间的临时目录:",
                "   在nextflow.config中添加:",
                "   process {",
                "       withName: SAMTOOLS_SORT {",
                "           clusterOptions = '-T /large/tmp'",
                "       }",
                "   }",
                "3. 重新运行workflow",
            ],
            estimated_time="10分钟",
            success_probability=0.90,
            impact="避免内存和磁盘问题",
            recommendation_level="★★★★★"
        ),
    ]
)


PICARD_VALIDATION_ERROR_GUIDANCE = UserGuidance(
    issue_type="picard_validation_error",
    severity="low",
    category=IssueCategory.TOOL_SPECIFIC,
    fix_strategy=FixStrategy.AUTO_FIXABLE,

    problem_summary="Picard验证发现BAM文件格式问题",
    problem_details="""
Picard ValidateSamFile工具检测到BAM文件不符合SAM规范，但通常不影响下游分析。

**常见警告**：
1. **MISSING_TAG_NM** - 缺少NM标签（编辑距离）
2. **INVALID_QUALITY_FORMAT** - 质量值超出范围
3. **MATE_NOT_FOUND** - 配对端reads未找到

**注意**: 这些通常是警告而非致命错误。
""",

    recommended_actions=[
        Action(
            priority=1,
            title="跳过严格验证（推荐用于分析流程）",
            description="禁用Picard的严格验证，允许非致命性警告通过",
            steps=[
                "1. 在workflow参数中禁用Picard严格验证:",
                "   skip_picard_validation = true",
                "2. 或降低验证级别:",
                "   picard_validation_stringency = 'LENIENT'",
                "3. 重新运行workflow",
            ],
            estimated_time="2分钟",
            success_probability=0.95,
            impact="跳过非关键验证，加速流程",
            recommendation_level="★★★★★"
        ),
    ]
)


# ============================================================================
# Day 3: AWS Batch 问题指导
# ============================================================================

AWS_BATCH_PERMISSION_DENIED_GUIDANCE = UserGuidance(
    issue_type="aws_batch_permission_denied",
    severity="high",
    category=IssueCategory.INFRASTRUCTURE,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="AWS Batch权限不足导致任务无法提交或执行",
    problem_details="""
AWS Batch任务执行需要正确的IAM权限，包括提交任务、访问S3、拉取Docker镜像等。

**常见权限问题**：
1. **任务提交失败** - 缺少batch:SubmitJob权限
2. **S3访问拒绝** - 缺少s3:GetObject权限
3. **ECR镜像拉取失败** - 缺少ecr:GetAuthorizationToken权限
4. **日志写入失败** - 缺少logs:CreateLogStream权限

**典型报错**：
- "AccessDenied"
- "User is not authorized to perform"
- "Permission denied"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="检查并更新IAM角色权限（推荐）",
            description="为AWS Batch实例角色添加必要的S3、ECR等权限",
            steps=[
                "1. 登录AWS IAM控制台",
                "2. 找到Batch任务使用的IAM角色（通常是 ecsTaskExecutionRole）",
                "3. 确保附加了以下托管策略:",
                "   - AmazonEC2ContainerServiceforEC2Role",
                "   - AmazonS3ReadOnlyAccess（或自定义S3权限）",
                "   - CloudWatchLogsFullAccess",
                "4. 如果使用ECR，添加自定义策略:",
                "   允许 ecr:GetAuthorizationToken, ecr:BatchGetImage 等操作",
                "5. 等待权限生效（约1分钟）",
                "6. 重新运行workflow",
            ],
            estimated_time="10-15分钟",
            success_probability=0.95,
            impact="解决所有权限相关问题",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="使用预配置的IAM角色模板",
            description="使用经过验证的IAM角色配置模板",
            steps=[
                "1. 在项目文档中找到推荐的IAM角色配置",
                "2. 使用CloudFormation模板快速创建",
                "3. 更新Batch Compute Environment使用新角色",
                "4. 重新运行workflow",
            ],
            estimated_time="15-20分钟",
            success_probability=0.98,
            impact="一次性解决所有权限问题",
            recommendation_level="★★★★☆"
        ),
    ]
)


AWS_BATCH_SPOT_INTERRUPTION_GUIDANCE = UserGuidance(
    issue_type="aws_batch_spot_interruption",
    severity="medium",
    category=IssueCategory.INFRASTRUCTURE,
    fix_strategy=FixStrategy.AUTO_FIXABLE,

    problem_summary="AWS Batch Spot实例被中断导致任务失败",
    problem_details="""
使用Spot实例可以节省成本，但当AWS需要回收容量时，Spot实例会被中断（interruption）。

**Spot中断特征**：
1. **任务突然终止** - 没有明显错误信息
2. **exit code 137** - 被强制kill
3. **持续时间短** - 任务运行不到预期时间就失败
4. **随机性** - 同样的workflow有时成功有时失败

**典型报错**：
- "Host EC2 instance terminated"
- "Spot instance interruption"
- "Instance stopped"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="启用Nextflow自动重试（推荐）",
            description="配置Nextflow自动重试Spot中断的任务",
            steps=[
                "1. Nextflow已配置了自动重试机制",
                "2. 在workflow参数中确认重试设置:",
                "   max_retries = 3  # 最多重试3次",
                "3. Spot中断的任务会自动在新实例上重试",
                "4. 无需手动干预，系统会自动恢复",
                "5. 查看workflow日志确认重试状态",
            ],
            estimated_time="0分钟（自动处理）",
            success_probability=0.90,
            impact="自动恢复，无需人工干预",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="混合使用Spot和On-Demand实例",
            description="关键任务使用On-Demand，其他任务使用Spot节省成本",
            steps=[
                "1. 登录AWS Batch控制台",
                "2. 编辑Compute Environment配置",
                "3. 设置实例类型分配策略:",
                "   - Spot占比: 80%（成本优化）",
                "   - On-Demand占比: 20%（稳定性保证）",
                "4. 保存配置并重新运行workflow",
            ],
            estimated_time="10-15分钟",
            success_probability=0.95,
            impact="平衡成本和稳定性",
            recommendation_level="★★★★☆"
        ),
        Action(
            priority=3,
            title="完全切换到On-Demand实例（最稳定）",
            description="使用On-Demand实例避免Spot中断（成本较高）",
            steps=[
                "1. 编辑Compute Environment",
                "2. 将实例类型从 SPOT 改为 ON_DEMAND",
                "3. 注意: 成本会增加2-3倍",
                "4. 适用于生产环境或关键workflow",
                "5. 重新运行workflow",
            ],
            estimated_time="5分钟",
            success_probability=0.99,
            impact="完全避免中断，但成本更高",
            recommendation_level="★★★☆☆"
        ),
    ]
)


AWS_S3_TRANSFER_ERROR_GUIDANCE = UserGuidance(
    issue_type="aws_s3_transfer_error",
    severity="medium",
    category=IssueCategory.INFRASTRUCTURE,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="AWS S3文件传输失败导致数据读写错误",
    problem_details="""
Nextflow使用AWS S3存储输入数据和输出结果，网络问题或权限问题可能导致传输失败。

**常见S3错误**：
1. **下载失败** - 无法读取输入FASTQ文件
2. **上传失败** - 无法写入输出BAM文件
3. **超时** - 大文件传输超时
4. **权限拒绝** - IAM角色权限不足

**典型报错**：
- "Unable to download file from S3"
- "SlowDown: Please reduce your request rate"
- "NoSuchKey"
- "Access Denied"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="启用S3传输加速和重试（推荐）",
            description="配置AWS CLI/SDK自动重试和传输优化",
            steps=[
                "1. 在nextflow.config中添加AWS配置优化传输",
                "2. 启用S3传输加速（针对大文件）:",
                "   - 在S3 bucket设置中启用 Transfer Acceleration",
                "3. 增加重试次数和超时时间",
                "4. 重新运行workflow",
            ],
            estimated_time="10分钟",
            success_probability=0.90,
            impact="提高传输成功率和速度",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="检查S3 bucket权限和策略",
            description="确保IAM角色有足够的S3访问权限",
            steps=[
                "1. 登录AWS S3控制台",
                "2. 选择存储workflow数据的bucket",
                "3. 检查Bucket Policy确保允许访问",
                "4. 检查IAM角色附加了S3访问权限",
                "5. 重新运行workflow",
            ],
            estimated_time="15分钟",
            success_probability=0.95,
            impact="解决权限问题",
            recommendation_level="★★★★☆"
        ),
    ]
)


AWS_BATCH_RESOURCE_UNAVAILABLE_GUIDANCE = UserGuidance(
    issue_type="aws_batch_resource_unavailable",
    severity="medium",
    category=IssueCategory.INFRASTRUCTURE,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="AWS Batch计算资源不可用导致任务长时间等待",
    problem_details="""
AWS Batch任务处于RUNNABLE状态长时间无法启动，通常是因为请求的实例类型不可用。

**常见原因**：
1. **实例类型不可用** - 请求的实例在当前区域/可用区耗尽
2. **vCPU限制** - AWS账户vCPU配额不足
3. **Spot容量不足** - Spot实例容量耗尽
4. **网络配置错误** - VPC/Subnet配置问题

**典型现象**：
- 任务长时间处于 RUNNABLE 状态（>10分钟）
- Compute Environment显示 INVALID 状态
- CloudWatch Logs中无任务启动记录
""",

    recommended_actions=[
        Action(
            priority=1,
            title="扩展Compute Environment的实例类型范围",
            description="添加更多实例类型选项，提高资源可用性",
            steps=[
                "1. 登录AWS Batch控制台",
                "2. 编辑Compute Environment",
                "3. 扩展允许的实例类型列表:",
                "   当前: [\"r5.xlarge\"]",
                "   修改为: [\"r5.xlarge\", \"r5.2xlarge\", \"r5a.xlarge\", \"r5n.xlarge\"]",
                "4. 启用 'optimal' 实例类型选择（推荐）:",
                "   AWS会自动选择可用的最优实例",
                "5. 保存配置",
                "6. 等待5分钟后任务应自动启动",
            ],
            estimated_time="10分钟",
            success_probability=0.90,
            impact="提高实例可用性",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="增加AWS账户vCPU配额",
            description="提高AWS账户的vCPU限制，支持更多并发任务",
            steps=[
                "1. 登录AWS Service Quotas控制台",
                "2. 搜索 'EC2 vCPUs'",
                "3. 查看当前配额（默认通常是32或64）",
                "4. 如果接近限制，请求增加配额",
                "5. 等待AWS审批（通常24小时内）",
                "6. 配额增加后重新运行workflow",
            ],
            estimated_time="1-2天（等待审批）",
            success_probability=0.95,
            impact="解决长期容量问题",
            recommendation_level="★★★★☆"
        ),
    ]
)


CONTAINER_PULL_ERROR_GUIDANCE = UserGuidance(
    issue_type="container_pull_error",
    severity="high",
    category=IssueCategory.INFRASTRUCTURE,
    fix_strategy=FixStrategy.USER_ACTION_REQUIRED,

    problem_summary="Docker容器镜像拉取失败",
    problem_details="""
Nextflow任务需要拉取Docker镜像，可能因网络、权限或镜像不存在而失败。

**常见拉取错误**：
1. **镜像不存在** - 镜像名称或标签错误
2. **ECR权限不足** - 无法访问私有ECR仓库
3. **网络超时** - Docker Hub限流或网络问题
4. **磁盘空间不足** - 无法保存拉取的镜像

**典型报错**：
- "manifest unknown"
- "pull access denied"
- "TLS handshake timeout"
- "no space left on device"
""",

    recommended_actions=[
        Action(
            priority=1,
            title="验证镜像名称和标签（优先检查）",
            description="确认Docker镜像名称和标签正确，镜像存在",
            steps=[
                "1. 检查错误日志中的镜像名称",
                "2. 常见错误:",
                "   - 错误: nfcore/rnaseq:3.0  →  正确: nf-core/rnaseq:3.0",
                "   - 检查镜像标签是否存在",
                "3. 在Docker Hub或Quay.io验证镜像存在",
                "4. 在workflow参数中修正镜像名称",
                "5. 重新运行workflow",
            ],
            estimated_time="5分钟",
            success_probability=0.85,
            impact="快速修复镜像名称错误",
            recommendation_level="★★★★★"
        ),
        Action(
            priority=2,
            title="配置ECR权限和镜像缓存",
            description="为AWS Batch配置ECR访问权限和本地镜像缓存",
            steps=[
                "1. 如果使用私有ECR，确保IAM角色有权限",
                "2. 建议将常用镜像推送到私有ECR",
                "3. 在nextflow.config中使用ECR镜像",
                "4. ECR在AWS内网访问更快更稳定",
            ],
            estimated_time="20-30分钟",
            success_probability=0.95,
            impact="提高拉取成功率和速度",
            recommendation_level="★★★★☆"
        ),
    ]
)


# 知识库映射
USER_GUIDANCE_KNOWLEDGE_BASE = {
    "gtf_format_error": GTF_FORMAT_ERROR_GUIDANCE,
    "star_memory_error": STAR_MEMORY_ERROR_GUIDANCE,
    "missing_reference_genome": MISSING_REFERENCE_GENOME_GUIDANCE,
    # 新增文件格式问题指导
    "fastq_quality_error": FASTQ_QUALITY_ERROR_GUIDANCE,
    "bam_file_corrupt": BAM_FILE_CORRUPT_GUIDANCE,
    "vcf_format_error": VCF_FORMAT_ERROR_GUIDANCE,
    "fasta_encoding_error": FASTA_ENCODING_ERROR_GUIDANCE,
    # Day 1: 新增文件格式和数据质量指导
    "bed_format_error": BED_FORMAT_ERROR_GUIDANCE,
    "gff_format_error": GFF_FORMAT_ERROR_GUIDANCE,
    "fasta_format_error": FASTA_FORMAT_ERROR_GUIDANCE,
    "fastq_encoding_error": FASTQ_ENCODING_ERROR_GUIDANCE,
    "duplicate_reads_high": DUPLICATE_READS_HIGH_GUIDANCE,
    "low_mapping_rate": LOW_MAPPING_RATE_GUIDANCE,
    # Day 2: 新增资源和工具特定错误指导
    "memory_oom_killer": MEMORY_OOM_KILLER_GUIDANCE,
    "disk_quota_exceeded": DISK_QUOTA_EXCEEDED_GUIDANCE,
    "cpu_timeout": CPU_TIMEOUT_GUIDANCE,
    "star_alignment_error": STAR_ALIGNMENT_ERROR_GUIDANCE,
    "bowtie2_alignment_error": BOWTIE2_ALIGNMENT_ERROR_GUIDANCE,
    "samtools_sort_error": SAMTOOLS_SORT_ERROR_GUIDANCE,
    "picard_validation_error": PICARD_VALIDATION_ERROR_GUIDANCE,
    # Day 3: 新增AWS Batch基础设施问题指导
    "aws_batch_permission_denied": AWS_BATCH_PERMISSION_DENIED_GUIDANCE,
    "aws_batch_spot_interruption": AWS_BATCH_SPOT_INTERRUPTION_GUIDANCE,
    "aws_s3_transfer_error": AWS_S3_TRANSFER_ERROR_GUIDANCE,
    "aws_batch_resource_unavailable": AWS_BATCH_RESOURCE_UNAVAILABLE_GUIDANCE,
    "container_pull_error": CONTAINER_PULL_ERROR_GUIDANCE,
}


# ============================================================================
# 用户指导生成器
# ============================================================================

class UserGuidanceGenerator:
    """用户指导生成器"""

    def __init__(self, llm_client=None):
        self.llm_client = llm_client
        self.knowledge_base = USER_GUIDANCE_KNOWLEDGE_BASE

    def classify_issue(self, issue_type: str, error_code: int = None,
                      error_message: str = None, task_name: str = None) -> IssueCategory:
        """
        分类问题类别（通用且智能的分类逻辑）

        Args:
            issue_type: 问题类型（如 "gtf_format_error"）
            error_code: 错误代码
            error_message: 错误信息
            task_name: 任务名称

        Returns:
            问题类别
        """
        # 规则1: 错误代码映射
        if error_code == 110:
            return IssueCategory.RESOURCE_INSUFFICIENT

        # 规则2: 根据issue_type精确匹配
        type_category_map = {
            'gtf_format_error': IssueCategory.DATA_FORMAT,
            'star_memory_error': IssueCategory.RESOURCE_INSUFFICIENT,
            'bowtie_align_error': IssueCategory.PARAMETER_WRONG,
            'missing_reference': IssueCategory.MISSING_REFERENCE,
            'container_error': IssueCategory.CONTAINER_ERROR,
            'permission_denied': IssueCategory.PERMISSION_ERROR,
            # 新增文件格式问题
            'fastq_quality_error': IssueCategory.DATA_QUALITY,
            'bam_file_corrupt': IssueCategory.DATA_FORMAT,
            'vcf_format_error': IssueCategory.DATA_FORMAT,
            'fasta_encoding_error': IssueCategory.DATA_FORMAT,
        }

        if issue_type in type_category_map:
            return type_category_map[issue_type]

        # 🆕 规则2.5: issue_type 模糊匹配（关键词）
        issue_lower = issue_type.lower()

        # 数据格式问题（文件格式、数据质量）
        if any(kw in issue_lower for kw in ['format', 'corrupt', 'invalid', 'malformed',
                                              'gtf', 'gff', 'fasta', 'fastq', 'bam', 'vcf',
                                              'quality', 'transcript', 'annotation']):
            return IssueCategory.DATA_FORMAT

        # 缺少文件/参考数据
        if any(kw in issue_lower for kw in ['missing', 'not_found', 'absent', 'reference',
                                              'index', 'genome', 'chromosome']):
            return IssueCategory.MISSING_REFERENCE

        # 资源不足
        if any(kw in issue_lower for kw in ['memory', 'oom', 'disk', 'space', 'resource',
                                              'timeout', 'killed']):
            return IssueCategory.RESOURCE_INSUFFICIENT

        # 权限问题
        if any(kw in issue_lower for kw in ['permission', 'denied', 'access', 'forbidden']):
            return IssueCategory.PERMISSION_ERROR

        # 容器问题
        if any(kw in issue_lower for kw in ['container', 'docker', 'image', 'pull']):
            return IssueCategory.CONTAINER_ERROR

        # 规则3: 错误信息关键词
        if error_message:
            msg_lower = error_message.lower()
            if 'format' in msg_lower or 'invalid' in msg_lower or 'corrupt' in msg_lower:
                return IssueCategory.DATA_FORMAT
            if 'not found' in msg_lower or 'no such file' in msg_lower or 'missing' in msg_lower:
                return IssueCategory.MISSING_REFERENCE
            if 'permission' in msg_lower or 'denied' in msg_lower:
                return IssueCategory.PERMISSION_ERROR
            if 'memory' in msg_lower or 'oom' in msg_lower:
                return IssueCategory.RESOURCE_INSUFFICIENT

        # 规则4: 任务名称模式
        if task_name:
            task_upper = task_name.upper()
            if any(kw in task_upper for kw in ['GTF', 'GFF', 'ANNOTATION']):
                return IssueCategory.DATA_FORMAT
            if any(kw in task_upper for kw in ['STAR', 'INDEX', 'GENOME']):
                return IssueCategory.RESOURCE_INSUFFICIENT

        # 默认：参数问题（最保守的分类）
        return IssueCategory.PARAMETER_WRONG

    def determine_fix_strategy(self, category: IssueCategory) -> FixStrategy:
        """
        根据问题类别确定修复策略

        Args:
            category: 问题类别

        Returns:
            修复策略
        """
        # 可自动修复的类别
        auto_fixable_categories = {
            IssueCategory.PARAMETER_MISSING,
            IssueCategory.PARAMETER_WRONG,
            IssueCategory.RESOURCE_INSUFFICIENT
        }

        if category in auto_fixable_categories:
            return FixStrategy.AUTO_FIXABLE

        # 需要用户操作的类别
        user_action_categories = {
            IssueCategory.DATA_QUALITY,
            IssueCategory.DATA_FORMAT,
            IssueCategory.MISSING_REFERENCE
        }

        if category in user_action_categories:
            return FixStrategy.USER_ACTION_REQUIRED

        # 其他：无法修复
        return FixStrategy.NOT_FIXABLE

    def get_guidance(self, issue_type: str, **context) -> Optional[UserGuidance]:
        """
        获取用户指导

        Args:
            issue_type: 问题类型
            **context: 上下文信息（affected_tasks, error_messages等）

        Returns:
            用户指导对象
        """
        # 从知识库获取
        if issue_type in self.knowledge_base:
            guidance = self.knowledge_base[issue_type]

            # 更新上下文信息
            if 'affected_tasks' in context:
                guidance.affected_tasks = context['affected_tasks']
            if 'error_messages' in context:
                guidance.error_messages = context['error_messages']

            return guidance

        # 如果知识库没有，返回通用指导
        log.warning(f"No guidance found for issue type: {issue_type}")
        return self._create_generic_guidance(issue_type, **context)

    def _create_generic_guidance(self, issue_type: str, **context) -> UserGuidance:
        """创建通用指导（当知识库没有时）"""

        category = self.classify_issue(
            issue_type,
            error_code=context.get('error_code'),
            error_message=context.get('error_message'),
            task_name=context.get('task_name')
        )

        fix_strategy = self.determine_fix_strategy(category)

        return UserGuidance(
            issue_type=issue_type,
            severity="medium",
            category=category,
            fix_strategy=fix_strategy,
            problem_summary=f"检测到问题: {issue_type}",
            problem_details=f"详细信息: {context.get('error_message', '未知错误')}",
            affected_tasks=context.get('affected_tasks', []),
            error_messages=context.get('error_messages', []),
            recommended_actions=[
                Action(
                    priority=1,
                    title="查看workflow日志获取更多信息",
                    description="检查具体的错误信息和堆栈跟踪",
                    steps=[
                        "1. 在workflow详情页查看失败任务的日志",
                        "2. 查看错误信息和堆栈跟踪",
                        "3. 根据错误信息搜索相关文档或论坛"
                    ],
                    estimated_time="5-10分钟"
                )
            ]
        )
