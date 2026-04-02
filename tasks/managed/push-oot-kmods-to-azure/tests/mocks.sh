set -eux

# Ensure our mock az function takes precedence over any real az binary
function az() {
    echo "Mock 'az' called with: $*"

    case "$1" in
        login)
            echo "Mocking az login..."
            # More flexible validation - just check that it's a service principal login with mock credentials
            if [[ "$*" != *"--service-principal"* ]]; then
               echo "ERROR: az login not called as service-principal"
               return 1
            fi
            if [[ "$*" != *"mock-client-id"* ]]; then
               echo "ERROR: az login called without mock-client-id"
               return 1
            fi
            if [[ "$*" != *"mock-client-secret"* ]]; then
               echo "ERROR: az login called without mock-client-secret"
               return 1
            fi
            echo "SUCCESS: Mock az login completed with service principal"
            ;;

        storage)
            case "$2" in
                container)
                    if [ "$3" != "create" ]; then
                        echo "ERROR: Unexpected az storage container command"
                        return 1
                    fi
                    echo "Mocking az storage container create..."
                    if [ "$5" != "mock-container" ] || [ "$7" != "mockstorageaccount" ]; then
                        echo "ERROR: az storage container create called with wrong container or account"
                        echo "Got container: $5, account: $7"
                        return 1
                    fi
                    ;;
                
                blob)
                    if [ "$3" != "upload" ]; then
                        echo "ERROR: Unexpected az storage blob command"
                        return 1
                    fi

                    COUNT_FILE="/var/workdir/upload_count.txt"
                    UPLOAD_LOG="/var/workdir/upload_paths.log"
                    if [ ! -f "$COUNT_FILE" ]; then
                        echo 0 > "$COUNT_FILE"
                    fi
                    COUNT=$(cat "$COUNT_FILE")

                    echo "Mock az storage blob upload called (count=$COUNT) with: $*"

                    # Log the upload path for verification
                    echo "$*" >> "$UPLOAD_LOG"

                    # For multiarch, expect different upload patterns
                    # Check if this looks like a multiarch upload by looking for arch paths
                    if [[ "$*" == *"/amd64/"* ]] || [[ "$*" == *"/arm64/"* ]]; then
                        # This is a multiarch upload - be more flexible with validation
                        if [[ "$*" == *"--name test-vendor/"* ]] && [[ "$*" == *"/test.ko"* ]]; then
                            echo "Valid multiarch .ko file upload detected"
                        elif [[ "$*" == *"--name test-vendor/"* ]] && [[ "$*" == *"envfile"* ]]; then
                            echo "Valid multiarch envfile upload detected"
                        else
                            echo "WARNING: Unexpected multiarch upload pattern, but allowing: $*"
                        fi
                    else
                        # Single arch mode - now expects arch suffix (x86_64)
                        if [ "$COUNT" -le 1 ]; then
                            # First two uploads should be .ko files (mod1.ko or mod2.ko, order doesn't matter)
                            if [[ "$*" == *"--name mocked-vendor-azure/1.2.3-az/6.5.0-az/x86_64/mod1.ko"* ]] || [[ "$*" == *"--name mocked-vendor-azure/1.2.3-az/6.5.0-az/x86_64/mod2.ko"* ]]; then
                                echo "Valid .ko file upload detected (upload #$COUNT)"
                            else
                                echo "ERROR: Upload #$COUNT should be mod1.ko or mod2.ko"
                                echo "Expected: --name mocked-vendor-azure/1.2.3-az/6.5.0-az/x86_64/mod[12].ko"
                                echo "Got: $*"
                                return 1
                            fi
                        elif [ "$COUNT" -eq 2 ]; then
                            # Checksum file with arch-specific name
                            if [[ ! "$*" == *"--name mocked-vendor-azure/1.2.3-az/6.5.0-az/x86_64/signed_kmods_checksums_x86_64.txt"* ]]; then
                                echo "ERROR: Third az blob upload call has wrong name param for checksum file"
                                echo "Expected: --name mocked-vendor-azure/1.2.3-az/6.5.0-az/x86_64/signed_kmods_checksums_x86_64.txt"
                                return 1
                            fi
                        elif [ "$COUNT" -gt 10 ]; then
                            echo "ERROR: az blob upload called too many times!"
                            return 1
                        fi
                    fi

                    COUNT=$((COUNT + 1))
                    echo $COUNT > "$COUNT_FILE"
                    ;;

                *)
                    echo "ERROR: Unknown az storage subcommand: $2"
                    return 1
                    ;;
            esac
            ;;

        *)
            echo "ERROR: Unknown az command: $1"
            echo "Full command was: $*"
            echo "This indicates the mock doesn't handle this Azure CLI command yet"
            return 1
            ;;
    esac

    return 0
}

check_upload_count() {
    COUNT_FILE="/var/workdir/upload_count.txt"
    if [ ! -f "$COUNT_FILE" ]; then
        echo "ERROR: Upload count file not found"
        return 1
    fi

    COUNT=$(cat "$COUNT_FILE")
    echo "Total upload count: $COUNT"

    # For multiarch, expect at least 4 uploads (2 .ko files + 2 envfiles minimum)
    # For single arch, expect exactly 4 uploads (2 .ko files + 1 checksum file + 1 envfile)
    if [ "$COUNT" -ge 5 ]; then
        echo "SUCCESS: az blob upload was called $COUNT times (multiarch scenario detected)"
    elif [ "$COUNT" -eq 4 ]; then
        echo "SUCCESS: az blob upload was called exactly 4 times (single arch scenario: 2 .ko files + checksum + envfile)"
    else
        echo "ERROR: az blob upload was called $COUNT times, expected 4 (single arch) or 5+ (multiarch)"
        return 1
    fi

    # Verify kernel version cleaning: the test uses KERNEL_VERSION="6.5.0-az.x86_64"
    # The task should strip the .x86_64 suffix, so upload paths should contain "6.5.0-az/" not "6.5.0-az.x86_64/"
    UPLOAD_LOG="/var/workdir/upload_paths.log"
    if [ -f "$UPLOAD_LOG" ]; then
        echo ""
        echo "Verifying KERNEL_VERSION architecture suffix was stripped..."
        # Use grep -F for literal/fixed string matching (dots are literal, not regex)
        if grep -F -q "6.5.0-az.x86_64" "$UPLOAD_LOG"; then
            echo "ERROR: Found dirty kernel version (6.5.0-az.x86_64) in upload paths!"
            echo "The .x86_64 suffix should have been stripped."
            echo "Upload log:"
            cat "$UPLOAD_LOG"
            return 1
        else
            echo "SUCCESS: Kernel version architecture suffix was properly stripped"
            echo "All uploads used cleaned path: 6.5.0-az (not 6.5.0-az.x86_64)"
        fi
    fi
}