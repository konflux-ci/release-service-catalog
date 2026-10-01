#!/usr/bin/env sh
set -eux
echo "--- MOCK ORAS CALLED ---" >&2
echo "Arguments: $*" >&2
COMMAND="$1"
if [ "$COMMAND" = "pull" ]; then
    echo "Mock 'oras pull' called. Pretending to succeed."
    exit 0
elif [ "$COMMAND" = "push" ]; then
    echo "Mock 'oras push' called. Validating arguments..."
    EXPECTED_TARGET="mock.registry/test-repo/my-artifact"
    EXPECTED_SOURCE_NAME="sourceDataArtifact"
    shift # remove "push"
    POSITIONAL_ARGS=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --registry-config|--ca-file|--annotation)
                shift 2
                ;;
            --*=*)
                shift
                ;;
            --*)
                shift
                ;;
            *)
                POSITIONAL_ARGS="$POSITIONAL_ARGS $1"
                shift
                ;;
        esac
    done
    ACTUAL_TARGET=$(echo $POSITIONAL_ARGS | awk '{print $1}')
    ACTUAL_SOURCE=$(echo $POSITIONAL_ARGS | awk '{print $2}')
    if [ "$ACTUAL_TARGET" != "$EXPECTED_TARGET" ]; then
        echo "ERROR: Mock oras expected target '$EXPECTED_TARGET' but got '$ACTUAL_TARGET'"
        exit 1
    fi
    if [ "$ACTUAL_SOURCE" != "$EXPECTED_SOURCE_NAME" ]; then
        echo "ERROR: Mock oras expected source '$EXPECTED_SOURCE_NAME' but got '$ACTUAL_SOURCE'"
        exit 1
    fi
    echo "SUCCESS: Mock oras push validated."
    exit 0
elif [ "$COMMAND" = "blob" ]; then
    SUBCOMMAND="$2"
    echo "Mock 'oras blob $SUBCOMMAND' called." >&2
    if [ "$SUBCOMMAND" = "fetch" ]; then
        # Create a mock tar.gz stream for blob fetch
        # This simulates fetching an artifact and outputting it as a compressed tarball
        echo "Mock fetching blob..." >&2
        # Create a temporary directory with mock content
        TEMP_DIR=$(mktemp -d)
        echo "mock extracted content from trusted artifact" > "$TEMP_DIR/artifact-file.txt"
        echo "mock metadata" > "$TEMP_DIR/metadata.json"
        # Create a gzipped tar and output to stdout (this is what the caller expects)
        tar -C "$TEMP_DIR" -czf - .
        # Clean up
        rm -rf "$TEMP_DIR"
        echo "Mock blob fetch completed." >&2
        exit 0
    else
        echo "ERROR: Mock oras blob doesn't support subcommand: '$SUBCOMMAND'"
        exit 1
    fi
else
    echo "ERROR: Mock oras script doesn't know how to handle command: '$COMMAND'"
    exit 1
fi