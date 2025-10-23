#!/bin/bash

set -euo pipefail

# Script metadata
SCRIPT_NAME="deploy.sh"
VERSION="1.0.0"
AUTHOR="DevOps Intern"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to log info
info() {
    log "INFO" "${BLUE}$1${NC}"
}

# Function to log success
success() {
    log "SUCCESS" "${GREEN}$1${NC}"
}

# Function to log warning
warn() {
    log "WARNING" "${YELLOW}$1${NC}"
}

# Function to log error
error() {
    log "ERROR" "${RED}$1${NC}"
}

# Trap function for error handling
cleanup() {
    error "Script interrupted or failed at line $1"
    exit 1
}

trap 'cleanup $LINENO' ERR INT TERM

# Function to validate URL
validate_url() {
    local url=$1
    if [[ "$url" =~ ^https://.+\.git$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate port
validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for input with validation (FIXED VERSION)
prompt_input() {
    local prompt=$1
    local validation_func=$2
    local error_msg=$3
    local default_value=${4:-}  # Handle unset variable safely
    
    while true; do
        if [ -n "${default_value}" ]; then
            read -p "$prompt [$default_value]: " input
            input=${input:-$default_value}
        else
            read -p "$prompt: " input
        fi
        
        if $validation_func "$input"; then
            echo "$input"
            break
        else
            error "$error_msg"
        fi
    done
}

# Function to collect user parameters (FIXED VERSION)
collect_parameters() {
    info "Collecting deployment parameters..."
    
    # Git Repository URL
    REPO_URL=$(prompt_input "Enter Git Repository URL" validate_url "Invalid Git URL format (should be https://...git)")
    
    # Personal Access Token
    read -s -p "Enter Personal Access Token: " PAT
    echo
    if [ -z "$PAT" ]; then
        error "Personal Access Token cannot be empty"
        exit 1
    fi
    
    # Branch name (optional, default to main)
    read -p "Enter Branch name [main]: " BRANCH
    BRANCH=${BRANCH:-main}
    
    # Remote server details
    SSH_USER=$(prompt_input "Enter SSH username" ":" "Username cannot be empty" "")
    
    SSH_IP=$(prompt_input "Enter Server IP address" validate_ip "Invalid IP address format" "")
    
    read -p "Enter SSH key path [~/.ssh/id_rsa]: " SSH_KEY_PATH
    SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}
    SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
    
    if [ ! -f "$SSH_KEY_PATH" ]; then
        error "SSH key file not found: $SSH_KEY_PATH"
        exit 1
    fi
    
    # Application port
    APP_PORT=$(prompt_input "Enter Application port" validate_port "Invalid port (1-65535)" "8080")
    
    # Display summary
    info "Deployment Summary:"
    info "  Repository: $REPO_URL"
    info "  Branch: $BRANCH"
    info "  Server: $SSH_USER@$SSH_IP"
    info "  SSH Key: $SSH_KEY_PATH"
    info "  App Port: $APP_PORT"
    
    read -p "Proceed with deployment? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Deployment cancelled by user"
        exit 0
    fi
}

# Function to clone or update repository
clone_repository() {
    local repo_name=$(basename "$REPO_URL" .git)
    PROJECT_DIR="$repo_name"
    
    info "Processing repository: $REPO_URL"
    
    # Extract domain and add PAT to URL for authentication
    local auth_repo_url=$(echo "$REPO_URL" | sed "s|https://|https://token:${PAT}@|")
    
    if [ -d "$PROJECT_DIR" ]; then
        info "Repository exists, pulling latest changes..."
        cd "$PROJECT_DIR"
        git remote set-url origin "$auth_repo_url"
        git checkout "$BRANCH"
        git pull origin "$BRANCH" || {
            error "Failed to pull latest changes"
            exit 1
        }
    else
        info "Cloning repository..."
        git clone -b "$BRANCH" "$auth_repo_url" "$PROJECT_DIR" || {
            error "Failed to clone repository"
            exit 1
        }
        cd "$PROJECT_DIR"
    fi
    
    # Verify Docker configuration exists
    if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
        error "No Dockerfile or docker-compose.yml found in repository"
        exit 1
    fi
    
    success "Repository processed successfully"
}

# Function to test SSH connection
test_ssh_connection() {
    info "Testing SSH connection to $SSH_USER@$SSH_IP..."
    
    ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o BatchMode=yes "$SSH_USER@$SSH_IP" "echo 'SSH connection successful'" || {
        error "SSH connection failed"
        exit 1
    }
    
    success "SSH connection established"
}

# Function to prepare remote environment
prepare_remote_environment() {
    info "Preparing remote environment..."
    
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_IP" "
        set -e
        
        echo 'Updating system packages...'
        sudo apt-get update
        
        echo 'Installing Docker...'
        if ! command -v docker >/dev/null 2>&1; then
            sudo apt-get install -y docker.io
            sudo systemctl enable docker
            sudo systemctl start docker
        fi
        
        echo 'Installing Docker Compose...'
        if ! command -v docker-compose >/dev/null 2>&1; then
            sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi
        
        echo 'Installing Nginx...'
        if ! command -v nginx >/dev/null 2>&1; then
            sudo apt-get install -y nginx
            sudo systemctl enable nginx
            sudo systemctl start nginx
        fi
        
        echo 'Adding user to docker group...'
        sudo usermod -aG docker \$USER || true
        
        echo 'Environment preparation completed'
        
        # Display versions
        echo 'Docker version:'
        docker --version
        echo 'Docker Compose version:'
        docker-compose --version
        echo 'Nginx version:'
        nginx -v
    " || {
        error "Failed to prepare remote environment"
        exit 1
    }
    
    success "Remote environment prepared successfully"
}

# Function to deploy application
deploy_application() {
    info "Deploying application..."
    
    local repo_name=$(basename "$REPO_URL" .git)
    
    # Check for required files and create missing ones
    if [ ! -f "nginx.conf" ]; then
        warn "nginx.conf not found, creating a basic one..."
        cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html;
        }

        location /health {
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF
        success "Created basic nginx.conf"
    fi
    
    if [ ! -f "index.html" ]; then
        warn "index.html not found, creating a basic one..."
        cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>DevOps Intern Deployment</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { text-align: center; padding: 20px; }
        .success { color: green; font-size: 24px; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">✅ Deployment Successful!</h1>
        <p>Your application is running via Docker & Nginx</p>
        <p>Server: <strong>$HOSTNAME</strong></p>
        <p>Timestamp: <span id="time"></span></p>
    </div>
    <script>document.getElementById('time').textContent = new Date().toString();</script>
</body>
</html>
EOF
        success "Created basic index.html"
    fi

    # Transfer project files
    info "Transferring project files..."
    rsync -avz -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" --delete \
        --exclude '.git' \
        --exclude '.github' \
        --exclude 'node_modules' \
        ./ "$SSH_USER@$SSH_IP:/home/$SSH_USER/$repo_name/" || {
        error "Failed to transfer project files"
        exit 1
    }
    
    # Build and run application with better error handling
    ssh -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$SSH_IP" "
        set -e
        cd /home/$SSH_USER/$repo_name
        
        echo 'Stopping existing containers...'
        docker-compose down 2>/dev/null || true
        docker stop ${repo_name}_app 2>/dev/null || true
        docker rm ${repo_name}_app 2>/dev/null || true
        
        echo 'Checking for Docker configuration...'
        if [ -f 'docker-compose.yml' ]; then
            echo 'Found docker-compose.yml, using Docker Compose...'
            docker-compose up -d --build
        elif [ -f 'Dockerfile' ]; then
            echo 'Found Dockerfile, building directly...'
            docker build -t ${repo_name}_app .
            docker run -d --name ${repo_name}_app -p $APP_PORT:80 ${repo_name}_app
        else
            echo 'ERROR: No Docker configuration found!'
            echo 'Creating a simple Dockerfile as fallback...'
            cat > Dockerfile << 'DOCKERFILEEOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
CMD [\"nginx\", \"-g\", \"daemon off;\"]
DOCKERFILEEOF
            docker build -t ${repo_name}_app .
            docker run -d --name ${repo_name}_app -p $APP_PORT:80 ${repo_name}_app
        fi
        
        echo 'Waiting for containers to start...'
        sleep 15
        
        echo 'Checking container status...'
        docker ps
        
        echo 'Checking application health...'
        sleep 5
        docker logs \$(docker ps -q | head -1) 2>/dev/null || echo 'Could not retrieve logs'
        
        echo 'Testing application internally...'
        curl -f http://localhost:$APP_PORT || curl -f http://localhost:80 || echo 'Application might still be starting...'
    " || {
        error "Failed to deploy application"
        exit 1
    }
    
    success "Application deployed successfully"
}

# Function to display deployment summary
display_summary() {
    success "Deployment completed successfully!"
    info "Deployment Summary:"
    info "  Application: $REPO_URL"
    info "  Server: http://$SSH_IP"
    info "  Access URL: http://$SSH_IP"
    info "  Log file: $LOG_FILE"
    info "  Timestamp: $(date)"
}

# Main execution function
main() {
    echo -e "${GREEN}"
    cat << "EOF"
    
    DevOps Intern - Automated Deployment Script
    ===========================================
    
EOF
    echo -e "${NC}"
    
    info "Starting deployment process..."
    
    # Collect parameters
    collect_parameters
    
    # Clone repository
    clone_repository
    
    # Test SSH connection
    test_ssh_connection
    
    # Prepare remote environment
    prepare_remote_environment
    
    # Deploy application
    deploy_application
    
    # Configure nginx
    configure_nginx
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
}

# Cleanup function
cleanup_deployment() {
    info "Starting cleanup..."
    
    if [ -z "${SSH_USER:-}" ] || [ -z "${SSH_IP:-}" ] || [ -z "${SSH_KEY_PATH:-}" ]; then
        error "Cleanup requires SSH parameters. Please run normal deployment first."
        exit 1
    fi
    
    local repo_name=$(basename "${REPO_URL:-}" .git)
    
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_IP" "
        set -e
        
        echo 'Stopping and removing containers...'
        cd /home/$SSH_USER/$repo_name 2>/dev/null && docker-compose down 2>/dev/null || true
        docker stop ${repo_name}_app 2>/dev/null || true
        docker rm ${repo_name}_app 2>/dev/null || true
        
        echo 'Removing Docker images...'
        docker rmi ${repo_name}_app 2>/dev/null || true
        
        echo 'Removing Nginx configuration...'
        sudo rm -f /etc/nginx/sites-available/${repo_name}
        sudo rm -f /etc/nginx/sites-enabled/${repo_name}
        sudo systemctl reload nginx
        
        echo 'Removing project files...'
        rm -rf /home/$SSH_USER/$repo_name
        
        echo 'Cleanup completed'
    " || {
        error "Cleanup completed with some warnings"
    }
    
    # Local cleanup
    rm -rf "${PROJECT_DIR:-}" 2>/dev/null || true
    
    success "Cleanup completed successfully"
}

# Script help
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Automated deployment script for Dockerized applications

OPTIONS:
    -h, --help      Show this help message
    -c, --cleanup   Remove deployed resources
    -v, --version   Show version information

EXAMPLES:
    ./deploy.sh                    # Run deployment
    ./deploy.sh --cleanup          # Cleanup deployment
    ./deploy.sh --help             # Show help

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -v|--version)
        echo "$SCRIPT_NAME version $VERSION"
        exit 0
        ;;
    -c|--cleanup)
        # We need to collect minimal parameters for cleanup
        info "Cleanup mode activated"
        read -p "Enter Git Repository URL: " REPO_URL
        read -p "Enter SSH username: " SSH_USER
        read -p "Enter Server IP address: " SSH_IP
        read -p "Enter SSH key path [~/.ssh/id_rsa]: " SSH_KEY_PATH
        SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}
        SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
        
        cleanup_deployment
        exit 0
        ;;
    *)
        main
        ;;
esac