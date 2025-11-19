set -eux

# Check if this is a multiarch test by looking for arch_count.txt
aws() {
    echo "Mock 'aws' called with: $*"

    if [ "$1" != "s3" ] || [ "$2" != "cp" ]; then
        echo "ERROR: Mock aws called with wrong command ($1 $2)"
        exit 1
    fi

    # Check if this is a multi-architecture test
    if [ -f "/var/workdir/release/arch_count.txt" ]; then
        arch_count=$(cat "/var/workdir/release/arch_count.txt")
        if [ "$arch_count" -gt 1 ]; then
            echo "Multi-architecture S3 upload detected"

            # For multi-arch, accept architecture-specific paths
            case "$*" in
                *"/amd64/"*|*"/arm64/"*|*"multi-arch-summary"*)
                    echo "SUCCESS: Multi-arch S3 path accepted: $*"
                    echo "1" > /var/workdir/aws_call_validated.txt
                    return 0
                    ;;
            esac

            # Also accept architecture-specific source paths
            if [[ "$3" == *"/amd64" ]] || [[ "$3" == *"/arm64" ]] || [[ "$3" == *"/signed-kmods" ]]; then
                echo "SUCCESS: Multi-arch source path accepted: $*"
                echo "1" > /var/workdir/aws_call_validated.txt
                return 0
            fi
        fi
    fi

    # Single-arch validation - handle both directory and individual file uploads
    case "$3" in
        "/var/workdir/release/signed-kmods")
            # Directory upload with recursive flags
            EXPECTED_TARGET="s3://mock-bucket/mocked-vendor-s3/1.2.3-s3/6.5.0-s3/"
            if [ "$4" != "$EXPECTED_TARGET" ]; then
                echo "ERROR: Wrong target S3 path: $4"
                echo "Expected: $EXPECTED_TARGET"
                exit 1
            fi

            if [ "$5" != "--endpoint-url" ] || [ "$6" != "https://s3.mock.endpoint.com" ]; then
                echo "ERROR: Wrong endpoint-url: $5 $6"
                exit 1
            fi

            if [ "$7" != "--recursive" ] || [ "$8" != "--exclude" ] || [ "$9" != "*" ] || [ "${10}" != "--include" ] || [ "${11}" != "*.ko" ]; then
                 echo "ERROR: Wrong flags (recursive, exclude, include): $*"
                 exit 1
            fi
            ;;
        "/var/workdir/release/signed-kmods/envfile")
            # Individual envfile upload
            EXPECTED_TARGET="s3://mock-bucket/mocked-vendor-s3/1.2.3-s3/6.5.0-s3/envfile"
            if [ "$4" != "$EXPECTED_TARGET" ]; then
                echo "ERROR: Wrong target S3 path for envfile: $4"
                echo "Expected: $EXPECTED_TARGET"
                exit 1
            fi

            if [ "$5" != "--endpoint-url" ] || [ "$6" != "https://s3.mock.endpoint.com" ]; then
                echo "ERROR: Wrong endpoint-url for envfile: $5 $6"
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Unexpected source path: $3"
            exit 1
            ;;
    esac

    echo "SUCCESS: aws s3 cp command validated."
    echo "1" > /var/workdir/aws_call_validated.txt
}

check_final_status() {
    if [ ! -f "/var/workdir/aws_call_validated.txt" ] || [ "$(cat /var/workdir/aws_call_validated.txt)" != "1" ]; then
        echo "ERROR: Final check failed. aws() mock validation did not run or failed."
        exit 1
    fi
    echo "SUCCESS: Final check passed. AWS mock was validated."
}