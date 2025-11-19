#!/usr/bin/env bash
set -eux

# Simple mocks to create dummy RPM files for testing

function rpmbuild() {
  echo "Mock rpmbuild called with: $*"

  # Parse arguments to find topdir, sourcedir, and spec file
  local topdir=""
  local sourcedir=""
  local spec_file=""
  local build_binary=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --define)
        shift
        if [[ $1 == "_topdir "* ]]; then
          topdir="${1#_topdir }"
        elif [[ $1 == "_sourcedir "* ]]; then
          sourcedir="${1#_sourcedir }"
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

    # Extract package info from spec file
    local package_name=$(grep "^Name:" "$spec_file" | awk '{print $2}' | head -1)
    local package_version=$(grep "^Version:" "$spec_file" | awk '{print $2}' | head -1)
    local package_release=$(grep "^Release:" "$spec_file" | awk '{print $2}' | head -1)
    local build_arch=$(grep "^BuildArch:" "$spec_file" | awk '{print $2}' | head -1 || echo "x86_64")

    # Create output directory
    local rpms_dir="$topdir/RPMS/$build_arch"
    mkdir -p "$rpms_dir"

    # Create dummy RPM file
    local rpm_filename="${package_name}-${package_version}-${package_release}.${build_arch}.rpm"
    local rpm_path="$rpms_dir/$rpm_filename"

    # Create a simple dummy file that just needs to exist and not be empty
    echo "MOCK RPM FILE" > "$rpm_path"
    echo "Package: $package_name" >> "$rpm_path"
    echo "Version: $package_version" >> "$rpm_path"
    echo "Release: $package_release" >> "$rpm_path"
    echo "Architecture: $build_arch" >> "$rpm_path"
    echo "Created by mock rpmbuild for testing" >> "$rpm_path"

    echo "Mock rpmbuild: Created dummy RPM: $rpm_path"
    return 0
  else
    echo "Mock rpmbuild: Missing required arguments or spec file"
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