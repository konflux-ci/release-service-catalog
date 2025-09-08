#!/usr/bin/env python3
"""
Enhanced Promotion Report Generator
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
from datetime import datetime, timedelta
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

# Configuration
GITHUB_REPO_URL = "https://github.com/konflux-ci/release-service-catalog"
OPENROUTER_MODEL = "meta-llama/llama-3-8b-instruct"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")
REPO_ROOT = Path(__file__).parent.parent.parent

# Email Configuration
SMTP_SERVER = os.getenv("SMTP_SERVER", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT") or "587")
SMTP_USERNAME = os.getenv("SMTP_USERNAME")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
EMAIL_FROM = os.getenv("EMAIL_FROM", "konflux-announce@redhat.com")
EMAIL_TO = os.getenv("EMAIL_TO", "konflux-announce@redhat.com").split(",") if os.getenv("EMAIL_TO") else ["konflux-announce@redhat.com"]

class CommitCollector:
    """Collects and analyzes commits between branches."""
    
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        
    def _should_include_commit(self, summary: str, message: str, files: List[str]) -> bool:
        """Filter out chore, docs, and test commits to focus on important changes."""
        # Convert to lowercase for case-insensitive matching
        summary_lower = summary.lower()
        message_lower = message.lower()
        
        # Skip commits that are purely routine maintenance
        skip_patterns = [
            r'^chore\s*:',  # chore: prefix
            r'^docs\s*:',   # docs: prefix  
            r'^test\s*:',   # test: prefix
            r'^ci\s*:',     # ci: prefix
            r'^style\s*:',  # style: prefix
            r'^refactor\s*:', # refactor: prefix (unless it's significant)
            r'^bump\s+',    # version bumps
            r'^update\s+deps', # dependency updates
            r'^update\s+.*docker\s+digest', # docker digest updates
            r'^chore\(deps\)', # dependency chore
        ]
        
        # Check if commit matches skip patterns
        for pattern in skip_patterns:
            if re.match(pattern, summary_lower) or re.match(pattern, message_lower):
                return False
        
        # Check if commit only affects documentation or test files
        if files:
            non_doc_test_files = [
                f for f in files 
                if not (f.endswith('.md') or 
                       f.startswith('docs/') or 
                       f.startswith('test') or 
                       f.endswith('_test.yaml') or
                       f.endswith('.test.yaml') or
                       f.startswith('integration-tests/') or
                       f.endswith('.md'))
            ]
            # If all files are docs/tests, skip the commit
            if not non_doc_test_files:
                return False
        
        return True
        
    def run_git_command(self, cmd: List[str]) -> str:
        """Run a git command and return stdout."""
        result = subprocess.run(cmd, cwd=self.repo_root, capture_output=True, text=True)
        if result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, cmd, result.stderr)
        return result.stdout.strip()
    
    def get_commits_with_diff(self, from_branch: str, to_branch: str) -> List[Dict]:
        """Collect commits with detailed diff information."""
        # Fetch latest remote state
        self.run_git_command(["git", "fetch", "--no-tags", "origin"])
        
        # Get commit range - try origin branches first, fallback to local
        try:
            rev_range = f"origin/{to_branch}..origin/{from_branch}"
            log_cmd = [
                "git", "log", rev_range,
                "--pretty=format:%H||%s||%an||%ad||%ae",
                "--date=short"
            ]
            logs = self.run_git_command(log_cmd).split("\n")
        except subprocess.CalledProcessError:
            print(f"⚠️ Origin branches not found, trying local branches")
            rev_range = f"{to_branch}..{from_branch}"
            log_cmd = [
                "git", "log", rev_range,
                "--pretty=format:%H||%s||%an||%ad||%ae",
                "--date=short"
            ]
            logs = self.run_git_command(log_cmd).split("\n")
        commits = []
        
        for line in logs:
            if not line.strip():
                continue
                
            parts = line.strip().split("||")
            if len(parts) != 5:
                continue
                
            full_hash, summary, author, date, email = parts
            
            # Get full commit message
            message = self.run_git_command(["git", "show", "-s", "--format=%B", full_hash])
            
            # Get changed file paths
            file_list = self.run_git_command([
                "git", "diff-tree", "--no-commit-id", "--name-only", "-r", full_hash
            ]).splitlines()
            
            # Get diff stat
            diffstat = self.run_git_command(["git", "show", "--stat", "--oneline", full_hash])
            
            # Build GitHub link
            commit_url = f"{GITHUB_REPO_URL}/commit/{full_hash}"
            
            # Filter out routine commits (chore, docs, test)
            if self._should_include_commit(summary, message.strip(), file_list):
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
    """Handles AI-powered commit summarization."""
    
    def __init__(self):
        if not OPENROUTER_API_KEY:
            raise ValueError("OPENROUTER_API_KEY environment variable is required")
        
        self.headers = {
            "Authorization": f"Bearer {OPENROUTER_API_KEY}",
            "Content-Type": "application/json"
        }
    
    def generate_summary(self, commits: List[Dict], promotion_type: str) -> str:
        """Generate AI-powered summary of commits."""
        system_prompt = self._get_system_prompt(promotion_type)
        user_prompt = self._build_user_prompt(commits)
        
        payload = {
            "model": OPENROUTER_MODEL,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "temperature": 0.3,
            "max_tokens": 2500
        }
        
        print("🤖 Generating AI summary...")
        response = requests.post(OPENROUTER_URL, headers=self.headers, json=payload)
        
        if response.status_code != 200:
            raise Exception(f"OpenRouter API error: {response.status_code} {response.text}")
        
        result = response.json()
        return result["choices"][0]["message"]["content"]
    
    def _get_system_prompt(self, promotion_type: str) -> str:
        """Get system prompt for AI summarization."""
        return f"""
You are a professional DevOps engineer creating a concise changelog for the {promotion_type} deployment.

Your task is to create a SHORT, focused summary highlighting only the most important changes. Follow these guidelines:

1. **Focus on Pipeline Changes**: Prioritize changes to pipelines, tasks, and core functionality
2. **Ignore Routine Changes**: Skip chore, docs, test, and dependency update commits
3. **Keep it Concise**: Maximum 2-3 bullet points per category, 1-2 sentences each
4. **Business Impact**: Focus on what users/operators need to know

**Format** (use these exact headings):
- 🚀 **Key Features**: New functionality or significant enhancements
- 🐛 **Important Fixes**: Critical bug fixes or improvements
- 🔧 **Pipeline Updates**: Changes to tasks, pipelines, or infrastructure

**Style Guidelines**:
- Use active voice and present tense
- Be concise and direct
- Focus on business value and operational impact
- Avoid technical jargon
- Maximum 150 words total

Respond only with the markdown content for the changelog section.
"""
    
    def _build_user_prompt(self, commits: List[Dict]) -> str:
        """Build user prompt with commit data."""
        entries = []
        for commit in commits[:30]:  # Limit to 30 commits for better AI performance
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

Focus on the most impactful changes and group them appropriately. If there are many similar changes, summarize them together.
"""

class TaskPipelineAnalyzer:
    """Analyzes task-pipeline relationships for changed components."""
    
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.pipeline_dir = repo_root / "pipelines"
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
                        "commit_url": commit["url"]
                    })
        
        # Remove duplicates
        unique_tasks = {}
        for task in changed_tasks:
            key = (task["name"], task["folder"])
            if key not in unique_tasks:
                unique_tasks[key] = task
        
        return list(unique_tasks.values())
    
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
                    print(f"⚠️ Could not parse YAML file {file_path}: {e}")
                    continue
                for doc in docs:
                    if not isinstance(doc, dict) or doc.get("kind") != "Pipeline":
                        continue
                    pipeline_name = doc.get("metadata", {}).get("name", file_path.stem)
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
                                    if path_in_repo == changed_task["file_path"] or path_in_repo.endswith(changed_task["file_path"].split("/tasks/")[-1]):
                                        task_pipeline_map[(changed_task["name"], changed_task["folder"])].add(pipeline_name)
                            elif "name" in task_ref:
                                # Fallback to name-based matching
                                task_name = task_ref["name"].strip()
                                for changed_task in changed_tasks:
                                    if task_name == changed_task["name"]:
                                        task_pipeline_map[(changed_task["name"], changed_task["folder"])].add(pipeline_name)
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
        """Generate complete HTML email content - simplified for changelog focus."""
        html_template = self._get_html_template()
        
        # Convert markdown summary to HTML for better formatting
        summary_html = markdown.markdown(summary, extensions=['extra', 'sane_lists'])
        
        # Fill template with simplified data
        content = html_template.format(
            promotion_type=promotion_type.replace("-", " ").title(),
            date=datetime.now().strftime("%B %d, %Y"),
            summary=summary_html,
            repo_url=GITHUB_REPO_URL
        )
        
        return content
    
    def _get_html_template(self) -> str:
        """Get HTML email template - unified format for both production and staging."""
        return """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Konflux Release Service Catalog - {promotion_type} Changelog</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.5;
            color: #333;
            max-width: 700px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f8f9fa;
        }}
        .container {{
            background: white;
            border-radius: 8px;
            padding: 25px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }}
        .header {{
            border-bottom: 2px solid #0366d6;
            padding-bottom: 15px;
            margin-bottom: 20px;
        }}
        .header h1 {{
            color: #0366d6;
            margin: 0;
            font-size: 24px;
        }}
        .header .subtitle {{
            color: #666;
            font-size: 14px;
            margin-top: 5px;
        }}
        .changelog {{
            margin: 20px 0;
        }}
        .changelog h2 {{
            color: #0366d6;
            font-size: 18px;
            margin: 20px 0 10px 0;
            border-bottom: 1px solid #e1e4e8;
            padding-bottom: 5px;
        }}
        .changelog ul {{
            margin: 10px 0;
            padding-left: 20px;
        }}
        .changelog li {{
            margin: 8px 0;
            line-height: 1.4;
        }}
        .changelog a {{
            color: #0366d6;
            text-decoration: none;
            font-weight: 500;
        }}
        .changelog a:hover {{
            text-decoration: underline;
        }}
        .footer {{
            margin-top: 30px;
            padding-top: 15px;
            border-top: 1px solid #e1e4e8;
            color: #666;
            font-size: 12px;
        }}
        .no-changes {{
            text-align: center;
            color: #666;
            font-style: italic;
            padding: 30px;
            background: #f6f8fa;
            border-radius: 6px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Konflux Release Service Catalog</h1>
            <div class="subtitle">{promotion_type} Changelog - {date}</div>
        </div>
        
        <div class="changelog">
            {summary}
        </div>
        
        <div class="footer">
            <p>This changelog was automatically generated by the Konflux Release Service Catalog promotion system.</p>
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
                    </tr>
                </thead>
                <tbody>
        """
        
        for task in task_analysis["changed_tasks"]:
            task_key = (task["name"], task["folder"])
            pipelines = task_analysis["pipeline_impact"].get(task_key, set())
            
            pipeline_links = []
            for pipeline in sorted(pipelines):
                pipeline_url = f"{GITHUB_REPO_URL}/tree/development/pipelines/{pipeline}"
                pipeline_links.append(f'<a href="{pipeline_url}">{pipeline}</a>')
            
            task_url = f"{GITHUB_REPO_URL}/tree/development/tasks/{task['folder']}/{task['name']}"
            
            html += f"""
                    <tr>
                        <td><a href="{task_url}">{task['name']}</a></td>
                        <td><code>{task['folder']}</code></td>
                        <td>{', '.join(pipeline_links) if pipeline_links else '<em>No pipelines affected</em>'}</td>
                        <td>{len(pipelines)}</td>
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
        if not all([SMTP_USERNAME, SMTP_PASSWORD]):
            raise ValueError("SMTP_USERNAME and SMTP_PASSWORD environment variables are required")
    
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
                server.starttls()
                server.login(SMTP_USERNAME, SMTP_PASSWORD)
                server.send_message(msg)
            
            print(f"✅ Email sent successfully to {len(recipients)} recipients")
            return True
            
        except Exception as e:
            print(f"❌ Failed to send email: {e}")
            return False

class GeminiSummarizer:
    def __init__(self, api_key):
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel("gemini-1.5-pro-latest")

    def generate_summary(self, prompt):
        response = self.model.generate_content(prompt)
        return response.text

def main():
    """Main function to generate and send promotion report."""
    if len(sys.argv) != 3:
        print("Usage: python generate_promotion_report.py <from_branch> <to_branch>")
        print("Example: python generate_promotion_report.py development staging")
        sys.exit(1)
    
    from_branch = sys.argv[1]
    to_branch = sys.argv[2]
    promotion_type = f"{from_branch}-to-{to_branch}"
    
    print(f"🚀 Generating promotion report: {from_branch} → {to_branch}")
    
    try:
        # Initialize components
        collector = CommitCollector(REPO_ROOT)
        analyzer = TaskPipelineAnalyzer(REPO_ROOT)
        email_gen = EmailGenerator()
        
        # Collect commits
        print("📊 Collecting commits...")
        commits = collector.get_commits_with_diff(from_branch, to_branch)
        
        if not commits:
            print("ℹ️ No commits found for this promotion")
            return
        
        print(f"📝 Found {len(commits)} commits")
        
        # Generate AI summary using Gemini if available, else OpenRouter
        summary = None
        gemini_api_key = os.getenv("GEMINI_API_KEY")
        if gemini_api_key:
            print("🤖 Generating AI summary with Gemini...")
            # Use the same prompt as before
            summarizer = GeminiSummarizer(gemini_api_key)
            # Build the prompt as markdown (reuse build_prompt from AISummarizer)
            prompt_text = AISummarizer()._build_user_prompt(commits)
            system_prompt = AISummarizer()._get_system_prompt(promotion_type)
            full_prompt = f"{system_prompt}\n\n{prompt_text}"
            summary = summarizer.generate_summary(full_prompt)
        else:
            print("🤖 Generating AI summary with OpenRouter...")
            summarizer = AISummarizer()
            summary = summarizer.generate_summary(commits, promotion_type)
        
        # Analyze task-pipeline impact
        print("🔍 Analyzing task-pipeline relationships...")
        task_analysis = analyzer.analyze_changes(commits)
        
        # Generate email content
        print("📧 Generating email content...")
        email_content = email_gen.generate_email_content(
            promotion_type, commits, summary, task_analysis
        )
        
        # Save report files
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_dir = Path(f"promotion_reports/{promotion_type}_{timestamp}")
        report_dir.mkdir(parents=True, exist_ok=True)
        
        # Save JSON data
        with open(report_dir / "commits.json", "w") as f:
            json.dump(commits, f, indent=2)
        
        # Save summary
        with open(report_dir / "summary.md", "w") as f:
            f.write(summary)
        
        # Save HTML report
        with open(report_dir / "report.html", "w") as f:
            f.write(email_content)
        
        print(f"📁 Report files saved to: {report_dir}")
        
        # Send email if configured
        if EMAIL_TO:
            print("📤 Sending email report...")
            subject = f"Konflux Release Service Catalog - {promotion_type.replace('-', ' ').title()} Changelog"
            
            try:
                sender = EmailSender()
                success = sender.send_email(subject, email_content, EMAIL_TO)
                if success:
                    print("✅ Email report sent successfully!")
                else:
                    print("⚠️ Email sending failed, but report files were saved")
            except Exception as e:
                print(f"⚠️ Email sending failed: {e}")
                print("Report files were saved locally")
        else:
            print("ℹ️ Email sending not configured (EMAIL_TO not set)")
        
        print("🎉 Promotion report generation completed!")
        
    except Exception as e:
        print(f"❌ Error generating promotion report: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 