#!/bin/bash
# install-postiz.sh - Install Docker + Docker Compose and deploy Postiz with default config
set -euo pipefail

log() { echo -e "[$(date +'%F %T')] $*"; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

log "Starting Postiz installation (Docker + Docker Compose + stack)..."

# Update system on Debian/Ubuntu-like systems
if need_cmd apt-get; then
  log "Updating apt package lists and upgrading packages..."
  sudo apt-get update -y && sudo apt-get upgrade -y
fi

# Install Docker if missing
if ! need_cmd docker; then
  log "Installing Docker Engine via get.docker.com..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  rm -f get-docker.sh
fi

# Install Docker Compose plugin if missing
if ! docker compose version >/dev/null 2>&1; then
  if need_cmd apt-get; then
    log "Installing docker-compose-plugin..."
    sudo apt-get update -y
    sudo apt-get install -y docker-compose-plugin
  else
    log "Could not auto-install docker-compose-plugin on this distro. Please install it manually and re-run."
    exit 1
  fi
fi

# Add current user to docker group (takes effect after re-login)
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx "docker"; then
  log "Adding user '$USER' to docker group (you may need to log out/in)..."
  sudo usermod -aG docker "$USER" || true
fi

# Prepare working directory
WORKDIR="postiz"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Write docker-compose.yml with default config exactly as requested
log "Writing docker-compose.yml..."
cat > docker-compose.yml <<'YAML'
services:
  postiz:
    image: ghcr.io/gitroomhq/postiz-app:latest
    container_name: postiz
    restart: always
    environment:
      MAIN_URL: "http://localhost:5000"
      FRONTEND_URL: "http://localhost:5000"
      NEXT_PUBLIC_BACKEND_URL: "http://localhost:5000/api"
      JWT_SECRET: "random string that is unique to every install - just type random characters here!"

      # postiz-postgres or postiz-redis services below.
      DATABASE_URL: "postgresql://postiz-user:postiz-password@postiz-postgres:5432/postiz-db-local"
      REDIS_URL: "redis://postiz-redis:6379"
      BACKEND_INTERNAL_URL: "http://localhost:3000"
      IS_GENERAL: "true" # Required for self-hosting.
      DISABLE_REGISTRATION: "false" # Only allow single registration, then disable signup
      # The container images are pre-configured to use /uploads for file storage.
      # You probably should not change this unless you have a really good reason!
      STORAGE_PROVIDER: "local"
      UPLOAD_DIRECTORY: "/uploads"
      NEXT_PUBLIC_UPLOAD_DIRECTORY: "/uploads"

      # You need to set these environment variables to use the various social media integrations
      YOUTUBE_CLIENT_ID: ''
      YOUTUBE_CLIENT_SECRET: ''
      X_API_KEY: ''
      X_API_SECRET: ''
      THREADS_APP_ID: ''
      THREADS_APP_SECRET: ''
      TELEGRAM_BOT_NAME: ''
      TELEGRAM_TOKEN: ''
      SLACK_ID: ''
      SLACK_SECRET: ''
      REDDIT_CLIENT_ID: ''
      REDDIT_CLIENT_SECRET: ''
      PINTEREST_CLIENT_ID: ''
      PINTEREST_CLIENT_SECRET: ''
      MASTODON_CLIENT_ID: ''
      MASTODON_CLIENT_SECRET: ''
      LINKEDIN_CLIENT_ID: ''
      LINKEDIN_CLIENT_SECRET: ''
      FACEBOOK_APP_ID: ''
      FACEBOOK_APP_SECRET: ''
      DISCORD_CLIENT_ID: ''
      DISCORD_CLIENT_SECRET: ''
      INSTAGRAM_APP_ID: ''
      INSTAGRAM_APP_SECRET: ''
    volumes:
      - postiz-config:/config/
      - postiz-uploads:/uploads/
    ports:
      - 5000:5000
    networks:
      - postiz-network
    depends_on:
      postiz-postgres:
        condition: service_healthy
      postiz-redis:
        condition: service_healthy
 
  postiz-postgres:
    image: postgres:17-alpine
    container_name: postiz-postgres
    restart: always
    environment:
      POSTGRES_PASSWORD: postiz-password
      POSTGRES_USER: postiz-user
      POSTGRES_DB: postiz-db-local
    volumes:
      - postgres-volume:/var/lib/postgresql/data
    networks:
      - postiz-network
    healthcheck:
      test: pg_isready -U postiz-user -d postiz-db-local
      interval: 10s
      timeout: 3s
      retries: 3
  postiz-redis:
    image: redis:7.2
    container_name: postiz-redis
    restart: always
    healthcheck:
      test: redis-cli ping
      interval: 10s
      timeout: 3s
      retries: 3
    volumes:
      - postiz-redis-data:/data
    networks:
      - postiz-network
 
 
volumes:
  postgres-volume:
    external: false
 
  postiz-redis-data:
    external: false
 
  postiz-config:
    external: false
 
  postiz-uploads:
    external: false
 
networks:
  postiz-network:
    external: false
YAML

# Deploy
log "Bringing up the Postiz stack..."
docker compose up -d

log "Deployment complete. Containers running:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo
echo "✅ Postiz is up. Open: http://localhost:5000"
echo "If you were just added to the docker group, log out and back in for it to take effect."
