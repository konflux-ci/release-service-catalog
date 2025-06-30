#!/bin/bash

# This script will verify that the README.md of all task and 
# pipeline directories provided matches the output of hack/readme_generator.sh
# to ensure that README files are up to date.
#
# Task and pipeline directories are provided
# either via README_ITEMS env var, or as arguments
# when running the script.

# yield empty strings for unmatched patterns
shopt -s nullglob

CLI_README_ITEMS=""

show_help() {
  echo "Usage: $0 [item1] [item2] [...]"
  echo
  echo Flags:
  echo "  --help: Show this help message"
  echo
  echo "Items are task or pipeline directories. They can be supplied"
  echo "either as arguments or via the README_ITEMS environment variable."
  echo
  echo "Examples:"
  echo "  $0 tasks/managed/apply-mapping"
  echo
  echo "  or"
  echo
  echo '  export README_ITEMS="mydir/tasks/apply-mapping some/other/dir"'
  echo "  $0"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      show_help
      ;;
    --*)
      show_help
      ;;
    *)
      CLI_README_ITEMS+="$1 "
      shift
      ;;
  esac
done

if [[ -n "$CLI_README_ITEMS" ]]; then
  README_ITEMS="${CLI_README_ITEMS% }"  # Remove trailing space
else
  README_ITEMS="${README_ITEMS:-}"      # Use env var or empty string
fi

if [ -z "${README_ITEMS}" ]
then
  show_help
fi

# Check that all directories exist. If not, fail
for ITEM in $README_ITEMS
do
  if [[ -d "$ITEM" ]]; then
    true
  else
    echo "Error: Invalid file or directory: $ITEM"
    exit 1
  fi
done

for ITEM in $README_ITEMS
do
  echo "Task/Pipeline item: $ITEM"
  ITEM_NAME=$(basename "$ITEM")
  ITEM_DIR=$(echo "$ITEM" | cut -d '/' -f -3)
  echo "  Task/Pipeline name: $ITEM_NAME"

  ITEM_PATH=${ITEM_DIR}/${ITEM_NAME}.yaml
  if [ ! -f "$ITEM_PATH" ]
  then
    echo "Error: Task/Pipeline file does not exist: $ITEM_PATH"
    exit 1
  fi

  README_PATH=${ITEM_DIR}/README.md
  if [ ! -f "$README_PATH" ]
  then
    echo "Error: README does not exist in $ITEM_DIR"
    exit 1
  fi

  if [[ "$(hack/readme_generator.sh --dry-run "$ITEM_DIR")" != "$(cat "$README_PATH")" ]]; then
    diff <(hack/readme_generator.sh --dry-run "$ITEM_DIR") <(cat "$README_PATH")
    echo "  Error: README.md has not been updated. Please use hack/readme-generator.sh to" \
      "generate a new README.md to replace $ITEM/README.md"
    exit 1
  else
    echo "  README.md for $ITEM_DIR is up to date"
  fi

done
