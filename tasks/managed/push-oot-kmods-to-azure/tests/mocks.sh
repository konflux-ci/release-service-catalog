set -eux

az() {
    echo "Mock 'az' called with: $*"

    case "$1" in
        login)
            echo "Mocking az login..."
            if [ "$2" != "--service-principal" ] || [ "$4" != "mock-client-id" ]; then
               echo "ERROR: az login called with wrong client-id ('$4') or not as service-principal ('$2')"
               exit 1
            fi
            ;;

        storage)
            case "$2" in
                container)
                    if [ "$3" != "create" ]; then
                        echo "ERROR: Unexpected az storage container command"
                        exit 1
                    fi
                    echo "Mocking az storage container create..."
                    if [ "$5" != "mockcontainer" ] || [ "$7" != "mockstorageaccount" ]; then
                        echo "ERROR: az storage container create called with wrong container or account"
                        exit 1
                    fi
                    ;;
                
                blob)
                    if [ "$3" != "upload" ]; then
                        echo "ERROR: Unexpected az storage blob command"
                        exit 1
                    fi
                    
                    COUNT_FILE="/var/workdir/upload_count.txt"
                    if [ ! -f "$COUNT_FILE" ]; then
                        echo 0 > "$COUNT_FILE"
                    fi
                    COUNT=$(cat "$COUNT_FILE")
                    
                    if [ "$COUNT" -eq 0 ]; then
                        if [[ ! "$*" == *"--name mocked-vendor-azure/1.2.3-az/6.5.0-az/mod1.ko"* ]]; then
                            echo "ERROR: First az blob upload call has wrong name param for mod1.ko"
                            exit 1
                        fi
                    elif [ "$COUNT" -eq 1 ]; then
                         if [[ ! "$*" == *"--name mocked-vendor-azure/1.2.3-az/6.5.0-az/mod2.ko"* ]]; then
                            echo "ERROR: Second az blob upload call has wrong name param for mod2.ko"
                            exit 1
                        fi
                    else
                        echo "ERROR: az blob upload called more than twice!"
                        exit 1
                    fi
                    
                    COUNT=$((COUNT + 1))
                    echo $COUNT > "$COUNT_FILE"
                    ;;

                *)
                    echo "ERROR: Unknown az storage subcommand: $2"
                    exit 1
                    ;;
            esac
            ;;

        *)
            echo "ERROR: Unknown az command: $1"
            exit 1
            ;;
    esac
}

check_upload_count() {
    COUNT_FILE="/var/workdir/upload_count.txt"
    if [ ! -f "$COUNT_FILE" ] || [ "$(cat $COUNT_FILE)" != "2" ]; then
        echo "ERROR: az blob upload was not called exactly 2 times."
        cat "$COUNT_FILE" 2>/dev/null || echo "Count file not found"
        exit 1
    fi
    echo "SUCCESS: az blob upload was called exactly 2 times."
}