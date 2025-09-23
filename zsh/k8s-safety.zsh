# Kubernets and helm safety script
# Add this script to your .zshrc

# Cores para output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

KUBECTL_DANGEROUS_COMMANDS=(
    "delete"
    "drain"
    "patch"
)

HELM_DANGEROUS_COMMANDS=(
    "delete"
    "uninstall"
)

confirm_command() {
    local command="$1"
    local context="$2"

    echo -e "${RED}⚠️  Destructive command: ${BLUE}$command${NC}"
    echo -e "${YELLOW}Contexto: ${GREEN}$context${NC}"
    echo -e "${RED}Type 'yes' to confirm:${NC}"
    read -r response

    if [[ "$response" == "yes" ]]; then
        #echo -e "${GREEN}✅ Execute...${NC}"
        return 0
    else
        echo -e "${RED}❌ Cancelled${NC}"
        # Remove the last command from history
        history -d -1
        return 1
    fi
}

kubectl() {
    command kubectl "$@"
    return

    local cmd="$1"
    local full_command="kubectl $*"
    local current_context=$(command kubectl config current-context 2>/dev/null || echo "unknown")

    for dangerous_cmd in "${KUBECTL_DANGEROUS_COMMANDS[@]}"; do
        if [[ "$cmd" == "$dangerous_cmd" ]]; then
            if ! confirm_command "$full_command" "$current_context"; then
                return 1
            fi
            break
        fi
    done

    # Executar o comando original
    command kubectl "$@"
}

helm() {
    local cmd="$1"
    local full_command="helm $*"
    local current_context=$(command kubectl config current-context 2>/dev/null || echo "unknown")

    for dangerous_cmd in "${HELM_DANGEROUS_COMMANDS[@]}"; do
        if [[ "$cmd" == "$dangerous_cmd" ]]; then
            if ! confirm_command "$full_command" "$current_context"; then
                return 1
            fi
            break
        fi
    done

    command helm "$@"
}

kubectl-unsafe() {
    echo -e "${RED}🚨 Execute KUBECTL WITHOUT PROTECTION!${NC}"
    command kubectl "$@"
}

helm-unsafe() {
    echo -e "${RED}🚨 Execute HELM WITHOUT PROTECTION!${NC}"
    command helm "$@"
}

k8s-context() {
    local context=$(command kubectl config current-context 2>/dev/null || echo "Nenhum contexto configurado")
    local namespace=$(command kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo 'default')

    echo -e "${BLUE}📋 Kubernetes context:${NC}"
    echo -e "${YELLOW}  Context: ${GREEN}$context${NC}"
    echo -e "${YELLOW}  Namespace: ${GREEN}$namespace${NC}"
}

k8s-contexts() {
    echo -e "${BLUE}📋 Available Kubernetes contexts:${NC}"
    command kubectl config get-contexts
}

k8s-help() {
    echo -e "${BLUE}🛡️  Protection against destructive K8s/Helm commands${NC}"
    echo ""
    echo -e "${YELLOW}Protected destructive commands:${NC}"
    echo -e "  ${GREEN}kubectl:${NC} delete, drain"
    echo -e "  ${GREEN}helm:${NC} delete, uninstall"
    echo ""
    echo -e "${YELLOW}Bypass commands (use with caution):${NC}"
    echo -e "  ${RED}kubectl-unsafe${NC} - Executes kubectl without protection"
    echo -e "  ${RED}helm-unsafe${NC} - Executes helm without protection"
    echo ""
    echo -e "${YELLOW}Utility commands:${NC}"
    echo -e "  ${GREEN}k8s-context${NC} - Displays current context and namespace"
    echo -e "  ${GREEN}k8s-contexts${NC} - Lists all contexts"
    echo -e "  ${GREEN}k8s-help${NC} - Displays this help"
}
