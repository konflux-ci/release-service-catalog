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
            TARGET_DIR="${DRIVER_VENDOR}_${DRIVER_VERSION}_${KERNEL_VERSION}"
            echo "Checking for files in target directory: ${TARGET_DIR}"
            
            if [ -f "${TARGET_DIR}/mod1.ko" ] && [ -f "${TARGET_DIR}/mod2.ko" ]; then
                echo "SUCCESS: Found .ko files in ${TARGET_DIR}"
            else
                echo "ERROR: Did not find .ko files in ${TARGET_DIR}"
                ls -la "${TARGET_DIR}"
                exit 1
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