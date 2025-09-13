# Postiz VPS Bootstrap

This repository contains:

- `install-postiz.sh` — one-shot installer that installs Docker + Docker Compose and deploys Postiz using the included defaults.
- `docker-compose.yml` — the exact default stack used by the installer.
- `setup-postiz.sh` — interactive wizard to generate JWT, choose and fill selected social API keys, write `docker-compose.yml`, and deploy.

## One-liner (run on a fresh VPS)

If you host `install-postiz.sh` as a GitHub Gist (Raw URL) you can run:

```bash
curl -sSL YOUR_RAW_GIST_URL | bash
```

This will:

- Install Docker and the Docker Compose plugin.
- Write `docker-compose.yml` with the default configuration.
- Start the stack with `docker compose up -d`.

Open `http://localhost:5000` (or replace with your server's IP/hostname if accessing remotely).

## Manual usage

- Ensure Docker and Docker Compose are installed.
- From this directory, run:

```bash
docker compose up -d
```

## Security note

- The default `JWT_SECRET` is a placeholder. For production, set a unique, strong value.
- To change any settings, edit `docker-compose.yml` and re-run `docker compose up -d`.

---

## Interactive setup (recommended for custom config)

Use `setup-postiz.sh` to step through configuration:

```bash
./setup-postiz.sh
```

What it does:

- Installs Docker and Docker Compose if missing.
- Lets you generate a random `JWT_SECRET` or paste your own.
- Allows selectively filling any of the social API keys (YouTube, X/Twitter, Threads, Telegram, Slack, Reddit, Pinterest, Mastodon, LinkedIn, Facebook, Discord, Instagram).
- Shows a preview of the resulting `docker-compose.yml`.
- Writes `docker-compose.yml` and starts containers when you choose Deploy.

Controls in the wizard:

- Main menu: choose between JWT setup, social keys setup, preview, and deploy.
- Social keys menu:
  - Choose a single key number to edit just that key.
  - Choose `a` to edit multiple keys at once using comma-separated numbers.
  - Choose `c` to clear all social keys.
  - Choose `b` to go back to the main menu.

### One-liner to run the wizard from a Raw URL (optional)

If you host `setup-postiz.sh` as a GitHub Gist (Raw URL), you can run:

```bash
curl -sSL YOUR_RAW_GIST_URL | bash
```

Replace `YOUR_RAW_GIST_URL` with the Raw link to `setup-postiz.sh`.

### Applying changes later

To edit variables later, modify `docker-compose.yml` and recreate containers:

```bash
docker compose up -d --force-recreate
```

Volumes preserve your data across restarts (`postgres-volume`, `postiz-redis-data`, `postiz-config`, `postiz-uploads`).
