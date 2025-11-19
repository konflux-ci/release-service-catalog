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

            # Check if this is a multi-arch build based on directory structure
            if [ -f "$(params.dataDir)/arch_count.txt" ]; then
                arch_count=$(cat "$(params.dataDir)/arch_count.txt")
                if [ "$arch_count" -gt 1 ]; then
                    echo "Multi-architecture build detected, checking architecture-specific directories"
                    # For multi-arch, check for architecture-specific directories
                    expected_archs=("amd64" "arm64")
                    for arch in "${expected_archs[@]}"; do
                        TARGET_DIR="${DRIVER_VENDOR}_${DRIVER_VERSION}_${KERNEL_VERSION}_${arch}"
                        echo "Checking for files in architecture-specific target directory: ${TARGET_DIR}"

                        if [ -d "${TARGET_DIR}" ] && ls "${TARGET_DIR}"/*.ko 1> /dev/null 2>&1; then
                            echo "SUCCESS: Found .ko files in ${TARGET_DIR}"
                        else
                            echo "ERROR: Did not find .ko files in ${TARGET_DIR}"
                            ls -la "${TARGET_DIR}" || echo "Directory does not exist"
                            exit 1
                        fi
                    done

                    # Also check for summary directory
                    if ls multi-arch-summary_* 1> /dev/null 2>&1; then
                        echo "SUCCESS: Found multi-arch summary directory"
                    else
                        echo "WARNING: No multi-arch summary directory found"
                    fi
                else
                    # Single architecture
                    TARGET_DIR="${DRIVER_VENDOR}_${DRIVER_VERSION}_${KERNEL_VERSION}"
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
                TARGET_DIR="${DRIVER_VENDOR}_${DRIVER_VERSION}_${KERNEL_VERSION}"
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