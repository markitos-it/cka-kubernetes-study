#!/bin/bash
set -e

show_help() {
    cat << EOF
Usage: $0 <username> [groups]

Arguments:
  username    User name (required): must start with a letter, only lowercase letters,
              numbers and hyphens allowed. Length: 3-20 characters.
  groups      Comma-separated list of groups (optional, default: system:authenticated)
              Example: developers,admins,viewers

Examples:
  $0 john
  $0 jane-doe developers
  $0 user123 developers,admins,viewers

EOF
    exit 1
}

echo "# Show help if no arguments"
if [ -z "$1" ]; then
    show_help
fi

USERNAME=$1

echo "# Validate username"
if [[ ! "$USERNAME" =~ ^[a-z][a-z0-9-]{2,19}$ ]]; then
    echo "Error: Invalid username '$USERNAME'"
    echo "Username must:"
    echo "  - Start with a lowercase letter"
    echo "  - Only contain lowercase letters, numbers and hyphens"
    echo "  - Be between 3 and 20 characters long"
    echo ""
    show_help
fi

echo "# Set default group if not provided"
if [ -z "$2" ]; then
    USER_GROUPS="system:authenticated"
else
    USER_GROUPS="$2"
fi

echo "# Convert comma-separated groups to /O=group1/O=group2/O=group3 format"
GROUPS_FORMATTED=""
IFS=',' read -ra GROUP_ARRAY <<< "$USER_GROUPS"
for group in "${GROUP_ARRAY[@]}"; do
    GROUPS_FORMATTED="${GROUPS_FORMATTED}/O=${group}"
done

echo "# Create certs directory if it doesn't exist"
mkdir -p certs

echo "# Generate private key and CSR"
echo "🔑 Generating private key..."
openssl genrsa -out certs/${USERNAME}-key.pem 2048

echo "📝 Creating certificate signing request..."
openssl req -new -key certs/${USERNAME}-key.pem -out certs/${USERNAME}.csr -subj "/CN=${USERNAME}${GROUPS_FORMATTED}"

echo "# Create CertificateSigningRequest in Kubernetes"
echo "☸️  Submitting CSR to Kubernetes..."
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USERNAME}
spec:
  request: $(cat certs/${USERNAME}.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 31536000
  usages:
  - client auth
EOF

echo "# Approve the CSR"
echo "✅ Approving certificate..."
kubectl certificate approve ${USERNAME}

echo "⏳ Waiting for certificate to be issued..."
sleep 2

echo "# Get the certificate"
kubectl get csr ${USERNAME} -o jsonpath='{.status.certificate}' | base64 -d > certs/${USERNAME}-cert.pem

echo "# Collect cluster-side info"
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
CURRENT_CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${CURRENT_CONTEXT}')].context.cluster}" 2>/dev/null || true)
CSR_SIGNER=$(kubectl get csr ${USERNAME} -o jsonpath='{.spec.signerName}')
CSR_EXP=$(kubectl get csr ${USERNAME} -o jsonpath='{.spec.expirationSeconds}')
CSR_APPROVED_AT=$(kubectl get csr ${USERNAME} -o jsonpath='{.status.conditions[?(@.type=="Approved")].lastUpdateTime}')
CERT_SUBJECT=$(openssl x509 -in certs/${USERNAME}-cert.pem -noout -subject | sed 's/^subject= //')
CERT_ISSUER=$(openssl x509 -in certs/${USERNAME}-cert.pem -noout -issuer | sed 's/^issuer= //')
CERT_DATES=$(openssl x509 -in certs/${USERNAME}-cert.pem -noout -dates | tr '\n' ' ')
CERT_SERIAL=$(openssl x509 -in certs/${USERNAME}-cert.pem -noout -serial)

ROLEBINDINGS=""
CLUSTERROLEBINDINGS=""
if command -v jq >/dev/null 2>&1; then
  ROLEBINDINGS=$(kubectl get rolebindings --all-namespaces -o json | jq -r --arg user "$USERNAME" '.items[] | select(.subjects[]? | select(.kind=="User" and .name==$user)) | "\(.metadata.namespace)/\(.metadata.name)"')
  CLUSTERROLEBINDINGS=$(kubectl get clusterrolebindings -o json | jq -r --arg user "$USERNAME" '.items[] | select(.subjects[]? | select(.kind=="User" and .name==$user)) | .metadata.name')
fi

echo ""
echo "✅ User '${USERNAME}' created successfully!"
echo "   Private key: certs/${USERNAME}-key.pem"
echo "   Certificate: certs/${USERNAME}-cert.pem"
echo "   Groups: ${USER_GROUPS}"
echo ""
echo "📜 Cluster view for '${USERNAME}':"
echo "   Context: ${CURRENT_CONTEXT}"
echo "   Cluster: ${CURRENT_CLUSTER}"
echo "   CSR signer: ${CSR_SIGNER}"
echo "   CSR expirationSeconds: ${CSR_EXP}"
echo "   CSR approved at: ${CSR_APPROVED_AT}"
echo "   Cert serial: ${CERT_SERIAL}"
echo "   Cert subject: ${CERT_SUBJECT}"
echo "   Cert issuer: ${CERT_ISSUER}"
echo "   Cert dates: ${CERT_DATES}"
if [ -n "$ROLEBINDINGS" ]; then
  echo "   RoleBindings:"
  echo "$ROLEBINDINGS" | sed 's/^/     - /'
else
  echo "   RoleBindings: (none)"
fi
if [ -n "$CLUSTERROLEBINDINGS" ]; then
  echo "   ClusterRoleBindings:"
  echo "$CLUSTERROLEBINDINGS" | sed 's/^/     - /'
else
  echo "   ClusterRoleBindings: (none)"
fi
echo ""
echo "Next steps:"
echo "  1. Configure kubeconfig:"
echo "     kubectl config set-credentials ${USERNAME} --client-certificate=certs/${USERNAME}-cert.pem --client-key=certs/${USERNAME}-key.pem"
echo "     kubectl config set-context ${USERNAME}-context --cluster=${CURRENT_CLUSTER:-<cluster-name>} --user=${USERNAME}"
echo "  2. Create RBAC bindings for the user/groups"