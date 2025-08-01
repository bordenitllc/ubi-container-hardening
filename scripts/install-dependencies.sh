#!/bin/bash
# Simple Multi-OS Compliance Hardening Script
# Uses ComplianceAsCode/content repository
# Supports RHEL/UBI 8, 9, and 10

set -e

# Default version if not provided
DEFAULT_COMPLIANCE_AS_CODE_VERSION="0.1.77"

# Parse command line arguments
usage() {
    echo "Usage: $0 [--version VERSION]"
    echo "  --version VERSION    Specify ComplianceAsCode version (default: $DEFAULT_COMPLIANCE_AS_CODE_VERSION)"
    echo "  -h, --help          Show this help message"
    exit 1
}

# Check if COMPLIANCE_AS_CODE_VERSION environment variable is set, otherwise use default
COMPLIANCE_AS_CODE_VERSION="${COMPLIANCE_AS_CODE_VERSION:-$DEFAULT_COMPLIANCE_AS_CODE_VERSION}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            COMPLIANCE_AS_CODE_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "Using ComplianceAsCode version: $COMPLIANCE_AS_CODE_VERSION"

# Detect OS version
if [ -f /etc/redhat-release ]; then
    OS_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -n1)
    echo "Detected RHEL/UBI version: $OS_VERSION"
else
    echo "Error: Could not detect Red Hat based OS"
    exit 1
fi

# Install packages based on OS version
dnf update -y
dnf install -y postfix unzip git

case $OS_VERSION in
    8)
        dnf install -y mailx python3.11-pip
        PYTHON_CMD="python3.11"
        PLAYBOOK_PATH="ansible/rhel8-playbook-stig.yml"
        ANSIBLE_VERSION="ansible==7.4.0"
        SKIP_TAGS="sudo_remove_no_authenticate,sudo_remove_nopasswd,sudoers_default_includedir,sudo_require_reauthentication,sudoers_validate_passwd,package_rng-tools_installed,enable_authselect,DISA-STIG-RHEL-08-040110"
        ;;
    9)
        dnf install -y s-nail python3-pip
        PYTHON_CMD="python3"
        PLAYBOOK_PATH="ansible/rhel9-playbook-stig.yml"
        ANSIBLE_VERSION="ansible==8.6.0"
        SKIP_TAGS="sudo_remove_no_authenticate,sudo_remove_nopasswd,sudoers_default_includedir,sudo_require_reauthentication,sudoers_validate_passwd,package_rng-tools_installed,enable_authselect,DISA-STIG-RHEL-09-040110"
        ;;
    10)
        dnf install -y s-nail python3-pip
        PYTHON_CMD="python3"
        PLAYBOOK_PATH="ansible/rhel10-playbook-stig.yml"
        ANSIBLE_VERSION="ansible==8.6.0"
        SKIP_TAGS="sudo_remove_no_authenticate,sudo_remove_nopasswd,sudoers_default_includedir,sudo_require_reauthentication,sudoers_validate_passwd,package_rng-tools_installed,enable_authselect,DISA-STIG-RHEL-10-040110"
        ;;
    *)
        echo "Error: Unsupported OS version: $OS_VERSION"
        echo "Supported versions: RHEL/UBI 8, 9, 10"
        exit 1
        ;;
esac

# Create virtual environment and run hardening
$PYTHON_CMD -m venv ansibletemp
source ansibletemp/bin/activate \
    && python3 -m pip install --upgrade pip \
    && python3 -m pip install ${ANSIBLE_VERSION} \
    && echo "Fetching SCAP Security Guide release v${COMPLIANCE_AS_CODE_VERSION}..." \
    && RELEASE_TAG="v${COMPLIANCE_AS_CODE_VERSION}" \
    && ASSET_URL="https://github.com/ComplianceAsCode/content/releases/download/$RELEASE_TAG/scap-security-guide-${COMPLIANCE_AS_CODE_VERSION}.zip" \
    && curl -L -o content.zip "$ASSET_URL" \
    && unzip -q content.zip -d temp_content \
    && mv temp_content/scap-security-guide-*/ content \
    && rm -rf temp_content content.zip \
    && echo "=== Full directory listing under 'content/' ===" \
    && ls -R content \
    && ansible-playbook -i "localhost," -c local "content/$PLAYBOOK_PATH" --skip-tags="$SKIP_TAGS"

# Set FIPS crypto policy
update-crypto-policies --set FIPS

echo "Hardening completed successfully for RHEL/UBI $OS_VERSION using ComplianceAsCode v${COMPLIANCE_AS_CODE_VERSION}"
