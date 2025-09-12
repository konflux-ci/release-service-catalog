#!/bin/bash
# Local Tekton Task Testing Setup Script
# This script sets up a local Kind cluster with all dependencies needed to run Tekton task tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-release-service-catalog}"
# Get latest tkn CLI version from GitHub API (same as .github/actions/install-tkn/action.yaml)
TKN_CLI_VERSION="${TKN_CLI_VERSION:-$(curl -s https://api.github.com/repos/tektoncd/cli/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

show_help() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Manage local Tekton testing environment.

COMMANDS:
    setup      Set up Kind cluster with Tekton (default)
    teardown   Remove the testing environment
    reset      Teardown then setup (fresh environment)

OPTIONS:
    --help          Show this help message
    --force         Skip confirmation prompts (for teardown/reset)
    --cluster-only  Only remove cluster (for teardown)
    --all           Remove everything including env files (for teardown)

EXAMPLES:
    # Initial setup
    $0 setup
    
    # Remove everything
    $0 teardown --all
    
    # Fresh start
    $0 reset --force

EOF
}

cleanup_test_resources() {
    log "Cleaning up test resources..."
    
    if kubectl config current-context 2>/dev/null | grep -q "kind-"; then
        # Clean up PipelineRuns and TaskRuns
        kubectl delete pipelinerun --all --timeout=60s 2>/dev/null || warn "Failed to delete some PipelineRuns"
        kubectl delete taskrun --all --timeout=60s 2>/dev/null || warn "Failed to delete some TaskRuns"
        
        # Clean up any test-related pods
        kubectl delete pod --all --timeout=60s 2>/dev/null || warn "Failed to delete some pods"
        
        success "Test resources cleaned up"
    else
        warn "Not connected to a Kind cluster, skipping resource cleanup"
    fi
}

cleanup_cluster() {
    log "Removing Kind cluster: $CLUSTER_NAME"
    
    # Kill any port-forward processes
    local regpid
    regpid=$(ps -eawwf | grep "30001:443" | grep -v grep | awk '{print $2}' || true)
    if [ -n "$regpid" ]; then
        log "Killing registry port-forward (PID: $regpid)"
        kill -9 "$regpid" 2>/dev/null || true
    fi
    
    # Delete the cluster
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        kind delete cluster --name "$CLUSTER_NAME"
        success "Cluster $CLUSTER_NAME removed"
    else
        warn "Cluster $CLUSTER_NAME not found"
    fi
}

cleanup_environment() {
    log "Cleaning up environment files..."
    
    # Remove environment file
    if [ -f "${REPO_ROOT}/.env.testing" ]; then
        rm -f "${REPO_ROOT}/.env.testing"
        success "Removed .env.testing"
    fi
    
    # Clean up test results
    if [ -d "${REPO_ROOT}/test-results" ]; then
        rm -rf "${REPO_ROOT}/test-results"
        log "Removed test-results directory"
    fi
    
    # Clean up any temporary docker configs
    if [ -n "${DOCKER_CONFIG_JSON:-}" ] && [ -f "$DOCKER_CONFIG_JSON" ]; then
        rm -f "$DOCKER_CONFIG_JSON"
        log "Removed temporary docker config"
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check for required tools
    local missing_tools=()
    
    command -v podman >/dev/null 2>&1 || missing_tools+=("podman")
    command -v kind >/dev/null 2>&1 || missing_tools+=("kind")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v yq >/dev/null 2>&1 || missing_tools+=("yq")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    command -v curl >/dev/null 2>&1 || missing_tools+=("curl")
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and run this script again."
        echo "Installation guides:"
        echo "  - podman: https://podman.io/getting-started/installation"
        echo "  - kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation" 
        echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  - yq: https://github.com/mikefarah/yq#install"
        echo "  - jq: https://stedolan.github.io/jq/download/"
        echo "  - curl: https://curl.se/download.html"
        exit 1
    fi
    
    success "All prerequisites found"
}

install_tkn() {
    # Validate that we have a version number
    if [ -z "$TKN_CLI_VERSION" ]; then
        error "Could not determine tkn CLI version. Please check your internet connection or set TKN_CLI_VERSION manually."
        return 1
    fi
    
    if command -v tkn >/dev/null 2>&1; then
        local current_version
        current_version=$(tkn version --client-only 2>/dev/null | grep -o 'v[0-9.]*' | head -1 | cut -c2-)
        if [ "$current_version" = "$TKN_CLI_VERSION" ]; then
            success "tkn CLI v${TKN_CLI_VERSION} already installed"
            return 0
        else
            warn "tkn CLI v${current_version} found, but v${TKN_CLI_VERSION} is recommended"
        fi
    fi
    
    log "Installing tkn CLI v${TKN_CLI_VERSION}..."
    
    # Download and install tkn
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    case "$(uname -s)" in
        Linux)
            curl -LO "https://github.com/tektoncd/cli/releases/download/v${TKN_CLI_VERSION}/tektoncd-cli-${TKN_CLI_VERSION}_Linux-64bit.deb"
            sudo dpkg -i "./tektoncd-cli-${TKN_CLI_VERSION}_Linux-64bit.deb" || {
                # Try without sudo if it fails
                warn "dpkg with sudo failed, trying alternative installation..."
                curl -LO "https://github.com/tektoncd/cli/releases/download/v${TKN_CLI_VERSION}/tkn_${TKN_CLI_VERSION}_Linux_x86_64.tar.gz"
                tar -xzf "tkn_${TKN_CLI_VERSION}_Linux_x86_64.tar.gz"
                sudo mv tkn /usr/local/bin/ || {
                    warn "Could not install to /usr/local/bin, installing to ~/.local/bin"
                    mkdir -p ~/.local/bin
                    mv tkn ~/.local/bin/
                    export PATH="$HOME/.local/bin:$PATH"
                }
            }
            ;;
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                brew install tektoncd-cli
            else
                curl -LO "https://github.com/tektoncd/cli/releases/download/v${TKN_CLI_VERSION}/tkn_${TKN_CLI_VERSION}_Darwin_x86_64.tar.gz"
                tar -xzf "tkn_${TKN_CLI_VERSION}_Darwin_x86_64.tar.gz"
                sudo mv tkn /usr/local/bin/ || {
                    warn "Could not install to /usr/local/bin, installing to ~/.local/bin"
                    mkdir -p ~/.local/bin
                    mv tkn ~/.local/bin/
                    export PATH="$HOME/.local/bin:$PATH"
                }
            fi
            ;;
        *)
            error "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
    
    cd - >/dev/null
    rm -rf "$temp_dir"
    
    success "tkn CLI installed successfully"
}

create_kind_cluster() {
    log "Creating Kind cluster: $CLUSTER_NAME"
    
    # Check if cluster already exists
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        warn "Cluster $CLUSTER_NAME already exists"
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Deleting existing cluster..."
            kind delete cluster --name "$CLUSTER_NAME"
        else
            log "Using existing cluster"
            kubectl config use-context "kind-${CLUSTER_NAME}"
            return 0
        fi
    fi
    
    # Create kind cluster with registry support
    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry-service.kind-registry"]
    endpoint = ["https://registry-service.kind-registry"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."registry-service.kind-registry".tls]
    insecure_skip_verify = true
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP
EOF
    
    # Wait for cluster to be ready
    log "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    success "Kind cluster created successfully"
}

install_crds() {
    log "Installing required CRDs using CI scripts..."
    
    # Change to the scripts directory 
    local original_dir="$PWD"
    cd "${REPO_ROOT}/.github/scripts"
    
    # Run the CRD installation script
    if ! bash ./install_crds.sh; then
        error "Failed to install CRDs"
        cd "$original_dir"
        return 1
    fi
    
    cd "$original_dir"
    success "CRDs installed successfully"
}

deploy_registry() {
    log "Deploying cert-manager, trust-manager and registry..."
    
    # Deploy cert-manager
    log "Installing cert-manager..."
    if ! kubectl apply -k "${REPO_ROOT}/.github/resources/cert-manager"; then
        error "Failed to install cert-manager"
        return 1
    fi
    
    log "Waiting for cert-manager to be ready..."
    if ! kubectl wait --for=condition=Ready --timeout=120s -l app.kubernetes.io/instance=cert-manager -n cert-manager pod; then
        error "Cert-manager did not become ready"
        return 1
    fi
    
    # Deploy trust-manager
    log "Installing trust-manager..."
    if ! kubectl apply -k "${REPO_ROOT}/.github/resources/trust-manager"; then
        error "Failed to install trust-manager"
        return 1
    fi
    
    log "Waiting for trust-manager to be ready..."
    if ! kubectl wait --for=condition=Ready --timeout=60s -l app.kubernetes.io/instance=trust-manager -n cert-manager pod; then
        error "Trust-manager did not become ready"
        return 1
    fi
    
    # Deploy cluster issuer
    log "Installing cluster issuer..."
    if ! kubectl apply -k "${REPO_ROOT}/.github/resources/cluster-issuer"; then
        error "Failed to install cluster issuer"
        return 1
    fi
    
    # Deploy registry
    log "Installing registry..."
    if ! kubectl apply -k "${REPO_ROOT}/.github/resources/registry"; then
        error "Failed to install registry"
        return 1
    fi
    
    log "Waiting for registry to be ready..."
    if ! kubectl wait --for=condition=Ready --timeout=240s -n kind-registry -l run=registry pod; then
        error "Registry did not become ready"
        return 1
    fi
    
    # Setup port forwarding (in background)
    log "Setting up port forwarding for registry..."
    # Kill any existing port forward
    pkill -f "kubectl port-forward.*30001:443" 2>/dev/null || true
    kubectl port-forward -n kind-registry svc/registry-service 30001:443 >/dev/null 2>&1 &
    sleep 2  # Give port forwarding time to establish
    
    # Create docker config in a persistent location
    log "Creating docker config for registry access..."
    local auth_string
    auth_string=$(echo -n "root:root" | base64 -w0)
    local docker_config_dir="${REPO_ROOT}/.local"
    local docker_config_file="${docker_config_dir}/dockerconfig.json"
    
    mkdir -p "${docker_config_dir}"
    cat > "${docker_config_file}" <<EOF
{
  "auths": {
    "registry-service.kind-registry": {
      "auth": "${auth_string}"
    }
  }
}
EOF
    
    export DOCKER_CONFIG_JSON="${docker_config_file}"
    
    success "Registry environment deployed successfully"
}

install_tekton() {
    log "Installing Tekton Pipelines using CI logic..."
    
    # Use exact same logic as CI workflow
    if ! kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml; then
        error "Failed to install Tekton Pipelines"
        return 1
    fi

    echo -n "Waiting for Tekton pods to appear.."
    while [ "$(kubectl get pods --namespace tekton-pipelines -o name | wc -l)" -lt 2 ]; do
        sleep 1
        echo -n .
    done
    echo " done"

    echo "Waiting for Tekton pods to be ready"
    for POD in $(kubectl get pods --namespace tekton-pipelines -o name); do
        if ! kubectl wait --timeout=120s --for=condition=Ready "$POD" --namespace tekton-pipelines; then
            error "Pod $POD did not become ready"
            return 1
        fi
    done

    kubectl get pods --namespace tekton-pipelines

    # let tekton controllers startup...
    sleep 10

    # enable stepActions
    log "Updating feature-flags"
    if ! kubectl get cm feature-flags -n tekton-pipelines -o yaml | \
        sed -e 's|enable-step-actions: "false"|enable-step-actions: "true"|' > /tmp/ff.yaml; then
        error "Failed to get feature-flags configmap"
        return 1
    fi
    
    if ! kubectl apply -f /tmp/ff.yaml -n tekton-pipelines; then
        error "Failed to enable StepActions feature"
        return 1
    fi
    rm -f /tmp/ff.yaml
    
    success "Tekton Pipelines installed successfully"
}

setup_test_environment() {
    log "Setting up test environment variables..."
    
    # Create environment file with complete, automated CI-like setup  
    cat > "${REPO_ROOT}/.env.testing" <<EOF
#!/bin/bash
# Local Tekton Task Testing Environment - TRUSTED ARTIFACTS READY
# This file provides complete CI-like environment for unit tests
# 
# Usage:
#   source .env.testing
#   ./scripts/run-local-tests.sh tasks/managed/check-fbc-packages
#
# Environment includes:
# - Local Kind cluster with cert-manager, trust-manager, and registry
# - Trusted Artifacts workflow (automatically configured)
# - All required CRDs (application-api, internal-services, release-service)
# - Tekton Pipelines with StepActions enabled
# - Persistent docker config and port forwarding

export KUBECONFIG="\$(pwd)/test-kubeconfig"
export CLUSTER_NAME="${CLUSTER_NAME}"

# Trusted Artifacts configuration (WORKING)
export DOCKER_CONFIG_JSON="\$(pwd)/.local/dockerconfig.json"
export TRUSTED_ARTIFACT_OCI_STORAGE="registry-service.kind-registry/trusted-artifacts"
export TRUSTED_ARTIFACT_OCI_DOCKER_CONFIG_JSON_PATH="\$(pwd)/.local/dockerconfig.json"
export USE_TRUSTED_ARTIFACTS=true

# Ensure kubectl context is correct
kubectl config use-context kind-${CLUSTER_NAME} >/dev/null 2>&1

# Ensure port forwarding is active
if ! pgrep -f "kubectl port-forward.*kind-registry.*30001:443" >/dev/null 2>&1; then
    echo "🔧 Restarting registry port forwarding..."
    pkill -f "kubectl port-forward.*30001:443" 2>/dev/null || true
    kubectl port-forward -n kind-registry svc/registry-service 30001:443 >/dev/null 2>&1 &
    sleep 2
fi

echo "=== Testing Environment Ready (TRUSTED ARTIFACTS) ==="
echo "✅ Cluster: \$(kubectl config current-context)"
echo "✅ Tekton: \$(kubectl get deployment tekton-pipelines-controller -n tekton-pipelines -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null || echo 'unknown')"
echo "✅ Registry: registry-service.kind-registry (with certificates and port forwarding)"
echo "✅ Docker config: \$DOCKER_CONFIG_JSON"
echo ""
echo "🚀 READY TO RUN TESTS:"
echo "  # Test packages (VERIFIED WORKING):"
echo "  ./scripts/run-local-tests.sh --remove-compute-resources tasks/managed/check-fbc-packages"
echo ""
echo "  # Test tasks:"
echo "  ./scripts/run-local-tests.sh --remove-compute-resources tasks/managed/add-fbc-contribution"
echo ""
echo "  # Test specific test file:"
echo "  ./scripts/run-local-tests.sh --remove-compute-resources tasks/managed/check-fbc-packages/tests/test-check-fbc-packages-positive.yaml"
echo ""
echo "  # Test multiple tasks (use with caution - some may be slow):"
echo "  ./scripts/run-local-tests.sh --remove-compute-resources \\\\"
echo "    tasks/managed/add-fbc-contribution \\\\"
echo "    tasks/managed/check-fbc-packages"
echo ""
echo "🧹 CLEANUP:"
echo "  # Clean test resources (keeps cluster):"
echo "  kubectl delete pipelinerun --all && kubectl delete taskrun --all"
echo ""
echo "  # Full cleanup:"
echo "  kind delete cluster --name ${CLUSTER_NAME}"
EOF
    
    success "Test environment configured with automated Trusted Artifacts setup"
    success "Ready to use: source .env.testing"
}

setup_environment() {
    log "Setting up local Tekton task testing environment..."
    
    # Run each setup step with explicit error checking
    check_prerequisites || { error "Prerequisites check failed"; exit 1; }
    install_tkn || { error "tkn installation failed"; exit 1; }
    create_kind_cluster || { error "Kind cluster creation failed"; exit 1; }
    install_crds || { error "CRD installation failed"; exit 1; }
    deploy_registry || { error "Registry deployment failed"; exit 1; }
    install_tekton || { error "Tekton installation failed"; exit 1; }
    setup_test_environment || { error "Test environment setup failed"; exit 1; }
    
    success "Local testing environment setup complete!"
    echo
    echo "Next steps:"
    echo "1. Source the environment: source .env.testing"
    echo "2. Run tests: ./scripts/run-local-tests.sh tasks/managed/add-fbc-contribution"
    echo "3. Or run specific test: ./scripts/run-local-tests.sh tasks/managed/add-fbc-contribution/tests/test-add-fbc-contribution.yaml"
    echo
    echo "To clean up: $0 teardown --all"
}

teardown_environment() {
    local cleanup_all=false
    local cluster_only=false
    local force=false
    
    # Parse teardown options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                cleanup_all=true
                shift
                ;;
            --cluster-only)
                cluster_only=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Determine what to clean up
    if [ "$cleanup_all" = "true" ]; then
        if [ "$force" != "true" ]; then
            echo "This will remove:"
            echo "  - Kind cluster: $CLUSTER_NAME"
            echo "  - Environment files"
            echo "  - All test resources and results"
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Cancelled"
                exit 0
            fi
        fi
        
        cleanup_test_resources
        cleanup_cluster
        cleanup_environment
        
    elif [ "$cluster_only" = "true" ]; then
        if [ "$force" != "true" ]; then
            read -p "Remove Kind cluster '$CLUSTER_NAME'? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Cancelled"
                exit 0
            fi
        fi
        
        cleanup_cluster
        
    else
        # Default: clean up resources and cluster, keep env files
        if [ "$force" != "true" ]; then
            read -p "Remove Kind cluster and test resources? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Cancelled"
                exit 0
            fi
        fi
        
        cleanup_test_resources
        cleanup_cluster
    fi
    
    success "Teardown completed!"
}

main() {
    local command="${1:-setup}"
    
    case "$command" in
        setup)
            shift
            setup_environment "$@"
            ;;
        teardown)
            shift
            teardown_environment "$@"
            ;;
        reset)
            shift
            local force_reset=false
            for arg in "$@"; do
                if [ "$arg" = "--force" ]; then
                    force_reset=true
                    break
                fi
            done
            
            if [ "$force_reset" = "true" ]; then
                teardown_environment --all --force
                setup_environment
            else
                teardown_environment --all
                setup_environment
            fi
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Handle script being sourced vs executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi