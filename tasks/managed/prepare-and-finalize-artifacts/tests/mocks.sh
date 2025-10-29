#!/usr/bin/env sh
set -eux

echo "--- MOCK ORAS CALLED ---"
echo "Arguments: $*"

COMMAND="$1"

if [ "$COMMAND" = "pull" ]; then
    echo "Mock 'oras pull' called. Pretending to succeed."
    exit 0

elif [ "$COMMAND" = "push" ]; then
    echo "Mock 'oras push' called. Validating arguments..."
    
    EXPECTED_TARGET="mock.registry/test-repo/my-artifact"
    
    if [ "$6" != "$EXPECTED_TARGET" ]; then
        echo "ERROR: Mock oras expected target '$EXPECTED_TARGET' (at \$6) but got '$6'"
        exit 1
    fi

    EXPECTED_SOURCE_NAME="sourceDataArtifact"
    if [ "$7" != "$EXPECTED_SOURCE_NAME" ]; then
        echo "ERROR: Mock oras expected source '$EXPECTED_SOURCE_NAME' (at \$7) but got '$7'"
        exit 1
    fi

    echo "SUCCESS: Mock oras push validated."
    exit 0

else
    echo "ERROR: Mock oras script doesn't know how to handle command: '$COMMAND'"
    exit 1
fi