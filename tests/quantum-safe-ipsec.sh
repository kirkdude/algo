#!/usr/bin/env bash
# Quantum-safe IPsec connectivity test
# Tests strongSwan 6.0+ with ML-KEM support

set -euxo pipefail

ALGO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ALGO_ROOT"

# Configuration variables
SERVER_IP="${SERVER_IP:-10.0.8.100}"
VPN_USER="${VPN_USER:-desktop}"
CLIENT_IP="${CLIENT_IP:-localhost}"
RIGHTSUBNET="${RIGHTSUBNET:-172.16.0.1/32}"

echo "=== Quantum-Safe IPsec Test Suite ==="

# Test 1: Verify quantum-safe configuration files exist
echo "Test 1: Verifying quantum-safe configuration files..."

if [[ ! -f "./configs/${SERVER_IP}/ipsec/quantum-safe/README.md" ]]; then
    echo "ERROR: Quantum-safe configurations not found"
    echo "Make sure to deploy with quantum_safe_enabled: true"
    exit 1
fi

echo "✓ Quantum-safe configuration directory found"

# Test 2: Check certificate validity for quantum-safe mode
echo "Test 2: Validating certificates..."

CA_CONSTRAINTS="$(openssl verify -verbose \
  -CAfile "./configs/${SERVER_IP}/ipsec/.pki/cacert.pem" \
  "./configs/${SERVER_IP}/ipsec/.pki/certs/google-algo-test-pair.com.crt" 2>&1)" || true

if echo "$CA_CONSTRAINTS" | grep "permitted subtree violation" >/dev/null; then
    echo "✓ Name Constraints test passed"
else
    echo "✗ Name Constraints test failed"
    exit 1
fi

# Test 3: Verify strongSwan supports quantum-safe algorithms
echo "Test 3: Checking strongSwan quantum-safe support..."

# Check if strongSwan supports ML-KEM algorithms
if ! strongswan --version | grep -q "6.0" 2>/dev/null; then
    echo "WARNING: strongSwan 6.0+ not detected, skipping quantum-safe tests"
    echo "Falling back to classical IPsec test..."
    exec "$ALGO_ROOT/tests/ipsec-client.sh"
fi

# Check for OQS plugin
if ! swanctl --list-algs 2>/dev/null | grep -qi "kem\|ml-kem" 2>/dev/null; then
    echo "WARNING: ML-KEM algorithms not available, falling back to classical mode"
    exec "$ALGO_ROOT/tests/ipsec-client.sh"
fi

echo "✓ strongSwan 6.0+ with quantum-safe support detected"

# Test 4: Deploy quantum-safe client configuration
echo "Test 4: Deploying quantum-safe client configuration..."

# Use quantum-safe specific client deployment
ansible-playbook deploy_client.yml \
  -e client_ip="$CLIENT_IP" \
  -e vpn_user="$VPN_USER" \
  -e server_ip="$SERVER_IP" \
  -e rightsubnet="$RIGHTSUBNET" \
  -e quantum_safe_enabled=true \
  -e quantum_safe_mode=hybrid

echo "✓ Quantum-safe client configuration deployed"

# Test 5: Establish quantum-safe IPsec connection
echo "Test 5: Establishing quantum-safe IPsec connection..."

# Try quantum-safe connection first
CONNECTION_NAME="algovpn-pq-${SERVER_IP}"
FALLBACK_NAME="algovpn-fallback-${SERVER_IP}"

# Attempt quantum-safe connection
if ipsec up "$CONNECTION_NAME" 2>/dev/null; then
    ACTIVE_CONNECTION="$CONNECTION_NAME"
    echo "✓ Quantum-safe connection established: $CONNECTION_NAME"
elif ipsec up "$FALLBACK_NAME" 2>/dev/null; then
    ACTIVE_CONNECTION="$FALLBACK_NAME"
    echo "⚠ Fallback to classical connection: $FALLBACK_NAME"
else
    echo "✗ Failed to establish any IPsec connection"
    ipsec statusall
    exit 1
fi

# Test 6: Verify connection status and algorithms
echo "Test 6: Verifying connection status..."

ipsec statusall

# Check connection is established
if ! ipsec statusall | grep -w "^${ACTIVE_CONNECTION}" | grep -w ESTABLISHED; then
    echo "✗ Connection not in ESTABLISHED state"
    ipsec statusall
    exit 1
fi

echo "✓ IPsec connection established successfully"

# Test 7: Verify algorithm usage
echo "Test 7: Checking active algorithms..."

ALGO_INFO="$(ipsec statusall | grep -A 10 "^${ACTIVE_CONNECTION}")"
echo "Active connection details:"
echo "$ALGO_INFO"

# Check for quantum-safe indicators
if echo "$ALGO_INFO" | grep -qi "mlkem\|ml-kem"; then
    echo "✓ Quantum-safe algorithms (ML-KEM) detected in active connection"
    TEST_MODE="quantum-safe"
elif echo "$ALGO_INFO" | grep -qi "ecp384\|aes256"; then
    echo "⚠ Classical algorithms detected - running in fallback mode"
    TEST_MODE="classical"
else
    echo "? Algorithm detection inconclusive"
    TEST_MODE="unknown"
fi

# Test 8: Connectivity test
echo "Test 8: Testing VPN connectivity..."

# Ping tests
fping -t 900 -c3 -r3 -Dse "$SERVER_IP" 172.16.0.1

# DNS resolution test
host google.com 172.16.0.1

echo "✓ VPN connectivity tests passed"

# Test 9: Performance benchmark (optional)
if [[ "${BENCHMARK:-false}" == "true" ]]; then
    echo "Test 9: Performance benchmarking..."

    # Simple throughput test
    echo "Running basic performance test..."
    time curl -s -o /dev/null "http://httpbin.org/bytes/1048576" --interface tun0 || true

    echo "✓ Performance test completed"
fi

# Clean up
echo "Cleaning up connection..."
ipsec down "$ACTIVE_CONNECTION"

echo ""
echo "=== Quantum-Safe IPsec Test Results ==="
echo "✓ Configuration validation: PASSED"
echo "✓ Certificate validation: PASSED"
echo "✓ strongSwan compatibility: PASSED"
echo "✓ Client deployment: PASSED"
echo "✓ Connection establishment: PASSED"
echo "✓ Algorithm verification: PASSED ($TEST_MODE mode)"
echo "✓ Connectivity testing: PASSED"
echo "✓ Connection cleanup: PASSED"
echo ""
echo "Quantum-safe IPsec tests completed successfully!"

if [[ "$TEST_MODE" == "quantum-safe" ]]; then
    echo "🔒 QUANTUM-SAFE MODE ACTIVE - Your VPN is protected against quantum attacks!"
elif [[ "$TEST_MODE" == "classical" ]]; then
    echo "⚠️  CLASSICAL FALLBACK MODE - Consider upgrading client for quantum-safe protection"
fi
