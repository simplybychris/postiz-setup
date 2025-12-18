#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

DEFAULT_INSTALL_DIR="/srv/postiz"
DEFAULT_HOST_PORT="30115"
DEFAULT_NETWORK="automation-net"
DEFAULT_CONTAINER_POSTIZ="postiz"
DEFAULT_CONTAINER_POSTGRES="postiz-postgres"
DEFAULT_CONTAINER_REDIS="postiz-redis"

usage() {
  cat <<'EOF'
Instaluje Postiz (postiz-app) na Mikr.us przez Docker Compose.

Użycie:
  sudo ./scripts/postiz_install.sh

Opcje:
  --dir <path>              Katalog instalacji (domyślnie: /srv/postiz)
  --port <host_port>        Port na hoście (domyślnie: 30115)
  --domain <fqdn>           Domena (np. postiz.example.com) - bez protokołu
  --scheme <http|https>     Protokół dla MAIN_URL/FRONTEND_URL (domyślnie: https)
  --network <name>          Wspólna sieć Dockera (domyślnie: automation-net)
  --n8n-container <name>    (Opcjonalnie) Nazwa kontenera n8n do podłączenia do sieci
  --with-spotlight          Dodaje opcjonalny kontener sentry/spotlight (domyślnie: wyłączone)
  --force                   Nadpisuje istniejące pliki compose/env
  --remove                  Zatrzymuje i usuwa stack Postiz (opcjonalnie z wolumenami)
  --purge-volumes           Użyj z --remove: usuwa też wolumeny danych
  -h, --help                Pomoc

Uwagi Mikr.us:
  - Na IPv4 masz tylko przekierowane porty (zwykle 20115 i 30115).
  - Usługi wystawiaj na portach 20000+/30000+ oraz przez Cloudflare/wykr.es.
EOF
}

log() { printf '%s\n' "[$SCRIPT_NAME] $*"; }
warn() { printf '%s\n' "[$SCRIPT_NAME] WARN: $*" >&2; }
die() { printf '%s\n' "[$SCRIPT_NAME] ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Brak polecenia: $1"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Uruchom jako root (np. sudo $0)"
  fi
}

read_non_empty() {
  local prompt="$1"
  local default="${2:-}"
  local value=""

  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "$prompt [$default]: " value || true
      value="${value:-$default}"
    else
      read -r -p "$prompt: " value || true
    fi
    value="$(printf '%s' "$value" | xargs)"
    [[ -n "$value" ]] && { printf '%s' "$value"; return 0; }
    warn "Wartość nie może być pusta."
  done
}

read_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local ans=""

  while true; do
    case "$default" in
      y|Y) read -r -p "$prompt [Y/n]: " ans || true ;;
      n|N) read -r -p "$prompt [y/N]: " ans || true ;;
      *) die "Nieprawidłowy default dla yes/no: $default" ;;
    esac

    ans="$(printf '%s' "$ans" | xargs)"
    if [[ -z "$ans" ]]; then
      ans="$default"
    fi

    case "$ans" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) warn "Odpowiedz: y albo n." ;;
    esac
  done
}

gen_secret() {
  local length="${1:-48}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -d '\n' | tr '+/' 'ab' | cut -c1-"$length"
    return 0
  fi
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
    return 0
  fi
  die "Brak docker compose (docker compose / docker-compose)."
}

install_dir="$DEFAULT_INSTALL_DIR"
host_port="$DEFAULT_HOST_PORT"
domain=""
scheme="https"
shared_network="$DEFAULT_NETWORK"
n8n_container=""
with_spotlight="false"
force="false"
remove="false"
purge_volumes="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) install_dir="${2:-}"; shift 2 ;;
    --port) host_port="${2:-}"; shift 2 ;;
    --domain) domain="${2:-}"; shift 2 ;;
    --scheme) scheme="${2:-}"; shift 2 ;;
    --network) shared_network="${2:-}"; shift 2 ;;
    --n8n-container) n8n_container="${2:-}"; shift 2 ;;
    --with-spotlight) with_spotlight="true"; shift ;;
    --force) force="true"; shift ;;
    --remove) remove="true"; shift ;;
    --purge-volumes) purge_volumes="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Nieznana opcja: $1 (użyj --help)" ;;
  esac
done

require_root
need_cmd docker
need_cmd mkdir
need_cmd chmod
need_cmd chown
need_cmd awk

if [[ "$scheme" != "http" && "$scheme" != "https" ]]; then
  die "scheme musi być http albo https"
fi

if [[ "$remove" == "true" ]]; then
  compose_file="$install_dir/docker-compose.yml"
  if [[ ! -f "$compose_file" ]]; then
    die "Brak $compose_file; nic do usunięcia."
  fi
  log "Zatrzymuję Postiz w $install_dir"
  if [[ "$purge_volumes" == "true" ]]; then
    (cd "$install_dir" && docker_compose down -v)
  else
    (cd "$install_dir" && docker_compose down)
  fi
  log "Gotowe."
  exit 0
fi

if [[ -z "$domain" ]]; then
  domain="$(read_non_empty "Podaj domenę Postiz (FQDN, bez https://)" "")"
fi
domain="${domain#http://}"
domain="${domain#https://}"

if ! [[ "$host_port" =~ ^[0-9]+$ ]] || (( host_port < 1 || host_port > 65535 )); then
  die "Nieprawidłowy port: $host_port"
fi

main_url="${scheme}://${domain}"
frontend_url="${scheme}://${domain}"
# Postiz (nginx) redirects "/api" -> "/api/" with an absolute Location that includes internal port 5000.
# Using a trailing slash here avoids clients requesting the bare "/api" path.
backend_url="${scheme}://${domain}/api/"

log "Docelowy URL: $main_url"
log "Port na hoście: $host_port -> 5000 (container)"

if command -v ss >/dev/null 2>&1; then
  if ss -tulpn 2>/dev/null | awk '{print $5}' | grep -qE "[:\\[]${host_port}\\]?$"; then
    warn "Port $host_port wygląda na zajęty. Jeśli to błąd, pomiń; inaczej wybierz inny port."
    if ! read_yes_no "Kontynuować mimo to?" "n"; then
      die "Przerwano."
    fi
  fi
fi

if [[ -z "$n8n_container" ]]; then
  if read_yes_no "Czy chcesz podłączyć istniejący kontener n8n do wspólnej sieci ($shared_network)?" "y"; then
    n8n_container="$(read_non_empty "Podaj nazwę kontenera n8n (docker ps --format '{{.Names}}')" "")"
  fi
fi

postgres_user="postiz-user"
postgres_db="postiz-db-local"
postgres_password="$(gen_secret 32)"
jwt_secret="$(gen_secret 64)"

if read_yes_no "Ustawić własne hasło do Postgresa zamiast generować?" "n"; then
  postgres_password="$(read_non_empty "POSTGRES_PASSWORD" "")"
fi
if read_yes_no "Ustawić własny JWT_SECRET zamiast generować?" "n"; then
  jwt_secret="$(read_non_empty "JWT_SECRET" "")"
fi

disable_registration="false"
if read_yes_no "Wyłączyć rejestrację nowych użytkowników (DISABLE_REGISTRATION=true)?" "y"; then
  disable_registration="true"
fi

install_dir="$(printf '%s' "$install_dir" | sed 's:/*$::')"
compose_file="$install_dir/docker-compose.yml"
env_file="$install_dir/postiz.env"

mkdir -p "$install_dir"
chmod 700 "$install_dir"

if [[ -f "$compose_file" || -f "$env_file" ]]; then
  if [[ "$force" != "true" ]]; then
    die "Pliki już istnieją w $install_dir. Użyj --force aby nadpisać."
  fi
  warn "Nadpisuję pliki w $install_dir (--force)."
fi

database_url="postgresql://${postgres_user}:${postgres_password}@${DEFAULT_CONTAINER_POSTGRES}:5432/${postgres_db}"
redis_url="redis://${DEFAULT_CONTAINER_REDIS}:6379"

cat >"$env_file" <<EOF
# Generated by $SCRIPT_NAME on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# === Required Settings
MAIN_URL=${main_url}
FRONTEND_URL=${frontend_url}
NEXT_PUBLIC_BACKEND_URL=${backend_url}
JWT_SECRET=${jwt_secret}
DATABASE_URL=${database_url}
REDIS_URL=${redis_url}
BACKEND_INTERNAL_URL=http://localhost:3000
IS_GENERAL=true
DISABLE_REGISTRATION=${disable_registration}

# === Storage Settings
STORAGE_PROVIDER=local
UPLOAD_DIRECTORY=/uploads
NEXT_PUBLIC_UPLOAD_DIRECTORY=/uploads

# === Postgres settings (used by the postgres container)
POSTGRES_PASSWORD=${postgres_password}
POSTGRES_USER=${postgres_user}
POSTGRES_DB=${postgres_db}

# === Optional Social Media API Settings (fill later)
X_API_KEY=
X_API_SECRET=
LINKEDIN_CLIENT_ID=
LINKEDIN_CLIENT_SECRET=
REDDIT_CLIENT_ID=
REDDIT_CLIENT_SECRET=
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
EOF

chmod 600 "$env_file"

cat >"$compose_file" <<EOF
services:
  postiz:
    image: ghcr.io/gitroomhq/postiz-app:latest
    container_name: ${DEFAULT_CONTAINER_POSTIZ}
    restart: always
    env_file:
      - ./postiz.env
    volumes:
      - postiz-config:/config/
      - postiz-uploads:/uploads/
    ports:
      - "${host_port}:5000"
    networks:
      - ${shared_network}
    depends_on:
      postiz-postgres:
        condition: service_healthy
      postiz-redis:
        condition: service_healthy

  postiz-postgres:
    image: postgres:17-alpine
    container_name: ${DEFAULT_CONTAINER_POSTGRES}
    restart: always
    env_file:
      - ./postiz.env
    volumes:
      - postgres-volume:/var/lib/postgresql/data
    networks:
      - ${shared_network}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${postgres_user} -d ${postgres_db}"]
      interval: 10s
      timeout: 3s
      retries: 5

  postiz-redis:
    image: redis:7.2
    container_name: ${DEFAULT_CONTAINER_REDIS}
    restart: always
    volumes:
      - postiz-redis-data:/data
    networks:
      - ${shared_network}
    healthcheck:
      test: ["CMD-SHELL", "redis-cli ping | grep -q PONG"]
      interval: 10s
      timeout: 3s
      retries: 5
EOF

if [[ "$with_spotlight" == "true" ]]; then
  cat >>"$compose_file" <<EOF

  spotlight:
    image: ghcr.io/getsentry/spotlight:latest
    container_name: spotlight
    restart: always
    ports:
      - "8969:8969"
    networks:
      - ${shared_network}
EOF
fi

cat >>"$compose_file" <<EOF

volumes:
  postgres-volume:
  postiz-redis-data:
  postiz-config:
  postiz-uploads:

networks:
  ${shared_network}:
    external: true
EOF

chmod 600 "$compose_file"

if ! docker network inspect "$shared_network" >/dev/null 2>&1; then
  log "Tworzę sieć Docker: $shared_network"
  docker network create "$shared_network" >/dev/null
else
  log "Sieć Docker już istnieje: $shared_network"
fi

log "Uruchamiam Postiz (docker compose up -d)"
(cd "$install_dir" && docker_compose up -d)

if [[ -n "$n8n_container" ]]; then
  if docker inspect "$n8n_container" >/dev/null 2>&1; then
    n8n_id="$(docker inspect -f '{{.Id}}' "$n8n_container" 2>/dev/null || true)"
    if [[ -n "$n8n_id" ]] && docker network inspect "$shared_network" --format '{{json .Containers}}' | grep -q "$n8n_id"; then
      log "Kontener n8n już jest w sieci $shared_network: $n8n_container"
    else
      log "Podłączam kontener n8n do sieci $shared_network: $n8n_container"
      docker network connect "$shared_network" "$n8n_container" || warn "Nie udało się podłączyć $n8n_container (możesz zrobić to ręcznie)."
    fi
  else
    warn "Nie znaleziono kontenera n8n: $n8n_container (pomiń)."
  fi
fi

log "Status:"
(cd "$install_dir" && docker_compose ps)

cat <<EOF

Gotowe. Następne kroki:
  1) Wystaw domenę w Cloudflare/wykr.es na port ${host_port} (IPv6-first na Mikr.us).
  2) Sprawdź logi: (cd ${install_dir} && docker compose logs -f postiz)
  3) Integracja n8n -> Postiz (z tej samej sieci): http://${DEFAULT_CONTAINER_POSTIZ}:5000/api

Pliki:
  - ${compose_file}
  - ${env_file}

Usuwanie:
  - $0 --remove --dir ${install_dir}
  - $0 --remove --purge-volumes --dir ${install_dir}
EOF
