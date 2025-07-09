#!/usr/bin/env bash

# Automatically generates a README.md for tasks and pipelines.
# Without the '--dry-run' flag, this will automatically replace the current task/pipeline README.md
# A check will be run on each pull request to make sure the README.md matches this script's output.
#
# This script takes the '.spec.description' and '.spec.params' fields 
# from the associated task/pipeline to create the description and table in the README.md of this task/pipeline.
#
# If you wish to update the README.md description and table, please update the '.spec.description' or '.spec.table'
# field in the Tekton task/pipeline and run this script, instead of changing it manually in the README.md.
#
# Usage: ./readme_generator.sh tasks/apply-mapping

show_help() {
  echo "Usage: $0 [--dry-run] [item1] [item2] [...]"
  echo
  echo Flags:
  echo "  --help: Show this help message"
  echo "  --dry-run: Print the updated README.md files without changing"
  echo "             the current README.md in each task and pipeline"
  echo
  echo "Items are task or pipeline directories. They can be supplied"
  echo "either as arguments or via the README_ITEMS environment variable."
  echo
  echo "Examples:"
  echo "  $0 tasks/managed/apply-mapping"
  echo "  $0 --dry-run tasks/managed/apply-mapping"
  echo
  echo "  or"
  echo
  echo '  export README_ITEMS="mydir/tasks/apply-mapping some/other/dir"'
  echo "  $0"
  exit 1
}

DRY_RUN=false
CLI_README_ITEMS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      show_help
      ;;
    --*)
      show_help
      ;;
    *)
      CLI_README_ITEMS+=("$1")
      shift
      ;;
  esac
done

if [[ "${#CLI_README_ITEMS[@]}" -gt 0 ]]; then
  README_ITEMS=("${CLI_README_ITEMS[@]}")
else
  read -r -a README_ITEMS <<< "${README_ITEMS[@]}"
fi

if [ "${#README_ITEMS[@]}" -eq 0 ]
then
  show_help
fi

# Check that all directories exist. If not, fail
for ITEM in "${README_ITEMS[@]}"
do
  if [[ ! -d "$ITEM" ]]; then
    echo "Error: Invalid file or directory: $ITEM"
    exit 1
  fi

  ITEM_NAME=$(basename "$ITEM")
  ITEM_DIR=$(cut -d '/' -f -3 <<< "$ITEM")

  ITEM_PATH=${ITEM_DIR}/${ITEM_NAME}.yaml
  if [ ! -f "$ITEM_PATH" ]
  then
    echo "Error: Task/Pipeline file does not exist: $ITEM_PATH"
    exit 1
  fi
done

# Creating after checking all directories exist to simplify cleanup
TEMP_README=$(mktemp)

# Adds trailing whitespace/hyphens to table until num_spaces is reached
spaces() { # (num_spaces, string)
  for ((i=0; i < $(($1-${#2})); i++)); do
    echo -n " "
  done
}

dashes() { # (num_spaces, string)
  for ((i=0; i < $(($1-${#2})); i++)); do
    echo -n "-"
  done
}

# Add table
for ITEM in "${README_ITEMS[@]}"
do
  ITEM_DIR=$(cut -d '/' -f -3 <<< "$ITEM")
  BASE_DIR=$(cut -d '/' -f 1 <<< "$ITEM")
  ITEM_NAME=$(basename "$ITEM")
  ITEM_PATH=${ITEM_DIR}/${ITEM_NAME}.yaml

  # Don't print any debug messages when dry run is true
  $DRY_RUN || echo "Task/Pipeline item: $ITEM"
  $DRY_RUN || echo "  Task/Pipeline name: $ITEM_NAME"

  # Variables for description of README.md
  METADATA_NAME=$(yq .metadata.name "$ITEM_PATH")
  SPEC_DESCRIPTION=$(yq .spec.description "$ITEM_PATH")

  # Variables for table
  PARAMS=$(yq .spec.params "$ITEM_PATH")

  # Get the maximum length for each column of table
  LONGEST_NAME=0
  LONGEST_DESCRIPTION=0
  LONGEST_DEFAULT=13
  LONGEST_OPTIONAL=8

  for ((i=0; i < $(yq length <<< "$PARAMS"); i++)); do
    # Get rid of newlines and remove trailing whitespace
    NAME="$(yq .[$i].name <<< "$PARAMS" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    DESCRIPTION="$(yq .[$i].description <<< "$PARAMS" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    DEFAULT="$(yq .[$i].default <<< "$PARAMS" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

    if [[ ${#NAME} -gt $LONGEST_NAME ]]; then
      LONGEST_NAME=${#NAME}
    fi
    
    if [[ ${#DESCRIPTION} -gt $LONGEST_DESCRIPTION ]]; then
      LONGEST_DESCRIPTION=${#DESCRIPTION}
    fi

    if [[ ${#DEFAULT} -gt $LONGEST_DEFAULT ]]; then
      LONGEST_DEFAULT=${#DEFAULT}
    fi
  done

  # create table and write contents to file
  {
    if [[ "$BASE_DIR" == "pipelines" && "$ITEM_NAME" != *-pipeline ]]; then
      echo "# $METADATA_NAME pipeline"
    elif [[ "$BASE_DIR" == "pipelines" && "$ITEM_NAME" == *-pipeline ]]; then
      echo "# ${METADATA_NAME%-pipeline} pipeline"
    else
      echo "# $METADATA_NAME"
    fi
    echo
    echo "$SPEC_DESCRIPTION"
    echo
    echo "## Parameters"
    echo

    # Print first row of table
    echo "| Name$(spaces "$LONGEST_NAME" "Name")" \
      "| Description$(spaces "$LONGEST_DESCRIPTION" "Description")" \
      "| Optional$(spaces "$LONGEST_OPTIONAL" "Optional")" \
      "| Default value$(spaces "$LONGEST_DEFAULT" "Default value") |"

    # Print second row of table
    echo -n "|-$(dashes "$LONGEST_NAME" "")-|-$(dashes "$LONGEST_DESCRIPTION" "")"
    echo "-|-$(dashes "$LONGEST_OPTIONAL" "")-|-$(dashes "$LONGEST_DEFAULT" "")-|"

    # Print remaining rows of table
    for ((i=0; i < $(yq length <<< "$PARAMS"); i++)); do
      # Get rid of newlines and remove trailing whitespace
      NAME="$(yq .[$i].name <<< "$PARAMS" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      DESCRIPTION="$(yq .[$i].description <<< "$PARAMS" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      DEFAULT="$(yq .[$i].default <<< "$PARAMS" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

      # Check that default doesn't exist
      if [[ $(yq ".[$i] | has(\"default\")" <<< "$PARAMS") == "false" ]]; then
        echo "| $NAME$(spaces "$LONGEST_NAME" "$NAME")" \
          "| $DESCRIPTION$(spaces "$LONGEST_DESCRIPTION" "$DESCRIPTION")" \
          "| No$(spaces "$LONGEST_OPTIONAL" "No")" \
          "| -$(spaces "$LONGEST_DEFAULT" "-") |"
      else
        # Special case to show default empty strings as "" in table
        if [[ -z "$DEFAULT" ]]; then
          DEFAULT="\"\""
        fi

        echo "| $NAME$(spaces "$LONGEST_NAME" "$NAME")" \
          "| $DESCRIPTION$(spaces "$LONGEST_DESCRIPTION" "$DESCRIPTION")" \
          "| Yes$(spaces "$LONGEST_OPTIONAL" "Yes")" \
          "| $DEFAULT$(spaces "$LONGEST_DEFAULT" "$DEFAULT") |"
      fi
    done
  } > "$TEMP_README"

  if [[ $DRY_RUN == "true" ]]; then
    cat "$TEMP_README"
  else
    cat "$TEMP_README" > "${ITEM_DIR}/README.md"
    echo "  README.md for $ITEM_DIR updated"
  fi
done

# Cleanup
if [ -v TEMP_README ]; then
  rm -f "$TEMP_README"
fi
