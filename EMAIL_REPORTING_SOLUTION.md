# 🚀 Konflux Release Service Catalog - AI Generated Changelog

## Overview

**RELEASE-1844**: This solution provides **automated, AI-generated changelogs** for branch promotions in the Release Service Catalog repository. Based on Happy's AI PoC, it delivers concise, focused changelogs that highlight only the most important changes for stakeholders.

## ✨ Key Features

### 🤖 **AI-Powered Changelog Generation**
- **Focused Analysis**: Prioritizes pipeline changes and core functionality
- **Smart Filtering**: Automatically ignores chore, docs, and test commits
- **Concise Format**: Maximum 150 words, 2-3 bullet points per category
- **Dual AI Provider**: OpenRouter (primary) with Gemini fallback for reliability

### 📧 **Unified Email Format**
- **Single Template**: Consistent format for both production and staging changes
- **Konflux Branding**: Professional appearance with company colors
- **Changelog Focus**: Streamlined design emphasizing key changes only
- **konflux-announce Integration**: Automatically sent to konflux-announce@redhat.com

### 🔄 **Production Integration**
- **GitHub Actions Workflow**: Fully integrated with existing promotion workflow
- **Manual Trigger**: Run via GitHub UI with customizable options
- **Dry-Run Support**: Test changelog generation without performing promotions
- **Artifact Generation**: Downloadable changelog files for records

## 🏗️ Architecture

### Core Components

1. **`generate_promotion_report.py`** - Main script with AI changelog generation
2. **`report_config.yaml`** - Production configuration optimized for changelogs
3. **`promote_branch_with_report.yaml`** - Enhanced GitHub Actions workflow
4. **`test_email_reporting.yaml`** - Safe testing workflow for email functionality

### Key Features

- **`CommitCollector`** - Handles Git operations with smart filtering
- **`AISummarizer`** - Manages AI provider integration with concise prompts
- **`EmailGenerator`** - Creates unified HTML email templates
- **`EmailSender`** - Handles SMTP delivery to konflux-announce

## 🚀 Quick Start

### 1. **GitHub Secrets Setup**
Add these secrets to your repository:
```
OPENROUTER_API_KEY    # Primary AI provider
GEMINI_API_KEY        # Fallback AI provider  
SMTP_USERNAME         # Email credentials
SMTP_PASSWORD         # Email credentials
EMAIL_FROM           # konflux-announce@redhat.com
EMAIL_TO             # konflux-announce@redhat.com
```

### 2. **Run Promotion with Changelog**
1. Go to **Actions** → **Promote branch with automated reporting**
2. Select promotion type (development-to-staging or staging-to-production)
3. Configure options (force, override, dry-run)
4. Check **"Send email report"** ✅
5. Click **"Run workflow"**

### 3. **View Results**
- **Email**: Concise changelog sent to konflux-announce@redhat.com
- **Artifacts**: Downloadable changelog files from GitHub Actions
- **Logs**: Detailed execution logs in GitHub Actions

## 📋 Production Configuration

### AI Settings (Optimized for Changelogs)
```yaml
ai:
  model: "meta-llama/llama-3-8b-instruct"
  temperature: 0.3
  max_tokens: 1000  # Reduced for concise changelogs
  max_commits_for_analysis: 20  # Focus on important changes
```

### Email Settings (Production)
```yaml
email:
  from_address: "konflux-announce@redhat.com"
  to_address: "konflux-announce@redhat.com"
  subject_templates:
    development_to_staging: "Konflux Release Service Catalog - Development to Staging Changelog"
    staging_to_production: "Konflux Release Service Catalog - Staging to Production Changelog"
```

### Content Settings (Changelog Focus)
```yaml
report:
  include_commit_links: true      # GitHub links for each commit
  include_task_analysis: false    # Disabled for concise format
  include_pipeline_impact: false  # Disabled for concise format
  include_statistics: false       # Disabled for concise format
```

## 🎯 Changelog Format

### **Email Subject**
```
Konflux Release Service Catalog - Development to Staging Changelog
```

### **Changelog Categories**
- 🚀 **Key Features**: New functionality or significant enhancements
- 🐛 **Important Fixes**: Critical bug fixes or improvements
- 🔧 **Pipeline Updates**: Changes to tasks, pipelines, or infrastructure

### **Filtering Rules**
- ✅ **Included**: Feature commits, bug fixes, pipeline changes, infrastructure updates
- ❌ **Excluded**: chore:, docs:, test:, ci:, style:, dependency updates, version bumps

## 🔧 Technical Implementation

### **Commit Filtering**
```python
def _should_include_commit(self, summary: str, message: str, files: List[str]) -> bool:
    # Skip routine maintenance commits
    skip_patterns = [
        r'^chore\s*:', r'^docs\s*:', r'^test\s*:', r'^ci\s*:',
        r'^style\s*:', r'^bump\s+', r'^update\s+deps',
        r'^update\s+.*docker\s+digest', r'^chore\(deps\)'
    ]
    # Filter logic...
```

### **AI Prompt Engineering**
```python
def _get_system_prompt(self, promotion_type: str) -> str:
    return """
    You are a professional DevOps engineer creating a concise changelog.
    
    Focus on Pipeline Changes: Prioritize changes to pipelines, tasks, and core functionality
    Ignore Routine Changes: Skip chore, docs, test, and dependency update commits
    Keep it Concise: Maximum 2-3 bullet points per category, 1-2 sentences each
    Business Impact: Focus on what users/operators need to know
    Maximum 150 words total
    """
```

## 📊 Example Output

### **Changelog Content**
```markdown
## 🚀 Key Features
- **Multi-repository support**: Added support for multiple repositories in apply-mapping task
- **Enhanced advisory processing**: Improved SBOM processing with Mobster integration

## 🐛 Important Fixes  
- **Advisory validation**: Fixed CVE validation logic for empty CVE lists
- **Pipeline optimization**: Resolved race conditions in duplicate digest components

## 🔧 Pipeline Updates
- **Task updates**: Modified filter-already-released-advisory-images for better performance
- **Infrastructure**: Updated release-service-utils docker digest to latest version
```

## 🛠️ Development

### **Local Testing**
```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export OPENROUTER_API_KEY="your_key_here"
export GEMINI_API_KEY="your_key_here"
export EMAIL_FROM="konflux-announce@redhat.com"
export EMAIL_TO="konflux-announce@redhat.com"

# Run the script
python .github/scripts/generate_promotion_report.py development staging
```

## 🎯 Benefits

### **For Konflux Team**
- **Concise Updates**: Short, focused changelogs highlighting only important changes
- **Consistent Style**: Unified format across all promotion types
- **Automated Process**: No manual changelog generation required
- **Stakeholder Communication**: Clear updates sent to konflux-announce mailing list

### **For Stakeholders**
- **Quick Reading**: 150-word maximum for easy consumption
- **Business Focus**: Emphasizes operational impact over technical details
- **Professional Format**: Clean, branded email changelogs

### **For Operations**
- **Reliability**: Dual AI provider support with automatic fallback
- **Audit Trail**: Permanent record of all changelog reports
- **Integration**: Works seamlessly with existing promotion workflows

---

**RELEASE-1844 Implementation** | **Ready for konflux-announce integration** 🚀