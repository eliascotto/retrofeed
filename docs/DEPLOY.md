# Deployment Guide

This document covers deploying Retrofeed to production using [Kamal](https://kamal-deploy.org/).

## Prerequisites

- Docker installed locally
- SSH access to the production server
- GitHub Container Registry (ghcr.io) access token

## Environment Variables

### Single Source of Truth

All environment variables are managed in `.env*` files at the project root. These files are gitignored for security.

- `.env.production` - Primary file for production secrets (recommended)
- `.env` - Fallback if `.env.production` doesn't exist

The pre-deploy hook automatically syncs these to `.kamal/secrets` before each deployment.

### Required Variables

These must be present in your env file for deployment to succeed:

| Variable | Description |
|----------|-------------|
| `KAMAL_REGISTRY_PASSWORD` | GitHub Container Registry personal access token |
| `RAILS_MASTER_KEY` | Production Rails key (from `config/credentials/production.key`) |
| `KAMAL_IMAGE` | Container image, such as `ghcr.io/your-account/retrofeed` |
| `KAMAL_REGISTRY_USERNAME` | Container registry account |
| `DEPLOY_SERVER` | Deployment server address |
| `DEPLOY_SSH_KEY` | Local path to the deployment SSH private key |
| `APP_HOST` | Public hostname for the application |
| `DATABASE_URL` | PostgreSQL connection URL for production |
| `POSTGRES_USER` | PostgreSQL username |
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `POSTGRES_DB` | PostgreSQL database name |

### Optional Variables

All other variables in your env file are automatically included. Common ones:

| Variable | Description | Default |
|----------|-------------|---------|
| `RESEND_API_KEY` | Resend API key for sending emails | (emails disabled) |
| `MAILER_FROM_EMAIL` | From address for emails | `noreply@retrofeed.app` |
| `WEBSITE_ARCHIVE_INTERVAL` | Interval before re-crawling archives | `14 days` |
| `WEBSITE_ARCHIVE_MIN_INTERVAL` | Minimum interval between archive crawls (floor: 10 minutes) | `60 minutes` |
| `ARTICLE_CONTENT_INTERVAL` | Interval before re-fetching article content | `60 days` |
| `ARTICLE_CONTENT_MIN_INTERVAL` | Minimum interval between content fetches (floor: 10 minutes) | `30 minutes` |

### Example `.env.production`

```bash
# Kamal Registry
KAMAL_IMAGE=ghcr.io/your-account/retrofeed
KAMAL_REGISTRY_USERNAME=your-account
KAMAL_REGISTRY_PASSWORD=ghp_xxxxxxxxxxxxxxxxxxxx

# Server
DEPLOY_SERVER=192.0.2.1
DEPLOY_SSH_KEY=~/.ssh/your-deployment-key

# Rails
RAILS_MASTER_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# PostgreSQL
POSTGRES_USER=psqluser
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_DB=db_prod
DATABASE_URL=postgresql://psqluser:your_secure_password_here@retrofeed-db:5432/db_prod

# Email (Resend)
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxx
MAILER_FROM_EMAIL=noreply@retrofeed.app
APP_HOST=reader.example.com

# Content refresh intervals (optional)
WEBSITE_ARCHIVE_INTERVAL=14 days
WEBSITE_ARCHIVE_MIN_INTERVAL=60 minutes
ARTICLE_CONTENT_INTERVAL=60 days
ARTICLE_CONTENT_MIN_INTERVAL=30 minutes
```

## How Environment Sync Works

The `.kamal/hooks/pre-connect` script syncs environment variables to `.kamal/secrets`:

1. Looks for `.env.production` (primary) or `.env` (fallback)
2. Parses all environment variables from the file
3. Validates that required secrets are present
4. Writes all variables to `.kamal/secrets`
5. Kamal reads from `.kamal/secrets` and injects them into containers

**Important:** Kamal needs secrets at startup (before hooks run), so use `bin/deploy` instead of `bin/kamal deploy` directly. The wrapper script runs the sync before invoking Kamal.

### Adding New Variables

To add a new environment variable to production:

1. Add the variable to your `.env.production` (or `.env`) file
2. If needed by the Rails app, add it to `config/deploy.yml` under `env.secret`
3. If it's required for deployment, add it to `REQUIRED_SECRETS` in `.kamal/hooks/pre-deploy`

The pre-deploy hook automatically includes all variables from your env file, so step 3 is only needed if the variable is mandatory.

## Deploying

Use `bin/deploy` instead of `bin/kamal` directly. This wrapper script syncs environment variables before Kamal runs (Kamal needs secrets at startup, before hooks execute).

### First-time Setup

```bash
# Set up the server and deploy
bin/deploy setup
```

### Regular Deployments

```bash
# Deploy latest changes
bin/deploy
```

### Useful Commands

```bash
# View application logs
bin/kamal logs

# View database logs
bin/kamal accessory logs db

# Open Rails console on production
bin/kamal console

# Open shell on production
bin/kamal shell

# Open database console
bin/kamal dbc

# Rollback to previous version
bin/kamal rollback
```

Note: Commands that don't need secrets (like `logs`, `console`, `shell`) can use `bin/kamal` directly.

## Configuration Files

| File | Purpose |
|------|---------|
| `config/deploy.yml` | Kamal deployment configuration |
| `.kamal/secrets` | Generated secrets file (do not edit manually) |
| `.kamal/hooks/pre-connect` | Script that syncs env to secrets |
| `bin/deploy` | Wrapper script for deployment (use this instead of `bin/kamal`) |

## Troubleshooting

### Missing Environment Variables

If deployment fails with missing variables:

1. Check that your `.env.production` or `.env` file exists
2. Verify all required variables are present
3. Run the sync script manually to test: `.kamal/hooks/pre-connect`

### Email Not Sending

Ensure `RESEND_API_KEY` is set in your env file and listed in `config/deploy.yml` under `env.secret`.

### Database Connection Issues

Verify `DATABASE_URL` is correctly formatted and the PostgreSQL container is running:

```bash
bin/kamal accessory logs db
```
