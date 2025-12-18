# Quick Start - Postiz na Mikrus.us

## 🚀 Najszybsza instalacja (2 minuty)

### Wariant 1: Bez LinkedIn/Instagram

```bash
# Zaloguj się na serwer
ssh -p 10115 root@antoni115.mikrus.xyz

# Pobierz skrypt
wget https://raw.githubusercontent.com/.../postiz_install_interactive.sh
chmod +x postiz_install_interactive.sh

# Uruchom
sudo ./postiz_install_interactive.sh

# Odpowiadaj na pytania (Enter = domyślna wartość)
```

**✅ Gotowe!** Otwórz: `https://[NAZWA_SERWERA]-[PORT].wykr.es`

---

### Wariant 2: Z LinkedIn/Instagram (wymagany R2)

**Krok 1: Przygotuj CloudFlare R2** (5 minut)

1. Otwórz: https://dash.cloudflare.com/
2. **R2 Object Storage** → **Create bucket**
   - Nazwa: `postiz-media`
   - Region: Automatic
3. **Manage R2 API Tokens** → **Create API token**
   - Permissions: Object Read & Write
   - Apply to: **ALL buckets** (ważne!)
4. **Zapisz credentials** (tylko raz!):
   - Access Key ID
   - Secret Access Key
5. **Znajdź:**
   - Account ID (prawy górny róg w R2)
   - Bucket URL (bucket → Settings → S3 API)

**Krok 2: Zainstaluj Postiz**

```bash
# Zaloguj się na serwer
ssh -p 10115 root@antoni115.mikrus.xyz

# Pobierz skrypt
wget https://raw.githubusercontent.com/.../postiz_install_with_r2.sh
chmod +x postiz_install_with_r2.sh

# Uruchom
sudo ./postiz_install_with_r2.sh

# Wprowadź credentials gdy zapyta
```

**Krok 3: Skonfiguruj CORS** (1 minuta)

1. CloudFlare → R2 → `postiz-media` → **Settings**
2. **CORS Policy** → **Edit**
3. Wklej (zamień `your-domain.com` na swoją domenę):

```json
[
  {
    "AllowedOrigins": ["https://antoni115-30115.wykr.es"],
    "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag", "Content-Length"],
    "MaxAgeSeconds": 3600
  }
]
```

4. **Save**

**✅ Gotowe!** LinkedIn integration będzie działać bez 403 error!

---

## 📋 Wymagania minimalne

- VPS z Dockerem (Mikrus.us, DigitalOcean, Hetzner)
- 384MB RAM (Mikrus 1.0 wystarczy)
- 1 wolny port (20000-65535)
- Subdomena wykr.es lub własna domena

---

## 🐛 Szybkie rozwiązywanie problemów

### Postiz nie odpowiada
```bash
docker logs postiz --tail 50
docker compose -f /srv/postiz/docker-compose.yml restart
```

### LinkedIn zwraca "Could not add provider"
→ Użyj `postiz_install_with_r2.sh` zamiast wersji podstawowej
→ Sprawdź CORS w CloudFlare R2

### Port zajęty
```bash
ss -tulpn | grep :30115  # sprawdź co używa portu
```

Zmień port w `docker-compose.yml`:
```yaml
ports:
  - "30116:5000"  # zmień 30115 na 30116
```

Restart:
```bash
cd /srv/postiz
docker compose down && docker compose up -d
```

---

## 📚 Pełna dokumentacja

Zobacz: [README.md](README.md)

---

**Potrzebujesz pomocy?**
- Mikrus.us: [Facebook](https://mikr.us/facebook) | [Discord](https://mikr.us/discord)
- Postiz: [GitHub Issues](https://github.com/gitroomhq/postiz-app/issues)
