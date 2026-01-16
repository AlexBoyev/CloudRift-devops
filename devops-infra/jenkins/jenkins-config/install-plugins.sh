#!/bin/bash

# Jenkins Plugin Installation Script
# This script installs Jenkins plugins from plugins.txt using jenkins-plugin-cli

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() { printf "${GREEN}[PLUGIN-INSTALL]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# Wait for Jenkins to be ready
wait_for_jenkins() {
    local max_attempts=60
    local attempt=1
    
    log "Waiting for Jenkins to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "http://localhost:8080/login" > /dev/null 2>&1; then
            log "Jenkins is ready!"
            return 0
        fi
        
        if [ $((attempt % 10)) -eq 0 ]; then
            log "Still waiting for Jenkins... (attempt $attempt/$max_attempts)"
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
    
    err "Jenkins failed to start within expected time"
    return 1
}

# Install plugins from plugins.txt
install_plugins() {
    local plugins_file="/var/lib/jenkins/plugins.txt"
    local jenkins_cli="/opt/jenkins-cli.jar"
    
    if [ ! -f "$plugins_file" ]; then
        err "plugins.txt file not found at $plugins_file"
        return 1
    fi
    
    log "Installing plugins from $plugins_file"
    
    # Download jenkins-cli.jar if not exists
    if [ ! -f "$jenkins_cli" ]; then
        log "Downloading jenkins-cli.jar..."
        curl -s -L "http://localhost:8080/jnlpJars/jenkins-cli.jar" -o "$jenkins_cli"
    fi
    
    # Read plugins.txt and install each plugin
    while IFS= read -r plugin_line || [ -n "$plugin_line" ]; do
        # Skip comments and empty lines
        if [[ $plugin_line =~ ^[[:space:]]*# ]] || [[ -z "${plugin_line// }" ]]; then
            continue
        fi
        
        # Extract plugin name (remove version specification)
        plugin_name=$(echo "$plugin_line" | cut -d':' -f1)
        
        if [ -n "$plugin_name" ]; then
            log "Installing plugin: $plugin_name"
            java -jar "$jenkins_cli" -s "http://localhost:8080/" install-plugin "$plugin_name" -restart || warn "Failed to install $plugin_name"
        fi
    done < "$plugins_file"
    
    log "Plugin installation completed"
}

# Alternative method using jenkins-plugin-cli (if available)
install_plugins_with_cli() {
    local plugins_file="/var/lib/jenkins/plugins.txt"
    
    if [ ! -f "$plugins_file" ]; then
        err "plugins.txt file not found at $plugins_file"
        return 1
    fi
    
    log "Installing plugins using jenkins-plugin-cli"
    
    # Check if jenkins-plugin-cli is available
    if command -v jenkins-plugin-cli >/dev/null 2>&1; then
        jenkins-plugin-cli --plugin-file "$plugins_file" --jenkins-update-center "https://updates.jenkins.io/update-center.json"
    else
        warn "jenkins-plugin-cli not found, falling back to jenkins-cli method"
        install_plugins
    fi
}

# Main execution
main() {
    log "Starting Jenkins plugin installation"
    
    # Wait for Jenkins to be ready
    if wait_for_jenkins; then
        # Try installing plugins
        install_plugins_with_cli || install_plugins || err "Plugin installation failed"
        
        log "Restarting Jenkins to activate plugins..."
        systemctl restart jenkins
        
        # Wait for restart
        sleep 10
        wait_for_jenkins
        
        log "Jenkins plugin installation and restart completed!"
    else
        err "Jenkins is not ready, aborting plugin installation"
        exit 1
    fi
}

# Run main function
main "$@"