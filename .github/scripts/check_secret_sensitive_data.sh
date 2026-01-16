#!/usr/bin/env bash

# Check that all kubectl create secret commands in pre-apply-task-hook.sh files
# contain at least one SENSITIVE_DATA_ or sensitive-data- string
#
# This script ensures that test secrets are properly marked to prevent accidental
# leakage of real credentials in CI/CD logs.

set -euo pipefail

# ============================================================================
# Configuration - Sensitive Data Prefix Rules
# ============================================================================
# Define the required prefixes for test secrets to prevent accidental
# leakage of real credentials in CI/CD logs.
#
# To add a new allowed prefix:
# 1. Add it to SENSITIVE_PREFIXES array
# 2. The SENSITIVE_DATA_PATTERN will be automatically updated
#
readonly SENSITIVE_PREFIXES=(
  "SENSITIVE_DATA_"   # Standard prefix for test data
  "sensitive-data-"   # Alternative lowercase prefix
)

# Build regex pattern from prefixes array
# Result: "(SENSITIVE_DATA_|sensitive-data-)"
_build_pattern() {
  local IFS="|"
  echo "(${SENSITIVE_PREFIXES[*]})"
}
readonly SENSITIVE_DATA_PATTERN=$(_build_pattern)

# File patterns
readonly HOOK_FILE_PATTERN="pre-apply-task-hook\.sh$"
readonly HOOK_DIR_PATTERN="*/tests/pre-apply-task-hook.sh"

# Base64 detection threshold
# Minimum length for base64-encoded strings to check for sensitive data.
# Set to 20 to avoid false positives on short base64 strings that are unlikely
# to be actual secrets (e.g., short encoded flags or simple values).
# Adjust this if you need to detect shorter or longer base64-encoded secrets.
readonly MIN_BASE64_LENGTH=20

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1

# Counters
fail_count=0
check_count=0

# ============================================================================
# Helper Functions
# ============================================================================

# Clean command string for easier parsing
# Joins multi-line commands into a single line while preserving backslashes in arguments
# Note: The AWK extraction already handles line continuations, so we just normalize whitespace
clean_command() {
  local command="$1"
  # Simply join lines and normalize spaces
  # Do NOT remove backslashes - they may be part of valid arguments (e.g., "data=\"quoted\"")
  echo "$command" | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Check if a string contains the sensitive data pattern
has_sensitive_data() {
  local text="$1"
  echo "$text" | grep -qE "$SENSITIVE_DATA_PATTERN"
}

# Check if a string contains base64-encoded sensitive data
has_base64_sensitive_data() {
  local text="$1"
  # Try to decode base64 values and check if they contain SENSITIVE_DATA
  # This handles cases like: --from-literal=base64_keytab=U0VOU0lUSVZFX0RBVEFf...
  if echo "$text" | grep -qE "=[A-Za-z0-9+/=]{${MIN_BASE64_LENGTH},}"; then
    local encoded_values
    encoded_values=$(echo "$text" | grep -oE "=[A-Za-z0-9+/=]{${MIN_BASE64_LENGTH},}" | sed 's/^=//')
    for encoded in $encoded_values; do
      if decoded=$(echo "$encoded" | base64 -d 2>/dev/null); then
        if echo "$decoded" | grep -qE "$SENSITIVE_DATA_PATTERN"; then
          return 0
        fi
      fi
    done
  fi
  return 1
}

# Extract variable names from command
extract_variable_names() {
  local command="$1"
  echo "$command" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' | sed 's/[${}]//g' | sort -u
}

# Check if a variable definition contains sensitive data
check_variable_definition() {
  local file_content="$1"
  local var_name="$2"

  local var_def
  var_def=$(echo "$file_content" | awk -v var="$var_name" '
    $0 ~ "^"var"=" || $0 ~ "^"var"=\\$\\(" {
      in_var=1
      content=$0
    }
    in_var {
      print content
      # Check if this is a here-doc
      if (content ~ /<</) {
        # Extract heredoc delimiter dynamically
        # Supports: <<EOF, <<-EOF, <<"EOF", <<'\''EOF'\'', etc.
        delimiter = content
        # Remove everything before <<
        sub(/.*<<-?/, "", delimiter)
        # Remove quotes (single or double)
        gsub(/["'\'']/, "", delimiter)
        # Remove everything after the delimiter (spaces, comments, etc.)
        sub(/[[:space:]].*/, "", delimiter)
        # Trim whitespace
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", delimiter)

        # If we couldn'\''t extract a delimiter, use EOF as fallback
        if (delimiter == "" || length(delimiter) > 50) {
          delimiter = "EOF"
        }

        # Read heredoc content until we find the delimiter
        getline
        while ($0 !~ "^[[:space:]]*"delimiter"[[:space:]]*$") {
          print $0
          if (getline <= 0) break  # Prevent infinite loop on malformed heredoc
        }
        in_var=0
        next
      }
      # Check if line continues
      if (content ~ /\\$/) {
        getline
        content=$0
        next
      }
      in_var=0
    }
  ')

  [[ -n "$var_def" ]] && echo "$var_def" | grep -qE "$SENSITIVE_DATA_PATTERN"
}

# Extract kubectl secret commands from a file using AWK
# Handles multi-line commands with proper quote tracking
extract_kubectl_secrets() {
  local file="$1"

  awk '
    # Skip comment lines
    /^[[:space:]]*#/ {
      next
    }

    /kubectl create secret/ {
      in_secret=1
      secret_cmd=$0
      line_num=NR
      # Track quote state
      in_single_quote=0
      in_double_quote=0
      # Count quotes in current line using temporary copy to avoid mutating $0
      temp_line = $0
      num_single = gsub(/['"'"']/, "&", temp_line)
      temp_line = $0
      num_double = gsub(/"/, "&", temp_line)
      # Update quote state based on count
      if (num_single % 2 == 1) in_single_quote = !in_single_quote
      if (num_double % 2 == 1) in_double_quote = !in_double_quote
      next
    }

    in_secret {
      # Count quotes in current line to track state using temporary copy to avoid mutating $0
      temp_line = $0
      num_single = gsub(/['"'"']/, "&", temp_line)
      temp_line = $0
      num_double = gsub(/"/, "&", temp_line)

      # Update quote state
      if (num_single % 2 == 1) in_single_quote = !in_single_quote
      if (num_double % 2 == 1) in_double_quote = !in_double_quote

      # Append current line to command
      secret_cmd = secret_cmd "\n" $0

      # Determine if command continues
      # Command continues if:
      # 1. Inside quotes (single or double)
      # 2. Line ends with backslash
      # 3. Line is indented (starts with space/tab)
      if (in_single_quote || in_double_quote || $0 ~ /\\$/ || $0 ~ /^[[:space:]]/) {
        next
      } else {
        # Command ended, print it with NUL delimiter
        printf "%d:%s\0", line_num, secret_cmd
        in_secret=0
        secret_cmd=""
        in_single_quote=0
        in_double_quote=0
      }
    }

    END {
      # Print last command if file ends while in_secret
      if (in_secret) {
        printf "%d:%s\0", line_num, secret_cmd
      }
    }
  ' "$file"
}

# Extract filenames from --from-file parameters
extract_from_file_params() {
  local clean_command="$1"

  echo "$clean_command" | python3 -c '
import shlex, sys, re

input_text = sys.stdin.read()

try:
    # Try to parse using shlex for proper shell quoting handling
    args = shlex.split(input_text)
    for arg in args:
        if arg.startswith("--from-file="):
            value = arg[12:]  # Remove "--from-file="
            # If format is key=filename, extract filename part
            if "=" in value:
                value = value.split("=", 1)[1]
            print(value)
except (ValueError, UnicodeDecodeError) as e:
    # shlex.split() can fail on malformed shell syntax or encoding issues
    # Fall back to simple regex extraction
    sys.stderr.write(f"Warning: shlex parsing failed ({e}), using fallback regex extraction\n")
    # Extract --from-file=value patterns using regex
    for match in re.finditer(r"--from-file=([^\s]+)", input_text):
        value = match.group(1)
        # Remove quotes if present
        value = value.strip("\"'\''")
        # If format is key=filename, extract filename part
        if "=" in value:
            value = value.split("=", 1)[1]
        print(value)
except Exception as e:
    # Catch any other unexpected errors to prevent script failure
    sys.stderr.write(f"Error extracting --from-file parameters: {e}\n")
    pass
'
}

# Report validation error with consistent formatting
# Args: file, line_num, command, error_type, [extra_info]
report_validation_error() {
  local file="$1"
  local line_num="$2"
  local command="$3"
  local error_type="$4"
  local extra_info="${5:-}"

  case "$error_type" in
    "from-literal")
      echo "ERROR: $file line $line_num: kubectl create secret with --from-literal does not contain required sensitive data prefix"
      echo "  Command: $(clean_command "$command")"
      echo "  Hint: Add one of these prefixes to at least one value: ${SENSITIVE_PREFIXES[*]}"
      echo "        Or use base64-encoded data containing the prefix"
      ;;
    "from-file")
      echo "ERROR: $file line $line_num: kubectl create secret with --from-file uses a file without required sensitive data prefix"
      echo "  Command: $(clean_command "$command")"
      if [[ -n "$extra_info" ]]; then
        echo "  File creation: $extra_info"
      fi
      echo "  Hint: File should contain one of these prefixes: ${SENSITIVE_PREFIXES[*]}"
      ;;
    *)
      echo "ERROR: $file line $line_num: kubectl create secret does not contain required sensitive data prefix"
      echo "  Command: $(clean_command "$command")"
      echo "  Hint: Add one of these prefixes: ${SENSITIVE_PREFIXES[*]}"
      ;;
  esac
}

# Common validation logic for checking sensitive data in text
# Args: text_to_check, file_content (for variable lookup)
# Returns: 0 if valid (contains sensitive prefix), 1 otherwise
validate_has_sensitive_prefix() {
  local text_to_check="$1"
  local file_content="$2"

  # First check: Direct sensitive data in text
  if has_sensitive_data "$text_to_check"; then
    return 0  # OK
  fi

  # Second check: Base64-encoded sensitive data
  if has_base64_sensitive_data "$text_to_check"; then
    return 0  # OK
  fi

  # Third check: Variables containing sensitive data
  if echo "$text_to_check" | grep -q '\$'; then
    local var_names
    var_names=$(extract_variable_names "$text_to_check")

    for var in $var_names; do
      if check_variable_definition "$file_content" "$var"; then
        return 0  # OK - variable contains sensitive data
      fi
    done
  fi

  # Failed all checks
  return 1
}

# Check --from-literal commands for sensitive data
check_from_literal() {
  local file="$1"
  local file_content="$2"
  local line_num="$3"
  local command="$4"
  local clean_command="$5"

  # Use common validation logic
  if validate_has_sensitive_prefix "$clean_command" "$file_content"; then
    return 0  # OK
  fi

  # Failed validation - report error
  report_validation_error "$file" "$line_num" "$command" "from-literal"
  return 1
}

# Check --from-file commands for sensitive data
check_from_file() {
  local file="$1"
  local file_content="$2"
  local line_num="$3"
  local command="$4"
  local clean_command="$5"

  local filenames
  filenames=$(extract_from_file_params "$clean_command")

  while IFS= read -r filename; do
    [[ -z "$filename" ]] && continue

    # Skip variable-based filenames
    if echo "$filename" | grep -q '\$'; then
      local base_var
      base_var=$(echo "$filename" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' | head -1 | sed 's/[${}]//g')

      # Skip ssh-keygen generated files (binary keys)
      if echo "$file_content" | grep -q "ssh-keygen.*$base_var"; then
        continue
      fi

      # Skip other variable-based files (can't reliably check)
      continue
    fi

    # Look for file creation commands
    local file_creation
    file_creation=$(echo "$file_content" | grep -E "(echo|cat|printf).*>.*$filename" | head -1)

    if [[ -n "$file_creation" ]]; then
      # Use common validation logic
      if ! validate_has_sensitive_prefix "$file_creation" "$file_content"; then
        report_validation_error "$file" "$line_num" "$command" "from-file" "$file_creation"
        return 1
      fi
    fi
  done <<< "$filenames"

  return 0
}

# ============================================================================
# Main Logic
# ============================================================================

echo "Checking kubectl create secret commands for required sensitive data prefixes..."
echo "Required prefixes: ${SENSITIVE_PREFIXES[*]}"
echo ""

# Find files to check (using array for safe whitespace handling)
declare -a files
if [[ -n "${CHANGED_FILES:-}" ]]; then
  # If CHANGED_FILES is set, only check those files
  # Note: CHANGED_FILES should be newline or space-delimited
  while IFS= read -r file; do
    [[ -n "$file" ]] && [[ "$file" =~ $HOOK_FILE_PATTERN ]] && files+=("$file")
  done < <(echo "${CHANGED_FILES}" | tr ' ' '\n')
else
  # Otherwise check all pre-apply-task-hook.sh files using null-delimited find
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find tasks -path "$HOOK_DIR_PATTERN" -type f -print0 2>/dev/null || true)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No pre-apply-task-hook.sh files to check"
  exit $EXIT_SUCCESS
fi

# Process each file
for file in "${files[@]}"; do
  echo "Checking: $file"

  # Read entire file content once for variable tracking
  file_content=$(cat "$file")

  # Extract and process kubectl create secret commands
  while IFS= read -r -d '' line_and_command; do
    check_count=$((check_count + 1))

    # Split line number and command
    line_num="${line_and_command%%:*}"
    command="${line_and_command#*:}"

    # Clean command for parsing
    clean_cmd=$(clean_command "$command")

    # Check --from-literal commands
    if echo "$clean_cmd" | grep "kubectl create secret" | grep -q -- "--from-literal"; then
      if ! check_from_literal "$file" "$file_content" "$line_num" "$command" "$clean_cmd"; then
        fail_count=$((fail_count + 1))
      fi
    fi

    # Check --from-file commands
    if echo "$clean_cmd" | grep -q -- "--from-file"; then
      if ! check_from_file "$file" "$file_content" "$line_num" "$command" "$clean_cmd"; then
        fail_count=$((fail_count + 1))
      fi
    fi
  done < <(extract_kubectl_secrets "$file")
done

# Summary
echo ""
echo "=========================================="
echo "Checked $check_count kubectl create secret command(s)"
echo ""

if [[ $fail_count -ne 0 ]]; then
  echo "❌ FAILED: $fail_count command(s) missing required sensitive data prefix"
  echo ""
  echo "To fix: Add one of these prefixes to at least one secret value:"
  for prefix in "${SENSITIVE_PREFIXES[@]}"; do
    echo "  - $prefix"
  done
  echo ""
  echo "Example: kubectl create secret generic my-secret --from-literal=key=${SENSITIVE_PREFIXES[0]}value"
  exit $EXIT_FAILURE
fi

echo "✅ SUCCESS: All kubectl create secret commands contain required sensitive data prefix"
exit $EXIT_SUCCESS
