# Postiz Installer dla Mikrus.us

Zestaw skryptów instalacyjnych Postiz z integracją n8n dla serwerów Mikrus.us (i innych VPS z Dockerem).

## 🚀 Szybki start (One-liner)

```bash
wget https://raw.githubusercontent.com/simplybychris/postiz-setup/main/postiz-mikrus-installer/postiz_install_interactive.sh && chmod +x postiz_install_interactive.sh && sudo ./postiz_install_interactive.sh
```

Skrypt poprowadzi Cię krok po kroku przez instalację! ✨

## 📦 Trzy warianty instalacji

### 1. `postiz_install.sh` - Podstawowy (z flagami)

**Dla kogo:** Doświadczeni użytkownicy, automatyzacja, CI/CD

**Cechy:**
- Parametry przez flagi (`--domain`, `--port`, itp.)
- Wsparcie dla nieinteraktywnego trybu
- Domyślne wartości + możliwość nadpisania
- Pełna dokumentacja flag (`--help`)

**Użycie:**
```bash
sudo ./postiz_install.sh \
  --domain srv123-30123.wykr.es \
  --port 30123 \
  --network automation-net \
  --n8n-container n8n
```

---

### 2. `postiz_install_interactive.sh` - Interaktywny

**Dla kogo:** Początkujący użytkownicy, pierwsze uruchomienie, setup krok po kroku

**Cechy:**
- **Tylko prompty** - bez flag, bez argumentów
- Pytania po kolei o każdy parametr
- Domyślne wartości (Enter = akceptacja domyślnej)
- Automatyczna detekcja (nazwa serwera, istniejąca sieć, kontenery n8n)
- **Wybór obrazu Docker** - oryginalny lub lokalny/zmodyfikowany
- Walidacja portów i obrazów
- Przyjazne komunikaty i podpowiedzi

**Użycie:**
```bash
sudo ./postiz_install_interactive.sh
# Skrypt poprowadzi Cię krok po kroku
```

**Przykładowa sesja:**
```
[postiz_install_interactive.sh] === Postiz Interactive Installer v1.1 ===

Port na którym ma działać Postiz [30123]: ⏎
✓ Port: 30123

Domena/subdomena dla Postiz [srv123-30123.wykr.es]: ⏎
✓ Domena: srv123-30123.wykr.es

Katalog instalacji [/srv/postiz]: ⏎
✓ Katalog: /srv/postiz

Sieć Docker [automation-net]: ⏎
✓ Sieć: automation-net

Wykryto kontener n8n: n8n
Podłączyć n8n do wspólnej sieci automation-net? [Y/n]: y
✓ Integracja z n8n: n8n

Użyć lokalnego/zmodyfikowanego obrazu? [y/N]: n
✓ Używam oryginalnego obrazu: ghcr.io/gitroomhq/postiz-app:latest

Wyłączyć rejestrację nowych użytkowników? [Y/n]: y
✓ Rejestracja zostanie wyłączona

=== Podsumowanie konfiguracji ===
  Domena:              https://srv123-30123.wykr.es
  Port:                30123
  Obraz:               ghcr.io/gitroomhq/postiz-app:latest

Rozpocząć instalację? [Y/n]: y
```

---

### 3. `postiz_install_with_r2.sh` - Z CloudFlare R2

**Dla kogo:** Użytkownicy potrzebujący LinkedIn/Instagram integration

**Cechy:**
- Interaktywny setup jak w wersji 2
- **Dodatkowo**: Pyta o CloudFlare R2 credentials podczas instalacji
- Automatycznie konfiguruje `STORAGE_PROVIDER=cloudflare`
- Rozwiązuje problem LinkedIn avatar upload (403 error)

**Użycie:**
```bash
sudo ./postiz_install_with_r2.sh
# Skrypt poprosi o CloudFlare R2 credentials
```

**Wymaga przygotowania:**
1. Konto CloudFlare
2. R2 bucket (np. `postiz-media`)
3. API Token (Read & Write, ALL buckets)
4. Zapisane credentials:
   - Account ID
   - Access Key ID
   - Secret Access Key
   - Bucket URL

**Więcej o R2:** Zobacz [CloudFlare R2 Setup Guide](https://developers.cloudflare.com/r2/)

---

## 🎯 Który skrypt wybrać?

| Scenariusz | Skrypt |
|------------|--------|
| Pierwsza instalacja Postiz | `postiz_install_interactive.sh` |
| Automatyzacja/skrypt deployment | `postiz_install.sh` |
| Potrzebujesz LinkedIn/Instagram | `postiz_install_with_r2.sh` |
| Doświadczony admin, szybki setup | `postiz_install.sh` |
| Nie wiesz co wybrać | `postiz_install_interactive.sh` |

---

## 📋 Wymagania

### System
- VPS z Dockerem (Mikrus.us, DigitalOcean, Hetzner, itp.)
- Debian/Ubuntu (testowane na Debian 12)
- Root access (`sudo`)

### Porty (Mikrus.us)
- Port SSH: `10000+ID` (np. 10115)
- Port Postiz: `20000+ID` lub `30000+ID` (np. 30115)
- Port n8n (opcjonalnie): `20000+ID` (np. 20115)

### Domena
- Subdomena wykr.es (automatyczna): `srvNAME-PORT.wykr.es`
- Własna domena przez CloudFlare (zalecane dla produkcji)
- Darmowa subdomena z panelu Mikrus (byst.re, itp.)

---

## 🚀 Instalacja krok po kroku

### Wariant A: Interaktywny (zalecany dla początkujących)

```bash
# 1. Zaloguj się na serwer
ssh -p 10123 root@srv123.mikrus.xyz

# 2. Zainstaluj Docker (jeśli nie masz)
curl -fsSL https://get.docker.com | sh

# 3. Opcjonalnie: Zainstaluj n8n
# (jeśli chcesz integrację)
n8n_install  # komenda z NOOBS na Mikrus

# 4. Pobierz skrypt
wget https://raw.githubusercontent.com/simplybychris/postiz-setup/main/postiz-mikrus-installer/postiz_install_interactive.sh
chmod +x postiz_install_interactive.sh

# 5. Uruchom instalację
sudo ./postiz_install_interactive.sh

# 6. Odpowiadaj na pytania (Enter = domyślna wartość)
```

### Wariant B: Z argumentami (dla doświadczonych)

```bash
# 1-3. Jak wyżej

# 4. Pobierz skrypt
wget https://raw.githubusercontent.com/simplybychris/postiz-setup/main/postiz-mikrus-installer/postiz_install.sh
chmod +x postiz_install.sh

# 5. Uruchom z parametrami
sudo ./postiz_install.sh \
  --domain srv123-30123.wykr.es \
  --port 30123 \
  --network automation-net \
  --n8n-container n8n \
  --disable-registration
```

### Wariant C: Z CloudFlare R2 (dla LinkedIn/Instagram)

```bash
# 1. Przygotuj CloudFlare R2 bucket
# - https://dash.cloudflare.com/
# - R2 Object Storage → Create bucket
# - Create API Token (Read & Write, ALL buckets)
# - Zapisz: Account ID, Access Key, Secret Key, Bucket URL

# 2-3. Jak w wariancie A

# 4. Pobierz skrypt
wget https://raw.githubusercontent.com/TwojaOrg/postiz-mikrus-installer/main/postiz_install_with_r2.sh
chmod +x postiz_install_with_r2.sh

# 5. Uruchom
sudo ./postiz_install_with_r2.sh

# 6. Wprowadź credentials gdy skrypt zapyta
```

---

## 🔧 Co instalują skrypty?

Wszystkie trzy skrypty instalują:

### Kontenery Docker
- **postiz** - Główna aplikacja (port 5000 wewnętrzny)
- **postiz-postgres** - Baza danych PostgreSQL 17
- **postiz-redis** - Cache i kolejki Redis 7.2

### Volumeny Docker
- `postiz_postgres-volume` - Dane PostgreSQL
- `postiz_postiz-config` - Konfiguracja Postiz
- `postiz_postiz-redis-data` - Dane Redis
- `postiz_postiz-uploads` - Pliki uploadowane (tylko local storage)

### Sieć Docker
- `automation-net` (bridge, external)
- Wspólna sieć dla Postiz + n8n (jeśli wybrałeś integrację)

### Pliki konfiguracyjne
- `/srv/postiz/docker-compose.yml` - Definicja usług
- `/srv/postiz/postiz.env` - Zmienne środowiskowe (hasła, JWT, itp.)

### Generowane secrets
- Hasło PostgreSQL (32 znaki)
- JWT secret (64 znaki)
- Frontend URL, Backend URL

---

## 🌐 Dostęp do Postiz po instalacji

### Subdomena wykr.es (automatyczna)
```
https://srv123-30123.wykr.es
```
Format: `https://[NAZWA_SERWERA]-[PORT].wykr.es`

### Własna domena (przez CloudFlare)
```
https://postiz.twojadomena.pl
```
Wymaga konfiguracji CloudFlare (AAAA record + Proxy)

### Pierwszy login
1. Otwórz: `https://srv123-30123.wykr.es`
2. Przekieruje na: `/auth`
3. Zarejestruj się (jeśli nie wyłączyłeś rejestracji)
4. Lub zaloguj się (jeśli masz już konto)

---

## 🔐 Bezpieczeństwo

### Wyłączenie rejestracji (produkcja)
```bash
# W postiz.env dodaj:
DISABLE_REGISTRATION=true

# Restart:
cd /srv/postiz
docker compose down && docker compose up -d
```

### Hasła
- Generowane automatycznie (OpenSSL)
- Zapisane w `/srv/postiz/postiz.env`
- **Nigdy nie commituj postiz.env do Git!**

### Backup credentials
```bash
# Skopiuj plik env do bezpiecznego miejsca:
cp /srv/postiz/postiz.env ~/postiz-backup.env
chmod 600 ~/postiz-backup.env
```

---

## 🐛 Troubleshooting

### Postiz nie odpowiada
```bash
# Sprawdź logi:
docker logs postiz --tail 50

# Sprawdź czy kontenery działają:
docker ps | grep postiz

# Restart:
cd /srv/postiz
docker compose down && docker compose up -d
```

### Błąd CORS (LinkedIn/Instagram)
**Problem:** `No 'Access-Control-Allow-Origin' header`

**Rozwiązanie:**
1. Jeśli używasz R2: Zobacz `/docs/CLOUDFLARE_R2_CORS_FIX.md`
2. Jeśli local storage: Użyj `postiz_install_with_r2.sh` do migracji

### LinkedIn zwraca "Could not add provider"
**Problem:** 403 Forbidden przy pobieraniu avatara

**Rozwiązanie:**
- Zainstaluj ponownie używając `postiz_install_with_r2.sh`
- Lub migruj do R2: Zobacz `/docs/CLOUDFLARE_R2_SETUP.md`

### Port zajęty
```bash
# Sprawdź co używa portu:
ss -tulpn | grep :30123

# Zmień port w docker-compose.yml:
nano /srv/postiz/docker-compose.yml
# Zmień: "30123:5000" na "30124:5000"

# Restart:
docker compose down && docker compose up -d
```

---

## 🔄 Aktualizacja Postiz

### Automatyczna (Watchtower)
```bash
# Zainstaluj Watchtower (jeśli nie masz):
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower --interval 86400
```

### Ręczna
```bash
cd /srv/postiz
docker compose pull
docker compose down
docker compose up -d
```

---

## 🔗 Integracja z n8n

Jeśli wybrałeś integrację z n8n podczas instalacji:

### Dostęp z n8n do Postiz API
```
http://postiz:5000/api
```

### Przykład workflow n8n → Postiz
1. HTTP Request Node
2. URL: `http://postiz:5000/api/posts`
3. Method: POST
4. Headers: `Authorization: Bearer YOUR_API_KEY`

### Uzyskanie API Key z Postiz
1. Zaloguj się do Postiz
2. Settings → API Keys
3. Generate New Key
4. Skopiuj do n8n credentials

---

## 📚 Dodatkowe zasoby

### Dokumentacja
- [Postiz Official Docs](https://docs.postiz.com/)
- [Mikrus.us Wiki](https://wiki.mikr.us/)
- [CloudFlare R2 Docs](https://developers.cloudflare.com/r2/)

### GitHub
- [Postiz GitHub](https://github.com/gitroomhq/postiz-app)
- [Ten projekt](https://github.com/TwojaOrg/postiz-mikrus-installer)

### Wsparcie
- Mikrus.us: [Facebook](https://mikr.us/facebook) | [Discord](https://mikr.us/discord)
- Postiz: [GitHub Issues](https://github.com/gitroomhq/postiz-app/issues)

---

## 📄 Licencja

Skrypty instalacyjne: MIT License

Postiz: Licencja Postiz (sprawdź repozytorium upstream)

---

## 🤝 Contributing

Pull requesty mile widziane!

1. Fork projektu
2. Utwórz branch: `git checkout -b feature/amazing-feature`
3. Commit: `git commit -m 'Add amazing feature'`
4. Push: `git push origin feature/amazing-feature`
5. Otwórz Pull Request

---

**Pytania?** Otwórz issue na GitHub lub zapytaj na Mikrus.us Discord/Facebook.
