#!/bin/bash
set -e

# Validation and help function
show_help() {
    cat << EOF
Usage: $0 <username>

Arguments:
  username    User name to delete (required)

Examples:
  $0 john
  $0 jane-doe

This will:
  - Delete the CertificateSigningRequest from Kubernetes
  - Remove the certificate and key files
  - Remove the user from kubeconfig
  - List RoleBindings and ClusterRoleBindings for manual cleanup

EOF
    exit 1
}

# Show help if no arguments
if [ -z "$1" ]; then
    show_help
fi

USERNAME=$1

# Validate username
if [[ ! "$USERNAME" =~ ^[a-z][a-z0-9-]{2,19}$ ]]; then
    echo "Error: Invalid username '$USERNAME'"
    echo "Username must:"
    echo "  - Start with a lowercase letter"
    echo "  - Only contain lowercase letters, numbers and hyphens"
    echo "  - Be between 3 and 20 characters long"
    echo ""
    show_help
fi

echo "🗑️  Deleting user '${USERNAME}'..."
echo ""

# Delete CSR from Kubernetes
echo "📝 Deleting CertificateSigningRequest..."
if kubectl get csr ${USERNAME} &> /dev/null; then
    kubectl delete csr ${USERNAME}
    echo "   ✅ CSR deleted"
else
    echo "   ⚠️  CSR not found"
fi

# Delete certificate and key files
echo "📁 Deleting local files..."
FILES_DELETED=0
for file in certs/${USERNAME}-key.pem certs/${USERNAME}-cert.pem certs/${USERNAME}.csr; do
    if [ -f "$file" ]; then
        rm "$file"
        echo "   ✅ Deleted $file"
        FILES_DELETED=$((FILES_DELETED + 1))
    fi
done

if [ $FILES_DELETED -eq 0 ]; then
    echo "   ⚠️  No local files found"
fi

# Remove user from kubeconfig
echo "⚙️  Removing from kubeconfig..."
if kubectl config get-users | grep -q "^${USERNAME}$"; then
    kubectl config delete-user ${USERNAME}
    echo "   ✅ User removed from kubeconfig"
else
    echo "   ⚠️  User not found in kubeconfig"
fi

# Remove context if exists
if kubectl config get-contexts -o name | grep -q "^${USERNAME}-context$"; then
    kubectl config delete-context ${USERNAME}-context
    echo "   ✅ Context '${USERNAME}-context' removed"
fi

# List RoleBindings and ClusterRoleBindings
echo ""
echo "🔍 Checking RBAC bindings for user '${USERNAME}'..."
echo ""

ROLEBINDINGS=$(kubectl get rolebindings --all-namespaces -o json | jq -r --arg user "$USERNAME" '.items[] | select(.subjects[]? | select(.kind=="User" and .name==$user)) | "\(.metadata.namespace)/\(.metadata.name)"')

if [ -n "$ROLEBINDINGS" ]; then
    echo "   RoleBindings found:"
    echo "$ROLEBINDINGS" | while read binding; do
        echo "   - $binding"
    done
    echo ""
    echo "   To delete: kubectl delete rolebinding <name> -n <namespace>"
else
    echo "   ℹ️  No RoleBindings found"
fi

CLUSTERROLEBINDINGS=$(kubectl get clusterrolebindings -o json | jq -r --arg user "$USERNAME" '.items[] | select(.subjects[]? | select(.kind=="User" and .name==$user)) | .metadata.name')

if [ -n "$CLUSTERROLEBINDINGS" ]; then
    echo ""
    echo "   ClusterRoleBindings found:"
    echo "$CLUSTERROLEBINDINGS" | while read binding; do
        echo "   - $binding"
    done
    echo ""
    echo "   To delete: kubectl delete clusterrolebinding <name>"
else
    echo "   ℹ️  No ClusterRoleBindings found"
fi

echo ""
echo "✅ User '${USERNAME}' deleted successfully!"