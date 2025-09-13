#!/usr/bin/env bash
# setup-postiz.sh - Interactive configurator and deployer for Postiz
set -euo pipefail

log() { echo -e "[$(date +'%F %T')] $*"; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }
read_input() { local prompt="$1"; local var; read -r -p "$prompt" var || true; echo "$var"; }

# --- Ensure Docker & Compose ---
ensure_docker() {
  if need_cmd apt-get; then
    sudo apt-get update -y >/dev/null 2>&1 || true
  fi
  if ! need_cmd docker; then
    log "Installing Docker Engine via get.docker.com..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm -f get-docker.sh
  fi
  if ! docker compose version >/dev/null 2>&1; then
    if need_cmd apt-get; then
      log "Installing docker-compose-plugin..."
      sudo apt-get update -y
      sudo apt-get install -y docker-compose-plugin
    else
      log "Please install Docker Compose plugin manually and re-run."
      exit 1
    fi
  fi
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx "docker"; then
    log "Adding user '$USER' to docker group (log out/in for it to apply)."
    sudo usermod -aG docker "$USER" || true
  fi
}

# --- Config State ---
# Defaults fixed as requested
MAIN_URL="http://localhost:5000"
FRONTEND_URL="http://localhost:5000"
NEXT_PUBLIC_BACKEND_URL="http://localhost:5000/api"
BACKEND_INTERNAL_URL="http://localhost:3000"
DATABASE_URL="postgresql://postiz-user:postiz-password@postiz-postgres:5432/postiz-db-local"
REDIS_URL="redis://postiz-redis:6379"

# Changeable in wizard
JWT_SECRET=""

# Social keys (empty by default)
SOCIAL_KEYS=(
  YOUTUBE_CLIENT_ID YOUTUBE_CLIENT_SECRET
  X_API_KEY X_API_SECRET
  THREADS_APP_ID THREADS_APP_SECRET
  TELEGRAM_BOT_NAME TELEGRAM_TOKEN
  SLACK_ID SLACK_SECRET
  REDDIT_CLIENT_ID REDDIT_CLIENT_SECRET
  PINTEREST_CLIENT_ID PINTEREST_CLIENT_SECRET
  MASTODON_CLIENT_ID MASTODON_CLIENT_SECRET
  LINKEDIN_CLIENT_ID LINKEDIN_CLIENT_SECRET
  FACEBOOK_APP_ID FACEBOOK_APP_SECRET
  DISCORD_CLIENT_ID DISCORD_CLIENT_SECRET
  INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET
)

declare -A KV
for k in "${SOCIAL_KEYS[@]}"; do KV["$k"]=""; done

# --- Helper to generate JWT ---
rand_jwt() {
  if need_cmd openssl; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# --- Menus ---
menu_main() {
  while true; do
    clear 2>/dev/null || true
    echo "=== Postiz Interactive Setup ==="
    echo
    echo "Fixed defaults (as requested):"
    echo "- MAIN_URL:                $MAIN_URL"
    echo "- FRONTEND_URL:            $FRONTEND_URL"
    echo "- NEXT_PUBLIC_BACKEND_URL: $NEXT_PUBLIC_BACKEND_URL"
    echo "- BACKEND_INTERNAL_URL:    $BACKEND_INTERNAL_URL"
    echo "- DATABASE_URL:            $DATABASE_URL"
    echo "- REDIS_URL:               $REDIS_URL"
    echo
    if [[ -n "$JWT_SECRET" ]]; then
      echo "JWT_SECRET: [SET]"
    else
      echo "JWT_SECRET: (not set)"
    fi
    echo "Configured social keys (non-empty only):"
    local any=0
    for k in "${SOCIAL_KEYS[@]}"; do
      if [[ -n "${KV[$k]}" ]]; then echo "  - $k: [SET]"; any=1; fi
    done
    [[ $any -eq 0 ]] && echo "  (none)"
    echo
    echo "1) Set or generate JWT_SECRET"
    echo "2) Configure social API keys"
    echo "3) Preview docker-compose.yml"
    echo "4) Deploy (write compose + start containers)"
    echo "q) Quit without changes"
    choice=$(read_input "> Select an option: ")
    case "$choice" in
      1) menu_jwt ;;
      2) menu_social ;;
      3) preview_compose ; read -r -p "Press Enter to go back..." _ ;;
      4) deploy ; exit 0 ;;
      q|Q) echo "Goodbye"; exit 0 ;;
      *) ;;
    esac
  done
}

menu_jwt() {
  while true; do
    clear 2>/dev/null || true
    echo "--- JWT Secret ---"
    echo "Current: $( [[ -n "$JWT_SECRET" ]] && echo "[SET]" || echo "(not set)" )"
    echo "1) Generate random JWT secret"
    echo "2) Enter JWT secret manually"
    echo "b) Back"
    choice=$(read_input "> ")
    case "$choice" in
      1) JWT_SECRET=$(rand_jwt); echo "Generated."; sleep 0.6 ;;
      2) JWT_SECRET=$(read_input "Enter JWT secret: "); ;;
      b|B) return ;;
      *) ;;
    esac
  done
}

menu_social() {
  while true; do
    clear 2>/dev/null || true
    echo "--- Social API Keys ---"
    echo "Choose a key to edit (enter number), or b) back"
    local i=1
    declare -a idxmap=()
    for k in "${SOCIAL_KEYS[@]}"; do
      printf "%2d) %-24s %s\n" "$i" "$k" "$( [[ -n "${KV[$k]}" ]] && echo "[SET]" || echo "" )"
      idxmap[$i]="$k"
      ((i++))
    done
    echo "a) Set multiple (comma-separated numbers)"
    echo "c) Clear all social keys"
    echo "b) Back"
    choice=$(read_input "> ")
    case "$choice" in
      b|B) return ;;
      a|A)
        list=$(read_input "Numbers (e.g. 1,2,5): ")
        IFS=',' read -r -a arr <<<"$list"
        for n in "${arr[@]}"; do
          n=$(echo "$n" | xargs)
          [[ -z "$n" ]] && continue
          if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<i )); then
            key="${idxmap[$n]}"
            val=$(read_input "Value for $key (empty keeps empty): ")
            KV["$key"]="$val"
          fi
        done
        ;;
      c|C)
        read -r -p "Confirm clear all? (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && for k in "${SOCIAL_KEYS[@]}"; do KV["$k"]=""; done
        ;;
      *)
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<i )); then
          key="${idxmap[$choice]}"
          val=$(read_input "Value for $key (empty keeps empty): ")
          KV["$key"]="$val"
        fi
        ;;
    esac
  done
}

preview_compose() {
  echo "--- docker-compose.yml preview ---"
  generate_compose | sed 's/^/  /'
}

generate_compose() {
  cat <<YAML
services:
  postiz:
    image: ghcr.io/gitroomhq/postiz-app:latest
    container_name: postiz
    restart: always
    environment:
      MAIN_URL: "$MAIN_URL"
      FRONTEND_URL: "$FRONTEND_URL"
      NEXT_PUBLIC_BACKEND_URL: "$NEXT_PUBLIC_BACKEND_URL"
      JWT_SECRET: "${JWT_SECRET:-random string that is unique to every install - just type random characters here!}"

      # postiz-postgres or postiz-redis services below.
      DATABASE_URL: "$DATABASE_URL"
      REDIS_URL: "$REDIS_URL"
      BACKEND_INTERNAL_URL: "$BACKEND_INTERNAL_URL"
      IS_GENERAL: "true" # Required for self-hosting.
      DISABLE_REGISTRATION: "false" # Only allow single registration, then disable signup
      # The container images are pre-configured to use /uploads for file storage.
      # You probably should not change this unless you have a really good reason!
      STORAGE_PROVIDER: "local"
      UPLOAD_DIRECTORY: "/uploads"
      NEXT_PUBLIC_UPLOAD_DIRECTORY: "/uploads"

$(for k in "${SOCIAL_KEYS[@]}"; do printf "      %s: '%s'\n" "$k" "${KV[$k]}"; done)
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
}

deploy() {
  ensure_docker
  WORKDIR="postiz"
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"
  log "Writing docker-compose.yml..."
  generate_compose > docker-compose.yml
  log "Starting containers (docker compose up -d)..."
  docker compose up -d
  log "Deployment complete."
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  echo
  echo "Open: http://localhost:5000"
}

menu_main
