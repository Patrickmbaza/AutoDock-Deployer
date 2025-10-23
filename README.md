🚀 AutoDock Deployer

A production-grade Bash automation script that automates the end-to-end deployment of Dockerized applications to remote Linux servers.

📖 Overview

This script automates everything required to take a containerized application from a Git repository to a running instance on a remote Linux server, complete with Docker, Nginx, and validation.

It’s designed to reflect real-world DevOps workflows — combining provisioning, deployment, and validation in a single, reliable, idempotent Bash workflow.

⚙️ Key Features

Interactive parameter collection with validation

Secure Git clone using Personal Access Token (PAT)

Remote provisioning: installs Docker, Docker Compose, and Nginx

Builds and runs application containers

Configures Nginx as a reverse proxy

Health checks and validation

Structured logging with color-coded output

Cleanup and redeploy support

Fully POSIX-compliant and idempotent

🧠 Requirements

Linux (Ubuntu 20.04+ recommended)

Bash 5.0+

SSH access to remote server

GitHub Personal Access Token (PAT)

Dockerfile or docker-compose.yml in your repo

🧩 Setup

Make the script executable:

chmod +x deploy.sh


Run the script:

./deploy.sh


Follow the prompts:

GitHub repo URL (HTTPS)

Personal Access Token

Branch (default: main)

Remote SSH credentials

Application port

🧱 Logging

All logs are automatically stored in:

logs/deploy_YYYYMMDD_HHMMSS.log

🧹 Cleanup

To remove all deployed resources:

./deploy.sh --cleanup


This removes containers, Docker images, Nginx config, and project files from the remote server.

📦 Example Deployment Flow
./deploy.sh
# Follow prompts
# Wait for setup and provisioning
# Access your app at http://<server-ip>

👨‍💻 Author

Mbaza Patrick
DevOps Engineer | AWS | Kubernetes | CI/CD | Automation
📧 gotehmbaza@gmail.com

🔗 LinkedIn

💻 GitHub

🏆 Learning Outcome

This project demonstrates:

Infrastructure automation with Bash

Remote provisioning and container management

CI/CD-style deployment logic

Logging, error handling, and idempotency best practices