#!/usr/bin/env bash

# Check that all kubectl create secret commands in pre-apply-task-hook.sh files
# contain at least one SENSITIVE_DATA_ or sensitive-data- string when using --from-literal

set -euo pipefail

fail=0

echo "Checking that kubectl create secret commands contain SENSITIVE_DATA_ or sensitive-data- in pre-apply-task-hook.sh files"

# Find all pre-apply-task-hook.sh files
if [[ -n "${CHANGED_FILES:-}" ]]; then
  # If CHANGED_FILES is set, only check those files
  files=$(echo "${CHANGED_FILES}" | tr ' ' '\n' | grep -E 'pre-apply-task-hook\.sh$' || true)
else
  # Otherwise check all pre-apply-task-hook.sh files
  files=$(find tasks -path "*/tests/pre-apply-task-hook.sh" -type f)
fi

if [[ -z "$files" ]]; then
  echo "No pre-apply-task-hook.sh files to check"
  exit 0
fi

for file in $files; do
  echo "Checking: $file"

  # Read the entire file content for variable tracking
  file_content=$(cat "$file")

  # Extract kubectl create secret commands (handle multi-line commands)
  # Use awk to track multi-line kubectl create secret commands
  # Use process substitution to avoid subshell issues with the while loop
  while IFS=: read -r line_num command; do

    # Clean up the command (remove backslashes and newlines for easier parsing)
    clean_command=$(echo "$command" | tr '\n' ' ' | sed 's/\\//g' | sed 's/  */ /g')

    # Check if command uses --from-literal
    if echo "$clean_command" | grep "kubectl create secret" | grep -q -- "--from-literal"; then

      # Check if command contains SENSITIVE_DATA_ or sensitive-data- directly
      if echo "$clean_command" | grep -qE "(SENSITIVE_DATA_|sensitive-data-)"; then
        continue  # This command is OK
      fi

      # Check if command uses variables (contains $)
      if echo "$clean_command" | grep -q '\$'; then
        # Extract variable names used in the command
        var_names=$(echo "$clean_command" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' | sed 's/[${}]//g' | sort -u)

        # Check if any of these variables are defined with SENSITIVE_DATA_ or sensitive-data- in the file
        found_sensitive=0
        for var in $var_names; do
          # Look for variable assignment: var_name=... or var_name=$(...)
          # Extract the variable definition and check if it contains SENSITIVE_DATA_ or sensitive-data-
          var_def=$(echo "$file_content" | awk -v var="$var" '
            $0 ~ "^"var"=" || $0 ~ "^"var"=\\$\\(" {
              in_var=1
              content=$0
            }
            in_var {
              print content
              # Check if this is a here-doc
              if (content ~ /<</) {
                getline
                while ($0 !~ /^EOF/ && $0 !~ /^[[:space:]]*EOF/) {
                  print $0
                  getline
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

          if [[ -n "$var_def" ]] && echo "$var_def" | grep -qE "(SENSITIVE_DATA_|sensitive-data-)"; then
            found_sensitive=1
            break
          fi
        done

        if [[ $found_sensitive -eq 1 ]]; then
          continue  # Variable contains SENSITIVE_DATA_ or sensitive-data-, command is OK
        fi
      fi

      # If we reach here, the command doesn't have SENSITIVE_DATA_ or sensitive-data-
      echo "ERROR: $file line $line_num: kubectl create secret with --from-literal does not contain SENSITIVE_DATA_ or sensitive-data-"
      echo "  Command: $(echo "$command" | tr '\n' ' ' | sed 's/  */ /g')"
      fail=1
    fi

    # Check if command uses --from-file
    if echo "$clean_command" | grep -q -- "--from-file"; then
      # Extract filenames from --from-file parameters
      # Handles both --from-file=filename and --from-file=key=filename
      filenames=$(echo "$clean_command" | grep -oE -- '--from-file=[a-zA-Z0-9_=./-]+' | sed 's/--from-file=//' | sed 's/^[^=]*=//')

      for filename in $filenames; do
        # Skip if filename contains variables (like ${TMPDIR}/${OS})
        if echo "$filename" | grep -q '\$'; then
          # For variable-based filenames, try to check if the creation command has SENSITIVE_DATA_
          # Extract the variable parts
          base_var=$(echo "$filename" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' | head -1 | sed 's/[${}]//g')

          # Look for commands that create files with this variable pattern
          # For example: ssh-keygen generates binary keys, so we skip those
          if echo "$file_content" | grep -q "ssh-keygen.*$base_var"; then
            continue  # ssh-keygen creates binary keys, skip validation
          fi

          # For other variable-based files, we can't reliably check, so skip
          continue
        fi

        # Look for echo/cat/printf commands that create this file
        # Search for lines like: echo "..." > filename or cat << EOF > filename
        file_creation=$(echo "$file_content" | grep -E "(echo|cat|printf).*>.*$filename" | head -1)

        if [[ -n "$file_creation" ]]; then
          # Check if the file creation command contains SENSITIVE_DATA_ or sensitive-data-
          if ! echo "$file_creation" | grep -qE "(SENSITIVE_DATA_|sensitive-data-)"; then
            echo "ERROR: $file line $line_num: kubectl create secret with --from-file uses a file without SENSITIVE_DATA_ or sensitive-data-"
            echo "  Command: $(echo "$command" | tr '\n' ' ' | sed 's/  */ /g')"
            echo "  File creation: $file_creation"
            fail=1
          fi
        fi
        # If we can't find the file creation command in the script, skip (might be external)
      done
    fi
  done < <(awk '
    # Skip comment lines
    /^[[:space:]]*#/ {
      next
    }
    /kubectl create secret/ {
      in_secret=1
      secret_cmd=$0
      line_num=NR
      next
    }
    in_secret {
      # Continue collecting lines if they end with backslash or are indented
      if ($0 ~ /\\$/ || $0 ~ /^[[:space:]]/) {
        secret_cmd = secret_cmd "\n" $0
        next
      } else {
        # Command ended, print it
        print line_num ":" secret_cmd
        in_secret=0
        secret_cmd=""
      }
    }
    END {
      # Print last command if file ends while in_secret
      if (in_secret) {
        print line_num ":" secret_cmd
      }
    }
  ' "$file")
done

if [[ $fail -ne 0 ]]; then
  echo ""
  echo "FAILED: Some kubectl create secret commands are missing SENSITIVE_DATA_ or sensitive-data- prefix"
  exit 1
fi

echo ""
echo "SUCCESS: All kubectl create secret commands contain SENSITIVE_DATA_ or sensitive-data-"
