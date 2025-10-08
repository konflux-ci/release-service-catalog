#!/usr/bin/env python3
"""
Promotion Report Generator
===================================

This script generates comprehensive email reports for branch promotions in the
release-service-catalog repository. It combines commit analysis, AI summarization,
and task-pipeline impact analysis into a single automated workflow.

Features:
- Collects commits between branches with detailed diff information
- Uses AI to generate human-readable summaries with consistent formatting
- Analyzes task-pipeline relationships for changed components
- Generates professional HTML email templates
- Supports both development-to-staging and staging-to-production promotions
- Integrates with GitHub Actions workflow
"""

import os
import sys
import json
import subprocess
import requests
import yaml
import re
import logging
from datetime import datetime
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple, Optional
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import markdown
import google.generativeai as genai

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Configuration Constants
GITHUB_REPO_URL = "https://github.com/konflux-ci/release-service-catalog"
# Repository root directory (release-service-catalog/)
REPO_ROOT = Path(__file__).parent.parent.parent

# AI Configuration
GEMINI_MODEL = "gemini-flash-latest"
MAX_COMMITS_FOR_AI = 50
AI_TEMPERATURE = 0.7
AI_MAX_TOKENS = 2500

# Email Configuration
DEFAULT_SMTP_SERVER = "smtp.gmail.com"
DEFAULT_SMTP_PORT = 587
DEFAULT_EMAIL_FROM = "release-reports@konflux-ci.com"

# File Configuration  
TASK_PIPELINE_DIR = "pipelines"

def read_secret_from_file(env_var_name: str, file_env_var: str) -> str:
    """Read secret from file if available, otherwise from environment variable."""
    file_path = os.getenv(file_env_var)
    if file_path and os.path.exists(file_path):
        with open(file_path, 'r') as f:
            return f.read().strip()
    return os.getenv(env_var_name, "")

# Environment Variables and File-based Secrets
SMTP_SERVER = os.getenv("SMTP_SERVER", DEFAULT_SMTP_SERVER)
SMTP_PORT = int(os.getenv("SMTP_PORT") or DEFAULT_SMTP_PORT)
SMTP_USERNAME = read_secret_from_file("SMTP_USERNAME", "SMTP_USERNAME_FILE")
SMTP_PASSWORD = read_secret_from_file("SMTP_PASSWORD", "SMTP_PASSWORD_FILE") 
EMAIL_FROM = os.getenv("EMAIL_FROM", DEFAULT_EMAIL_FROM)
EMAIL_TO = os.getenv("EMAIL_TO", "").split(",") if os.getenv("EMAIL_TO") else []

class CommitCollector:
    """Collects and analyzes commits between branches."""
    
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
    
    def _should_include_commit(self, commit_message: str) -> bool:
        """Filter out routine commits that don't add business value."""
        # Convert to lowercase for case-insensitive matching
        message_lower = commit_message.lower()
        
        # Skip routine commits
        skip_patterns = [
            'chore:', 'docs:', 'test:', 'ci:', 'style:', 'refactor:',
            'bump', 'update dependencies', 'dependency update',
            'merge', 'revert', 'wip:', 'work in progress'
        ]
        
        for pattern in skip_patterns:
            if pattern in message_lower:
                return False
        
        return True
        
    def run_git_command(self, args: List[str]) -> str:
        """Run a git command with the given arguments and return stdout."""
        cmd = ["git", *args]
        result = subprocess.run(cmd, cwd=self.repo_root, capture_output=True, text=True)
        if result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, cmd, result.stderr)
        return result.stdout.strip()
    
    def get_commits_with_diff(self, from_branch: str, to_branch: str, commit_range: str = None) -> List[Dict]:
        """Collect commits with detailed diff information."""
        # Fetch latest remote state (skip if commit_range provided - already captured before promotion)
        if not commit_range:
            self.run_git_command(["fetch", "--no-tags", "origin"])
        
        # Use provided commit range or determine it
        if commit_range:
            rev_range = commit_range
            logger.info(f"Using provided commit range: {rev_range}")
        else:
            # Get commit range - try origin branches first, fallback to local
            try:
                rev_range = f"origin/{to_branch}..origin/{from_branch}"
            except subprocess.CalledProcessError:
                logger.warning("Origin branches not found, trying local branches")
                rev_range = f"{to_branch}..{from_branch}"
        
        # Handle different commit range formats
        if ".." in rev_range:
            # Standard range format (e.g., "origin/production..origin/staging")
            log_cmd = [
                "log", rev_range,
                "--pretty=format:%H||%s||%an||%ad||%ae",
                "--date=short"
            ]
        else:
            # Single commit or space-separated commits
            commits = rev_range.split()
            if len(commits) == 1:
                # Single commit
                log_cmd = [
                    "log", commits[0],
                    "--pretty=format:%H||%s||%an||%ad||%ae",
                    "--date=short",
                    "-1"
                ]
            else:
                # Multiple commits
                log_cmd = [
                    "log", "--pretty=format:%H||%s||%an||%ad||%ae",
                    "--date=short"
                ] + commits
        
        logs = self.run_git_command(log_cmd).split("\n")
        commits = []
        
        for line in logs:
            if not line.strip():
                continue
                
            parts = line.strip().split("||")
            if len(parts) != 5:
                continue
                
            full_hash, summary, author, date, email = parts
            
            # Filter out routine commits
            if not self._should_include_commit(summary):
                continue
            
            # Get full commit message
            message = self.run_git_command(["show", "-s", "--format=%B", full_hash])
            
            # Get changed file paths
            file_list = self.run_git_command([
                "diff-tree", "--no-commit-id", "--name-only", "-r", full_hash
            ]).splitlines()
            
            # Get diff stat
            diffstat = self.run_git_command(["show", "--stat", "--oneline", full_hash])
            
            # Build GitHub link
            commit_url = f"{GITHUB_REPO_URL}/commit/{full_hash}"
            
            commits.append({
                "hash": full_hash,
                "summary": summary,
                "message": message.strip(),
                "author": author,
                "email": email,
                "date": date,
                "files": file_list,
                "diffstat": diffstat,
                "url": commit_url
            })
        
        return commits

class AISummarizer:
    """Handles AI-powered commit summarization using Gemini API."""
    
    def __init__(self, api_key: str):
        if not api_key:
            raise ValueError("GEMINI_API_KEY environment variable or file is required")
        
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel(GEMINI_MODEL)
    
    def generate_summary(self, commits: List[Dict], promotion_type: str) -> str:
        """Generate AI-powered summary of commits using Gemini."""
        system_prompt = self._get_system_prompt(promotion_type)
        user_prompt = self._build_user_prompt(commits)
        
        full_prompt = f"{system_prompt}\n\n{user_prompt}"
        
        response = self.model.generate_content(full_prompt)
        return response.text
    
    def _get_system_prompt(self, promotion_type: str) -> str:
        """Get system prompt for AI summarization."""
        return f"""
You are a professional DevOps engineer creating a promotion report for the {promotion_type} deployment.

Your task is to create a clear, concise summary of the changes being promoted. Follow these EXACT guidelines:

1. **MANDATORY Header Structure** (start with these EXACT headers):
   - ## 📋 Executive Summary
   - ## {promotion_type.replace('-', ' ').title()} Promotion Report
   - ### Executive Summary

2. **MANDATORY Executive Summary** (2-3 paragraphs):
   - Start with "This {promotion_type} deployment introduces..." 
   - Highlight the most significant changes and their business impact
   - Mention key features, bug fixes, or improvements
   - Use professional, non-technical language when possible
   - ALWAYS include this section - it's required

3. **Change Categories** (use these EXACT headings):
   - ### 🚀 **New Features & Enhancements**
   - ### 🐛 **Bug Fixes & Improvements**

4. **For each change**:
   - Use bullet points with clear, concise descriptions
   - Include the commit title as a hyperlink to the GitHub commit
   - Add 1-2 sentences explaining the impact or reasoning
   - Avoid technical jargon unless necessary

5. **Style Guidelines**:
   - Use active voice and present tense
   - Be consistent with formatting
   - Focus on business value and user impact
   - Keep descriptions concise but informative
   - IGNORE: chore, docs, test, ci, style, refactor, bump, and dependency update commits

6. **CRITICAL**: Always start with the exact header structure above. Do not skip any headers.

7. **CONSISTENCY REQUIREMENT**: 
   - ALWAYS include ALL feat() and fix() commits in your analysis
   - Be consistent across multiple runs - same commits should produce same results
   - Do not randomly skip important commits
   - If you see feat() or fix() commits, they MUST be included in the report

Respond only with the markdown content for the changelog section.
"""
    
    def _build_user_prompt(self, commits: List[Dict]) -> str:
        """Build user prompt with commit data."""
        entries = []
        for commit in commits[:MAX_COMMITS_FOR_AI]:  # Include more commits for comprehensive coverage
            entry = f"""
**Commit**: {commit['summary']}
**Author**: {commit['author']} ({commit['email']})
**Date**: {commit['date']}
**URL**: {commit['url']}
**Files Changed**: {len(commit['files'])}
**Message**: {commit['message']}
**Diff Stats**: {commit['diffstat']}
            """.strip()
            entries.append(entry)
        
        return f"""
Please analyze the following {len(commits)} commits and create a professional summary:

{chr(10).join(entries)}

CRITICAL REQUIREMENTS:
1. **INCLUDE ALL feat() and fix() commits** - Do not skip any important commits
2. **Be consistent** - Every time you analyze the same commits, include the same feat/fix items
3. **Focus on business impact** - Group similar changes but don't omit any feat/fix commits
4. **Comprehensive coverage** - Ensure all significant changes are represented

Focus on the most impactful changes and group them appropriately. If there are many similar changes, summarize them together, but ALWAYS include every feat() and fix() commit.
"""

class TaskPipelineAnalyzer:
    """Analyzes task-pipeline relationships for changed components."""
    
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.pipeline_dir = repo_root / TASK_PIPELINE_DIR
        self.tasks_dir = repo_root / "tasks"
    
    def analyze_changes(self, commits: List[Dict]) -> Dict:
        """Analyze which tasks were changed and their pipeline impact."""
        changed_tasks = self._extract_changed_tasks(commits)
        if not changed_tasks:
            return {"changed_tasks": [], "pipeline_impact": {}}
        
        pipeline_impact = self._analyze_pipeline_impact(changed_tasks)
        
        return {
            "changed_tasks": changed_tasks,
            "pipeline_impact": pipeline_impact
        }
    
    def _extract_changed_tasks(self, commits: List[Dict]) -> List[Dict]:
        """Extract changed task information from commits."""
        changed_tasks = []
        task_pattern = re.compile(r"tasks/([^/]+)/([^/]+)/[^/]+\.yaml")
        
        for commit in commits:
            for file_path in commit.get("files", []):
                match = task_pattern.search(file_path)
                if match:
                    folder, task_name = match.groups()
                    changed_tasks.append({
                        "name": task_name,
                        "folder": folder,
                        "file_path": file_path,
                        "commit": commit["hash"],
                        "commit_url": commit["url"],
                        "commit_summary": commit["summary"],
                        "commit_message": commit["message"]
                    })
        
        # Group by task and collect all commits that modified each task
        task_commits = defaultdict(list)
        for task in changed_tasks:
            key = (task["name"], task["folder"])
            task_commits[key].append({
                "commit": task["commit"],
                "commit_url": task["commit_url"],
                "commit_summary": task["commit_summary"],
                "commit_message": task["commit_message"]
            })
        
        # Create unique tasks with all their commits
        unique_tasks = []
        for (name, folder), commits_list in task_commits.items():
            unique_tasks.append({
                "name": name,
                "folder": folder,
                "commits": commits_list
            })
        
        return unique_tasks
    
    def _analyze_pipeline_impact(self, changed_tasks: List[Dict]) -> Dict:
        """Analyze which pipelines use the changed tasks."""
        task_pipeline_map = defaultdict(set)
        
        for root, _, files in os.walk(self.pipeline_dir):
            for file in files:
                if not file.endswith(".yaml"):
                    continue
                file_path = Path(root) / file
                try:
                    with open(file_path) as f:
                        docs = list(yaml.safe_load_all(f))
                except Exception as e:
                    logger.warning(f"Could not parse YAML file {file_path}: {e}")
                    continue
                for doc in docs:
                    if not isinstance(doc, dict) or doc.get("kind") != "Pipeline":
                        continue
                    # Get the relative path from pipelines directory
                    pipeline_relative_path = file_path.relative_to(self.pipeline_dir)
                    pipeline_name = doc.get("metadata", {}).get("name", file_path.stem)
                    # Use the directory structure, not the metadata name
                    pipeline_path = str(pipeline_relative_path.parent) if pipeline_relative_path.parent != Path('.') else pipeline_name
                    for task_block in doc.get("spec", {}).get("tasks", []) + doc.get("spec", {}).get("finally", []):
                        task_ref = task_block.get("taskRef")
                        # Enhanced matching logic
                        if isinstance(task_ref, dict):
                            resolver = task_ref.get("resolver")
                            params = {p["name"]: p["value"] for p in task_ref.get("params", [])} if "params" in task_ref else {}
                            path_in_repo = params.get("pathInRepo")
                            if resolver == "git" and path_in_repo:
                                # Match by file_path (relative to repo root)
                                for changed_task in changed_tasks:
                                    task_file_path = f"tasks/{changed_task['folder']}/{changed_task['name']}/{changed_task['name']}.yaml"
                                    if path_in_repo == task_file_path or path_in_repo.endswith(f"{changed_task['name']}.yaml"):
                                        task_pipeline_map[(changed_task["name"], changed_task["folder"])].add(pipeline_path)
                            elif "name" in task_ref:
                                # Fallback to name-based matching
                                task_name = task_ref["name"].strip()
                                for changed_task in changed_tasks:
                                    if task_name == changed_task["name"]:
                                        task_pipeline_map[(changed_task["name"], changed_task["folder"])].add(pipeline_path)
                        elif isinstance(task_ref, str):
                            task_name = task_ref.strip()
                            for changed_task in changed_tasks:
                                if task_name == changed_task["name"]:
                                    task_pipeline_map[(changed_task["name"], changed_task["folder"])].add(pipeline_name)
        return dict(task_pipeline_map)

class EmailGenerator:
    """Generates professional HTML email reports."""
    
    def __init__(self):
        self.template_dir = Path(__file__).parent / "email_templates"
        self.template_dir.mkdir(exist_ok=True)
    
    def generate_email_content(self, promotion_type: str, commits: List[Dict], 
                             summary: str, task_analysis: Dict) -> str:
        """Generate complete HTML email content."""
        html_template = self._get_html_template()
        
        # Generate task-pipeline table
        task_table = self._generate_task_table(task_analysis)
        
        # Format commit statistics
        stats = self._calculate_stats(commits)
        
        # Convert markdown summary to HTML for better formatting
        summary_html = markdown.markdown(summary, extensions=['extra', 'sane_lists'])
        
        # Fill template
        content = html_template.format(
            promotion_type=promotion_type.replace("-", " ").title(),
            date=datetime.now().strftime("%B %d, %Y"),
            commit_count=len(commits),
            author_count=stats["unique_authors"],
            file_count=stats["total_files"],
            summary=summary_html,
            task_table=task_table,
            repo_url=GITHUB_REPO_URL
        )
        
        return content
    
    def _get_html_template(self) -> str:
        """Get HTML email template."""
        return """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Release Service Catalog - {promotion_type} Promotion Report</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f8f9fa;
        }}
        .container {{
            background: white;
            border-radius: 8px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        .header {{
            border-bottom: 3px solid #0366d6;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }}
        .header h1 {{
            color: #0366d6;
            margin: 0;
            font-size: 28px;
        }}
        .header .subtitle {{
            color: #666;
            font-size: 16px;
            margin-top: 5px;
        }}
        .stats {{
            background: #f6f8fa;
            border-radius: 6px;
            padding: 20px;
            margin: 20px 0;
        }}
        .stats-table {{
            width: 100%;
            border-collapse: collapse;
        }}
        .stats-table td {{
            text-align: center;
            padding: 10px;
            vertical-align: top;
        }}
        .stat .number {{
            font-size: 24px;
            font-weight: bold;
            color: #0366d6;
            display: block;
            margin-bottom: 5px;
        }}
        .stat .label {{
            font-size: 14px;
            color: #666;
            display: block;
        }}
        .summary {{
            background: #f8f9fa;
            border-left: 4px solid #28a745;
            padding: 20px;
            margin: 20px 0;
        }}
        .summary h2 {{
            color: #28a745;
            margin-top: 0;
        }}
        .task-table {{
            margin: 30px 0;
        }}
        .task-table h2 {{
            color: #0366d6;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
        }}
        th, td {{
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }}
        th {{
            background-color: #f6f8fa;
            font-weight: 600;
        }}
        tr:hover {{
            background-color: #f8f9fa;
        }}
        .footer {{
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            color: #666;
            font-size: 14px;
        }}
        a {{
            color: #0366d6;
            text-decoration: none;
        }}
        a:hover {{
            text-decoration: underline;
        }}
        .no-changes {{
            text-align: center;
            color: #666;
            font-style: italic;
            padding: 40px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Release Service Catalog</h1>
            <div class="subtitle">{promotion_type} Promotion Report - {date}</div>
        </div>
        
        <div class="stats">
            <table class="stats-table">
                <tr>
                    <td>
                        <div class="stat">
                            <div class="number">{commit_count}</div>
                            <div class="label">Commits</div>
                        </div>
                    </td>
                    <td>
                        <div class="stat">
                            <div class="number">{author_count}</div>
                            <div class="label">Contributors</div>
                        </div>
                    </td>
                    <td>
                        <div class="stat">
                            <div class="number">{file_count}</div>
                            <div class="label">Files Changed</div>
                        </div>
                    </td>
                </tr>
            </table>
        </div>
        
        <div class="summary">
            {summary}
        </div>
        
        {task_table}
        
        <div class="footer">
            <p>This report was automatically generated by the Release Service Catalog promotion system.</p>
            <p>Repository: <a href="{repo_url}">{repo_url}</a></p>
        </div>
    </div>
</body>
</html>
"""
    
    def _generate_task_table(self, task_analysis: Dict) -> str:
        """Generate HTML table for task-pipeline analysis."""
        if not task_analysis.get("changed_tasks"):
            return """
        <div class="task-table">
            <h2>🧩 Task Impact Analysis</h2>
            <div class="no-changes">No task changes detected in this promotion.</div>
        </div>
            """
        
        html = """
        <div class="task-table">
            <h2>🧩 Task Impact Analysis</h2>
            <p>The following tasks were modified and their pipeline impact:</p>
            <table>
                <thead>
                    <tr>
                        <th>Task Name</th>
                        <th>Type</th>
                        <th>Affected Pipelines</th>
                        <th>Pipeline Count</th>
                        <th>Impacted By Commits</th>
                    </tr>
                </thead>
                <tbody>
        """
        
        for task in task_analysis["changed_tasks"]:
            task_key = (task["name"], task["folder"])
            pipelines = task_analysis["pipeline_impact"].get(task_key, set())
            
            pipeline_links = []
            for pipeline in sorted(pipelines):
                pipeline_url = f"{GITHUB_REPO_URL}/tree/development/{TASK_PIPELINE_DIR}/{pipeline}"
                # Extract just the pipeline name for display (after the last slash)
                display_name = pipeline.split('/')[-1] if '/' in pipeline else pipeline
                pipeline_links.append(f'<a href="{pipeline_url}">{display_name}</a>')
            
            task_url = f"{GITHUB_REPO_URL}/tree/development/tasks/{task['folder']}/{task['name']}"
            
            # Generate commit links
            commit_links = []
            for commit in task.get("commits", []):
                commit_short = commit["commit"][:8]
                commit_type = commit["commit_summary"].split(":")[0] if ":" in commit["commit_summary"] else "change"
                commit_desc = commit["commit_summary"].split(":", 1)[1].strip() if ":" in commit["commit_summary"] else commit["commit_summary"]
                # Truncate long descriptions
                if len(commit_desc) > 50:
                    commit_desc = commit_desc[:47] + "..."
                commit_links.append(f'{commit_type}: {commit_desc} (<a href="{commit["commit_url"]}">{commit_short}</a>)')
            
            html += f"""
                    <tr>
                        <td><a href="{task_url}">{task['name']}</a></td>
                        <td><code>{task['folder']}</code></td>
                        <td>{', '.join(pipeline_links) if pipeline_links else '<em>No pipelines affected</em>'}</td>
                        <td>{len(pipelines)}</td>
                        <td>{'<br>'.join(commit_links) if commit_links else '<em>No commits</em>'}</td>
                    </tr>
            """
        
        html += """
                </tbody>
            </table>
        </div>
        """
        
        return html
    
    def _calculate_stats(self, commits: List[Dict]) -> Dict:
        """Calculate commit statistics."""
        unique_authors = set()
        total_files = 0
        
        for commit in commits:
            unique_authors.add(commit["author"])
            total_files += len(commit.get("files", []))
        
        return {
            "unique_authors": len(unique_authors),
            "total_files": total_files
        }

class EmailSender:
    """Handles email sending functionality."""
    
    def __init__(self):
        # For Red Hat corporate SMTP, authentication might not be required
        self.use_auth = bool(SMTP_USERNAME and SMTP_PASSWORD)
        if not self.use_auth:
            logger.info("📧 SMTP authentication disabled - using corporate relay")
    
    def send_email(self, subject: str, html_content: str, recipients: List[str]) -> bool:
        """Send HTML email."""
        try:
            msg = MIMEMultipart('alternative')
            msg['Subject'] = subject
            msg['From'] = EMAIL_FROM
            msg['To'] = ', '.join(recipients)
            
            # Attach HTML content
            html_part = MIMEText(html_content, 'html')
            msg.attach(html_part)
            
            # Send email
            with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
                # Only use STARTTLS and authentication if credentials are provided
                if self.use_auth:
                    server.starttls()
                    server.login(SMTP_USERNAME, SMTP_PASSWORD)
                    logger.info("🔐 Using SMTP authentication")
                else:
                    logger.info("📧 Using SMTP without authentication (corporate relay)")
                
                server.send_message(msg)
            
            logger.info(f"✅ Email sent to {len(recipients)} recipients")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to send email: {e}")
            return False

# Removed GeminiSummarizer class - using AISummarizer for everything

def main():
    """Main function to generate and send promotion report."""
    if len(sys.argv) < 3 or len(sys.argv) > 5:
        logger.error("Usage: python generate_promotion_report.py <from_branch> <to_branch> [--commit-range <range>]")
        logger.error("Example: python generate_promotion_report.py development staging")
        logger.error("Example: python generate_promotion_report.py staging production --commit-range origin/production..origin/staging")
        sys.exit(1)
    
    from_branch = sys.argv[1]
    to_branch = sys.argv[2]
    promotion_type = f"{from_branch}-to-{to_branch}"
    
    # Parse optional commit range parameter
    commit_range = None
    if len(sys.argv) >= 5 and sys.argv[3] == "--commit-range":
        commit_range = sys.argv[4]
        logger.info(f"Using provided commit range: {commit_range}")
    
    logger.info(f"🚀 Generating promotion report: {from_branch} → {to_branch}")
    
    try:
        # Initialize components
        collector = CommitCollector(REPO_ROOT)
        analyzer = TaskPipelineAnalyzer(REPO_ROOT)
        email_gen = EmailGenerator()
        
        # Collect commits
        logger.info("📊 Collecting commits...")
        commits = collector.get_commits_with_diff(from_branch, to_branch, commit_range)
        
        if not commits:
            logger.info("ℹ️ No commits found for this promotion")
            return
        
        logger.info(f"📝 Found {len(commits)} commits")
        
        # Generate AI summary using Gemini API
        gemini_api_key = read_secret_from_file("GEMINI_API_KEY", "GEMINI_API_KEY_FILE")
        if not gemini_api_key:
            raise ValueError("GEMINI_API_KEY environment variable or file is required")
        
        logger.info("🤖 Generating AI summary...")
        summarizer = AISummarizer(gemini_api_key)
        summary = summarizer.generate_summary(commits, promotion_type)
        
        # Analyze task-pipeline impact
        logger.info("🔍 Analyzing task-pipeline relationships...")
        task_analysis = analyzer.analyze_changes(commits)
        
        # Generate email content
        logger.info("📧 Generating email content...")
        email_content = email_gen.generate_email_content(
            promotion_type, commits, summary, task_analysis
        )
        
        # Send email if configured
        if EMAIL_TO:
            logger.info("📤 Sending email report...")
            subject = f"Release Service Catalog - {promotion_type.replace('-', ' ').title()} Promotion Report"
            
            try:
                sender = EmailSender()
                success = sender.send_email(subject, email_content, EMAIL_TO)
                if success:
                    logger.info("✅ Email report sent successfully!")
                else:
                    logger.warning("⚠️ Email sending failed, but report files were saved")
            except Exception as e:
                logger.warning(f"⚠️ Email sending failed: {e}")
                logger.info("📁 Report files were saved locally")
        else:
            logger.info("ℹ️ Email sending not configured (EMAIL_TO not set)")
        
        logger.info("🎉 Promotion report generation completed!")
        
    except Exception as e:
        logger.error(f"❌ Error generating promotion report: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
