set -eux

aws() {
    echo "Mock 'aws' called with: $*"
    
    if [ "$1" != "s3" ] || [ "$2" != "cp" ]; then
        echo "ERROR: Mock aws called with wrong command ($1 $2)"
        exit 1
    fi
    
    if [ "$3" != "/var/workdir/release/signed-kmods" ]; then
        echo "ERROR: Wrong source path: $3"
        exit 1
    fi
    
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