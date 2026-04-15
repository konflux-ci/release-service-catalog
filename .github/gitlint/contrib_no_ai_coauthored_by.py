# -*- coding: utf-8 -*-
from gitlint.rules import CommitRule, RuleViolation
import re


class NoAICoAuthoredBy(CommitRule):
    """This rule will enforce that Co-Authored-By trailers do not
    reference AI tools. AI tools should be referenced using
    the Assisted-by: trailer instead."""

    id = "UC2"
    name = "contrib-no-ai-coauthored-by"

    # AI tool patterns to block in Co-Authored-By:
    ai_tool_patterns = [
        r"claude",
        r"cursor",
        r"copilot",
        r"chatgpt",
        r"gemini",
    ]

    def validate(self, commit):
        """Validate that Co-Authored-By does not reference AI tools."""

        pattern = re.compile("|".join(self.ai_tool_patterns), re.IGNORECASE)

        for idx, line in enumerate(commit.message.body):
            match = re.match(r"\s*co-authored-by:\s*(.*)", line, re.IGNORECASE)
            if match:
                value = match.group(1)
                if pattern.search(value):
                    return [
                        RuleViolation(
                            self.id,
                            f"Co-Authored-By must not reference AI tools. "
                            f"Use 'Assisted-by: <AI TOOL>' instead. "
                            f"Found: {line.strip()}",
                            line_nr=idx + 2,
                        )
                    ]

        return []
