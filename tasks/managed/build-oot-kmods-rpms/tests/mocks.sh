#!/usr/bin/env bash
set -eux

# Simple mocks to create dummy RPM files for testing

function rpmbuild() {
  echo "Mock rpmbuild called with: $*"

  # Parse arguments to find topdir, sourcedir, spec file, and macro definitions
  local topdir=""
  local sourcedir=""
  local spec_file=""
  local build_binary=false
  declare -A macros  # Associative array for macro definitions

  while [[ $# -gt 0 ]]; do
    case $1 in
      --define)
        shift
        if [[ $1 == "_topdir "* ]]; then
          topdir="${1#_topdir }"
        elif [[ $1 == "_sourcedir "* ]]; then
          sourcedir="${1#_sourcedir }"
        else
          # Parse macro definition: "name value"
          local macro_name="${1%% *}"
          local macro_value="${1#* }"
          macros["$macro_name"]="$macro_value"
        fi
        shift
        ;;
      -bb)
        build_binary=true
        shift
        ;;
      *.spec)
        spec_file="$1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  # Only proceed if we have the necessary arguments
  if [ "$build_binary" = true ] && [ -n "$topdir" ] && [ -n "$spec_file" ] && [ -f "$spec_file" ]; then
    echo "Mock rpmbuild: Creating dummy RPM from spec: $spec_file"

    # Function to expand a single macro reference
    expand_macro() {
      local value="$1"
      # Expand %{macro_name} references
      for macro_name in "${!macros[@]}"; do
        value="${value//\%\{${macro_name}\}/${macros[$macro_name]}}"
      done
      echo "$value"
    }

    # Extract package info from spec file and expand macros
    local package_name=$(grep "^Name:" "$spec_file" | awk '{print $2}' | head -1)
    package_name=$(expand_macro "$package_name")

    local package_version=$(grep "^Version:" "$spec_file" | awk '{print $2}' | head -1)
    package_version=$(expand_macro "$package_version")

    local package_release=$(grep "^Release:" "$spec_file" | awk '{print $2}' | head -1)
    package_release=$(expand_macro "$package_release")

    local build_arch=$(grep "^BuildArch:" "$spec_file" | awk '{print $2}' | head -1 || echo "x86_64")
    build_arch=$(expand_macro "$build_arch")

    # Create output directory
    local rpms_dir="$topdir/RPMS/$build_arch"
    mkdir -p "$rpms_dir"

    # Extract additional metadata from spec file
    local license=$(grep "^License:" "$spec_file" | awk '{print $2}' | head -1)
    license=$(expand_macro "$license")

    local summary=$(grep "^Summary:" "$spec_file" | cut -d':' -f2- | sed 's/^[[:space:]]*//' | head -1)
    summary=$(expand_macro "$summary")

    # Extract description (first non-empty line after %description)
    local description=$(awk '/^%description/,/^%/ {if (NF && !/^%/) print}' "$spec_file" | head -1)
    description=$(expand_macro "$description")

    # Create dummy RPM file
    local rpm_filename="${package_name}-${package_version}-${package_release}.${build_arch}.rpm"
    local rpm_path="$rpms_dir/$rpm_filename"

    # Create a simple dummy file with metadata
    echo "MOCK RPM FILE" > "$rpm_path"
    echo "Name: $package_name" >> "$rpm_path"
    echo "Version: $package_version" >> "$rpm_path"
    echo "Release: $package_release" >> "$rpm_path"
    echo "Architecture: $build_arch" >> "$rpm_path"
    echo "License: $license" >> "$rpm_path"
    echo "Summary: $summary" >> "$rpm_path"
    echo "Description: $description" >> "$rpm_path"
    echo "Created by mock rpmbuild for testing" >> "$rpm_path"

    echo "Mock rpmbuild: Created dummy RPM: $rpm_path"
    return 0
  else
    echo "Mock rpmbuild: Missing required arguments or spec file"
    return 1
  fi
}

function rpm() {
  echo "Mock rpm called with: $*" >&2

  # Parse arguments
  local query_package=false
  local query_format=""
  local rpm_file=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -qp)
        query_package=true
        shift
        ;;
      --queryformat)
        shift
        query_format="$1"
        shift
        ;;
      *.rpm)
        rpm_file="$1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  # If querying a package file
  if [ "$query_package" = true ] && [ -n "$rpm_file" ] && [ -f "$rpm_file" ]; then
    # Extract the requested field from the mock RPM file
    case "$query_format" in
      '%{LICENSE}')
        grep "^License:" "$rpm_file" | cut -d':' -f2- | sed 's/^[[:space:]]*//'
        ;;
      '%{SUMMARY}')
        grep "^Summary:" "$rpm_file" | cut -d':' -f2- | sed 's/^[[:space:]]*//'
        ;;
      '%{DESCRIPTION}')
        grep "^Description:" "$rpm_file" | cut -d':' -f2- | sed 's/^[[:space:]]*//'
        ;;
      '%{NAME}')
        grep "^Name:" "$rpm_file" | cut -d':' -f2- | sed 's/^[[:space:]]*//'
        ;;
      '%{VERSION}')
        grep "^Version:" "$rpm_file" | cut -d':' -f2- | sed 's/^[[:space:]]*//'
        ;;
      '%{RELEASE}')
        grep "^Release:" "$rpm_file" | cut -d':' -f2- | sed 's/^[[:space:]]*//'
        ;;
      *)
        echo "Mock rpm: Unknown query format: $query_format" >&2
        return 1
        ;;
    esac
    return 0
  else
    echo "Mock rpm: Invalid arguments" >&2
    return 1
  fi
}

function rpm2cpio() {
  echo "Mock rpm2cpio called with: $*"
  # For simple testing, just return successfully
  # Tests no longer require RPM extraction
  return 0
}

function cpio() {
  echo "Mock cpio called with: $*"
  # For simple testing, just return successfully
  # Tests no longer require RPM extraction
  return 0
}