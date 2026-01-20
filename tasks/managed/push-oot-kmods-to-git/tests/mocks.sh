set -eux

git() {
    case "$1" in
        lfs)
            echo "Mocking LFS install: $*"
            ;;
        clone)
            echo "Mocking clone command: $*"
            mkdir local-artifacts
            ;;
        sparse-checkout)
            echo "Mocking sparse-checkout: $*"
            ;;
        config)
            echo "Skipping git config: $*"
            ;;
        checkout)
            echo "Skipping git checkout: $*"
            ;;

        add)
            echo "Mock git add: $*"

            # Log the TARGET_DIR for verification
            if [ -n "${KERNEL_VERSION:-}" ]; then
                echo "KERNEL_VERSION=${KERNEL_VERSION}" >> /var/workdir/git_paths.log
            fi

            # Check if this is a multi-arch build based on directory structure
            if [ -f "$(params.dataDir)/arch_count.txt" ]; then
                arch_count=$(cat "$(params.dataDir)/arch_count.txt")
                if [ "$arch_count" -gt 1 ]; then
                    echo "Multi-architecture build detected, checking architecture-specific directories"
                    # For multi-arch, check for architecture-specific directories
                    expected_archs=("amd64" "arm64")
                    for arch in "${expected_archs[@]}"; do
                        TARGET_DIR="${DRIVER_VENDOR}/${DRIVER_VERSION}/${KERNEL_VERSION}/${arch}"
                        echo "Checking for files in architecture-specific target directory: ${TARGET_DIR}"

                        if [ -d "${TARGET_DIR}" ] && ls "${TARGET_DIR}"/*.ko 1> /dev/null 2>&1; then
                            echo "SUCCESS: Found .ko files in ${TARGET_DIR}"
                        else
                            echo "ERROR: Did not find .ko files in ${TARGET_DIR}"
                            ls -la "${TARGET_DIR}" || echo "Directory does not exist"
                            exit 1
                        fi
                    done

                    # Also check for summary directory under the kernel version path
                    SUMMARY_DIR="${DRIVER_VENDOR}/${DRIVER_VERSION}/${KERNEL_VERSION}/multi-arch-summary"
                    if [ -d "${SUMMARY_DIR}" ]; then
                        echo "SUCCESS: Found multi-arch summary directory at ${SUMMARY_DIR}"
                    else
                        echo "WARNING: No multi-arch summary directory found at ${SUMMARY_DIR}"
                    fi
                else
                    # Single architecture
                    TARGET_DIR="${DRIVER_VENDOR}/${DRIVER_VERSION}/${KERNEL_VERSION}"
                    echo "Checking for files in single-arch target directory: ${TARGET_DIR}"

                    if [ -f "${TARGET_DIR}/mod1.ko" ] && [ -f "${TARGET_DIR}/mod2.ko" ]; then
                        echo "SUCCESS: Found .ko files in ${TARGET_DIR}"
                    else
                        echo "ERROR: Did not find .ko files in ${TARGET_DIR}"
                        ls -la "${TARGET_DIR}"
                        exit 1
                    fi
                fi
            else
                # Fallback to original single-arch logic
                TARGET_DIR="${DRIVER_VENDOR}/${DRIVER_VERSION}/${KERNEL_VERSION}"
                echo "Checking for files in target directory: ${TARGET_DIR}"

                if [ -f "${TARGET_DIR}/mod1.ko" ] && [ -f "${TARGET_DIR}/mod2.ko" ]; then
                    echo "SUCCESS: Found .ko files in ${TARGET_DIR}"
                else
                    echo "ERROR: Did not find .ko files in ${TARGET_DIR}"
                    ls -la "${TARGET_DIR}"
                    exit 1
                fi
            fi
            ;;

        commit)
            echo "Mocking commit: $*"
            ;;
        push)
            echo "Skipping push: $*"
            ;;
        *)
            echo "Unknown subcommand: $1"
            ;;
    esac
}

check_git_paths() {
    # Verify kernel version cleaning: the test uses KERNEL_VERSION="6.5.0.x86_64"
    # The task should strip the .x86_64 suffix, so git paths should use "6.5.0" not "6.5.0.x86_64"
    PATHS_LOG="/var/workdir/git_paths.log"
    if [ -f "$PATHS_LOG" ]; then
        echo ""
        echo "Verifying KERNEL_VERSION architecture suffix was stripped..."
        # Use grep -F for literal/fixed string matching (dots are literal, not regex)
        if grep -F -q "6.5.0.x86_64" "$PATHS_LOG"; then
            echo "ERROR: Found dirty kernel version (6.5.0.x86_64) in git paths!"
            echo "The .x86_64 suffix should have been stripped."
            echo "Paths log:"
            cat "$PATHS_LOG"
            exit 1
        else
            echo "SUCCESS: Kernel version architecture suffix was properly stripped"
            echo "All git operations used cleaned KERNEL_VERSION: 6.5.0 (not 6.5.0.x86_64)"
        fi
    fi
}