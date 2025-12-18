#!/usr/bin/env bash
set -euo pipefail

# postiz_install_interactive.sh - Interaktywny instalator Postiz
# Wersja: 1.1.0
# Dla: Mikrus.us VPS (i innych serwerów z Dockerem)

SCRIPT_NAME="$(basename "$0")"

# === Kolory i formatowanie ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { printf "${GREEN}[${SCRIPT_NAME}]${NC} %s\n" "$*"; }
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die() { error "$*"; exit 1; }
success() { printf "${GREEN}✓${NC} %s\n" "$*"; }

# === Sprawdzenie uprawnień root ===
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "Uruchom jako root: sudo $0"
fi

# === Sprawdzenie Docker ===
if ! command -v docker &>/dev/null; then
  die "Docker nie jest zainstalowany. Zainstaluj: curl -fsSL https://get.docker.com | sh"
fi

if ! docker ps &>/dev/null; then
  die "Docker nie działa lub brak uprawnień. Sprawdź: systemctl status docker"
fi

# === Banner ===
clear
cat <<'EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║         Postiz Interactive Installer v1.1                 ║
║         dla Mikrus.us i innych VPS z Dockerem             ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo ""
log "Ten skrypt zainstaluje Postiz z PostgreSQL i Redis"
log "Będziesz mógł połączyć Postiz z istniejącym kontenerem n8n"
echo ""
info "Naciśnij Enter aby użyć domyślnej wartości [w nawiasach]"
echo ""

# === Funkcje pomocnicze ===

# Czyta input z domyślną wartością
read_with_default() {
  local prompt="$1"
  local default="$2"
  local result

  read -r -p "$(printf "${BLUE}${prompt}${NC} [${GREEN}${default}${NC}]: ")" result
  echo "${result:-$default}"
}

# Czyta yes/no z domyślną wartością
read_yes_no() {
  local prompt="$1"
  local default="$2"  # "y" lub "n"
  local result

  if [[ "$default" == "y" ]]; then
    read -r -p "$(printf "${BLUE}${prompt}${NC} [${GREEN}Y/n${NC}]: ")" result
    result="${result:-y}"
  else
    read -r -p "$(printf "${BLUE}${prompt}${NC} [${GREEN}y/N${NC}]: ")" result
    result="${result:-n}"
  fi

  [[ "$result" =~ ^[Yy]$ ]]
}

# Generuje secret
gen_secret() {
  local length="${1:-32}"
  openssl rand -base64 48 | tr -d '\n' | tr '+/' 'ab' | cut -c1-"$length"
}

# Sprawdza czy port jest zajęty
check_port() {
  local port="$1"
  if ss -tulpn 2>/dev/null | grep -qE "[:[]${port}]?\$"; then
    return 0  # zajęty
  fi
  return 1  # wolny
}

# === Automatyczna detekcja parametrów ===

detect_server_name() {
  hostname | cut -d'.' -f1
}

detect_port_from_hostname() {
  local hostname_short
  hostname_short="$(detect_server_name)"

  # Mikrus format: antoniXXX → port 30XXX
  if [[ "$hostname_short" =~ ^antoni([0-9]+)$ ]]; then
    local id="${BASH_REMATCH[1]}"
    echo "30${id}"
  else
    echo "30115"  # domyślny
  fi
}

detect_domain() {
  local server_name port
  server_name="$(detect_server_name)"
  port="$1"

  # Format wykr.es: srvNAME-PORT.wykr.es
  echo "${server_name}-${port}.wykr.es"
}

detect_n8n_container() {
  docker ps --format '{{.Names}}' | grep -E '^n8n$' | head -n1 || echo ""
}

check_network_exists() {
  local network="$1"
  docker network ls --format '{{.Name}}' | grep -qE "^${network}$"
}

# === Zbieranie parametrów ===

echo ""
log "=== Konfiguracja podstawowa ==="
echo ""

# 1. Port
DEFAULT_PORT="$(detect_port_from_hostname)"
HOST_PORT="$(read_with_default "Port na którym ma działać Postiz (20000-65535)" "$DEFAULT_PORT")"

# Walidacja portu
if ! [[ "$HOST_PORT" =~ ^[0-9]+$ ]] || [[ "$HOST_PORT" -lt 1024 ]] || [[ "$HOST_PORT" -gt 65535 ]]; then
  die "Niepoprawny port: $HOST_PORT (dozwolone: 1024-65535)"
fi

if check_port "$HOST_PORT"; then
  warn "Port $HOST_PORT wygląda na zajęty"
  if ! read_yes_no "Kontynuować mimo to?" "n"; then
    die "Przerwano. Wybierz inny port lub zwolnij $HOST_PORT"
  fi
fi

success "Port: $HOST_PORT"

# 2. Domena
DEFAULT_DOMAIN="$(detect_domain "$HOST_PORT")"
DOMAIN="$(read_with_default "Domena/subdomena dla Postiz" "$DEFAULT_DOMAIN")"
success "Domena: $DOMAIN"

# 3. Katalog instalacji
DEFAULT_INSTALL_DIR="/srv/postiz"
INSTALL_DIR="$(read_with_default "Katalog instalacji" "$DEFAULT_INSTALL_DIR")"
success "Katalog: $INSTALL_DIR"

# Sprawdź czy katalog istnieje
if [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
  warn "Katalog $INSTALL_DIR już zawiera instalację Postiz"
  if ! read_yes_no "Nadpisać instalację?" "n"; then
    die "Przerwano. Wybierz inny katalog lub usuń istniejącą instalację"
  fi

  warn "Tworzenie backupu..."
  BACKUP_DIR="${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
  mv "$INSTALL_DIR" "$BACKUP_DIR"
  success "Backup: $BACKUP_DIR"
fi

# 4. Sieć Docker
echo ""
log "=== Konfiguracja sieci Docker ==="
echo ""

DEFAULT_NETWORK="automation-net"
if check_network_exists "$DEFAULT_NETWORK"; then
  info "Wykryto istniejącą sieć: $DEFAULT_NETWORK"
  SHARED_NETWORK="$(read_with_default "Sieć Docker" "$DEFAULT_NETWORK")"
else
  info "Sieć automation-net nie istnieje, zostanie utworzona"
  SHARED_NETWORK="$(read_with_default "Nazwa sieci Docker" "$DEFAULT_NETWORK")"
fi

success "Sieć: $SHARED_NETWORK"

# 5. Integracja z n8n
echo ""
log "=== Integracja z n8n (opcjonalnie) ==="
echo ""

N8N_CONTAINER=""
DETECTED_N8N="$(detect_n8n_container)"

if [[ -n "$DETECTED_N8N" ]]; then
  info "Wykryto kontener n8n: $DETECTED_N8N"
  if read_yes_no "Podłączyć n8n do wspólnej sieci $SHARED_NETWORK?" "y"; then
    N8N_CONTAINER="$DETECTED_N8N"
  fi
else
  info "Nie wykryto kontenera n8n"
  if read_yes_no "Czy chcesz podłączyć istniejący kontener n8n?" "n"; then
    N8N_CONTAINER="$(read_with_default "Nazwa kontenera n8n" "n8n")"
  fi
fi

if [[ -n "$N8N_CONTAINER" ]]; then
  success "Integracja z n8n: $N8N_CONTAINER"
else
  info "Postiz będzie działać bez integracji n8n"
fi

# 6. Wybór obrazu Docker
echo ""
log "=== Wybór obrazu Postiz ==="
echo ""

info "Dostępne opcje:"
echo "  1) Oryginalny obraz (ghcr.io/gitroomhq/postiz-app:latest)"
echo "  2) Lokalny/zmodyfikowany obraz"
echo ""

USE_LOCAL_IMAGE="false"
POSTIZ_IMAGE="ghcr.io/gitroomhq/postiz-app:latest"

if read_yes_no "Użyć lokalnego/zmodyfikowanego obrazu?" "n"; then
  USE_LOCAL_IMAGE="true"
  POSTIZ_IMAGE="$(read_with_default "Nazwa lokalnego obrazu" "postiz-app:local")"

  # Sprawdź czy obraz istnieje
  if docker image inspect "$POSTIZ_IMAGE" &>/dev/null; then
    success "Obraz znaleziony: $POSTIZ_IMAGE"
  else
    warn "UWAGA: Obraz $POSTIZ_IMAGE nie został znaleziony lokalnie"
    info "Upewnij się, że zbudowałeś obraz przed uruchomieniem instalacji"
    if ! read_yes_no "Kontynuować mimo to?" "n"; then
      die "Przerwano. Zbuduj obraz lub użyj oryginalnego"
    fi
  fi
else
  success "Używam oryginalnego obrazu: $POSTIZ_IMAGE"
fi

# 7. Bezpieczeństwo
echo ""
log "=== Ustawienia bezpieczeństwa ==="
echo ""

DISABLE_REGISTRATION="false"
if read_yes_no "Wyłączyć rejestrację nowych użytkowników? (zalecane dla produkcji)" "y"; then
  DISABLE_REGISTRATION="true"
  success "Rejestracja zostanie wyłączona"
else
  warn "Rejestracja będzie włączona - każdy może utworzyć konto!"
fi

# === Podsumowanie konfiguracji ===

echo ""
log "=== Podsumowanie konfiguracji ==="
echo ""

cat <<EOF
  Domena:              https://${DOMAIN}
  Port:                ${HOST_PORT}
  Katalog:             ${INSTALL_DIR}
  Obraz:               ${POSTIZ_IMAGE}
  Sieć Docker:         ${SHARED_NETWORK}
  Integracja n8n:      ${N8N_CONTAINER:-brak}
  Rejestracja:         $([ "$DISABLE_REGISTRATION" = "true" ] && echo "wyłączona ✓" || echo "włączona")

  Kontenery:
    - postiz (Postiz App)
    - postiz-postgres (PostgreSQL 17)
    - postiz-redis (Redis 7.2)
EOF

echo ""
if ! read_yes_no "Rozpocząć instalację?" "y"; then
  die "Instalacja przerwana przez użytkownika"
fi

# === Instalacja ===

echo ""
log "=== Rozpoczynam instalację ==="
echo ""

# 1. Utwórz katalog
info "Tworzenie katalogu $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 2. Utwórz/sprawdź sieć Docker
if ! check_network_exists "$SHARED_NETWORK"; then
  info "Tworzenie sieci Docker: $SHARED_NETWORK..."
  docker network create "$SHARED_NETWORK"
  success "Sieć utworzona"
else
  success "Sieć $SHARED_NETWORK już istnieje"
fi

# 3. Podłącz n8n do sieci (jeśli wybrano)
if [[ -n "$N8N_CONTAINER" ]]; then
  info "Podłączanie $N8N_CONTAINER do sieci $SHARED_NETWORK..."

  if docker ps --format '{{.Names}}' | grep -qE "^${N8N_CONTAINER}\$"; then
    # Sprawdź czy już podłączony
    if docker inspect "$N8N_CONTAINER" | grep -q "\"$SHARED_NETWORK\""; then
      success "$N8N_CONTAINER już jest w sieci $SHARED_NETWORK"
    else
      docker network connect "$SHARED_NETWORK" "$N8N_CONTAINER" 2>/dev/null || true
      success "$N8N_CONTAINER podłączony do $SHARED_NETWORK"
    fi
  else
    warn "Kontener $N8N_CONTAINER nie działa, pomijam podłączanie"
  fi
fi

# 4. Generuj hasła i secrets
info "Generowanie haseł i kluczy..."
POSTGRES_PASSWORD="$(gen_secret 32)"
JWT_SECRET="$(gen_secret 64)"
success "Hasła wygenerowane"

# 5. Utwórz docker-compose.yml
info "Tworzenie docker-compose.yml..."

cat >"${INSTALL_DIR}/docker-compose.yml" <<EOF
# docker-compose.yml - Postiz + PostgreSQL + Redis
# Wygenerowano przez: $SCRIPT_NAME

services:
  postiz:
    image: ${POSTIZ_IMAGE}
    container_name: postiz
    restart: unless-stopped
    env_file: postiz.env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "${HOST_PORT}:5000"
    networks:
      - ${SHARED_NETWORK}
    volumes:
      - postiz-config:/config/
      - postiz-uploads:/uploads/
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  postgres:
    image: postgres:17-alpine
    container_name: postiz-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_USER: postiz
      POSTGRES_DB: postiz-db-local
    volumes:
      - postgres-volume:/var/lib/postgresql/data
    networks:
      - ${SHARED_NETWORK}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postiz -d postiz-db-local"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    image: redis:7.2-alpine
    container_name: postiz-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - postiz-redis-data:/data
    networks:
      - ${SHARED_NETWORK}
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 20s

volumes:
  postgres-volume:
    name: postiz_postgres-volume
  postiz-config:
    name: postiz_postiz-config
  postiz-redis-data:
    name: postiz_postiz-redis-data
  postiz-uploads:
    name: postiz_postiz-uploads

networks:
  ${SHARED_NETWORK}:
    external: true
EOF

success "docker-compose.yml utworzony"

# 6. Utwórz postiz.env
info "Tworzenie postiz.env..."

cat >"${INSTALL_DIR}/postiz.env" <<EOF
# postiz.env - Zmienne środowiskowe Postiz
# Wygenerowano przez: $SCRIPT_NAME
# Data: $(date '+%Y-%m-%d %H:%M:%S')

# === Main URL Settings
MAIN_URL="https://${DOMAIN}"
FRONTEND_URL="https://${DOMAIN}"
NEXT_PUBLIC_BACKEND_URL="https://${DOMAIN}/api"
BACKEND_INTERNAL_URL="http://localhost:3000"

# === Database (PostgreSQL)
DATABASE_URL="postgresql://postiz:${POSTGRES_PASSWORD}@postgres:5432/postiz-db-local"

# === Redis
REDIS_URL="redis://redis:6379"

# === JWT Secret (DO NOT SHARE!)
JWT_SECRET="${JWT_SECRET}"

# === Storage Settings
STORAGE_PROVIDER=local
UPLOAD_DIRECTORY=/uploads
NEXT_PUBLIC_UPLOAD_DIRECTORY=/uploads

# === Registration
IS_GENERAL=true
$([ "$DISABLE_REGISTRATION" = "true" ] && echo "DISABLE_REGISTRATION=true" || echo "#DISABLE_REGISTRATION=false")

# === Opcjonalne API Keys dla Social Media (uzupełnij później)
# X (Twitter)
#X_API_KEY=
#X_API_SECRET=

# LinkedIn
#LINKEDIN_CLIENT_ID=
#LINKEDIN_CLIENT_SECRET=

# Reddit
#REDDIT_CLIENT_ID=
#REDDIT_CLIENT_SECRET=

# GitHub
#GITHUB_CLIENT_ID=
#GITHUB_CLIENT_SECRET=

# === CloudFlare R2 (jeśli używasz - zobacz dokumentację)
# STORAGE_PROVIDER=cloudflare
# CLOUDFLARE_ACCOUNT_ID=
# CLOUDFLARE_ACCESS_KEY=
# CLOUDFLARE_SECRET_ACCESS_KEY=
# CLOUDFLARE_BUCKETNAME=
# CLOUDFLARE_BUCKET_URL=
# CLOUDFLARE_REGION=auto
EOF

chmod 600 "${INSTALL_DIR}/postiz.env"
success "postiz.env utworzony (chmod 600)"

# 7. Uruchom kontenery
info "Uruchamianie kontenerów Docker..."
docker compose up -d

echo ""
log "Czekam 10 sekund na uruchomienie..."
sleep 10

# 8. Sprawdź status
info "Sprawdzanie statusu kontenerów..."
docker compose ps

echo ""

# 9. Sprawdź healthcheck
if docker ps | grep -q "postiz.*healthy"; then
  success "Postiz działa i jest healthy!"
elif docker ps | grep -q "postiz"; then
  warn "Postiz działa, ale jeszcze nie jest healthy (trwa inicjalizacja)"
  info "Sprawdź za 30-60 sekund: docker logs postiz --tail 50"
else
  error "Postiz nie działa! Sprawdź logi: docker logs postiz --tail 100"
fi

# === Podsumowanie ===

echo ""
log "=== ✓ Instalacja zakończona! ==="
echo ""

cat <<EOF
╔═══════════════════════════════════════════════════════════╗
║                  POSTIZ ZAINSTALOWANY                     ║
╚═══════════════════════════════════════════════════════════╝

📍 URL: https://${DOMAIN}

🔐 Credentials (zapisz w bezpiecznym miejscu):
   PostgreSQL:
     User: postiz
     Password: ${POSTGRES_PASSWORD}
     Database: postiz-db-local

   JWT Secret: ${JWT_SECRET}

📂 Pliki:
   Instalacja: ${INSTALL_DIR}/
   Config: ${INSTALL_DIR}/postiz.env
   Compose: ${INSTALL_DIR}/docker-compose.yml

🐳 Kontenery:
   - postiz (port ${HOST_PORT})
   - postiz-postgres
   - postiz-redis

📊 Zarządzanie:
   Status:    cd ${INSTALL_DIR} && docker compose ps
   Logi:      docker logs postiz --tail 50
   Restart:   cd ${INSTALL_DIR} && docker compose restart
   Stop:      cd ${INSTALL_DIR} && docker compose down
   Start:     cd ${INSTALL_DIR} && docker compose up -d

🔄 Aktualizacja:
   cd ${INSTALL_DIR}
   docker compose pull
   docker compose down
   docker compose up -d

$(if [[ -n "$N8N_CONTAINER" ]]; then
  echo "🔗 Integracja n8n:"
  echo "   n8n może wywoływać Postiz API: http://postiz:5000/api"
  echo "   (kontenery są w wspólnej sieci: $SHARED_NETWORK)"
fi)

⚠️  Następne kroki:
   1. Otwórz: https://${DOMAIN}
   2. Zarejestruj się / zaloguj
   $([ "$DISABLE_REGISTRATION" = "false" ] && echo "3. WAŻNE: Wyłącz rejestrację (DISABLE_REGISTRATION=true w postiz.env)")
   3. Skonfiguruj integracje (LinkedIn, X, Instagram, itp.)
   4. $(echo "Dla LinkedIn: Rozważ CloudFlare R2 storage (fix 403 error)")

📚 Dokumentacja:
   - Postiz: https://docs.postiz.com/
   - Mikrus.us: https://wiki.mikr.us/

💾 Backup credentials:
   cp ${INSTALL_DIR}/postiz.env ~/postiz-backup-$(date +%Y%m%d).env

EOF

log "Gotowe! Możesz teraz korzystać z Postiz 🎉"
