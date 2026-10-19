# Release security

## Checks before publishing

Install Gitleaks 8.30.1 or newer, then run:

```bash
bin/scan-secrets --history
bin/rails test
bin/rails test:system
```

The secret check rejects private filenames in the Git index and all locally
available Git history. It scans tracked release files with Gitleaks, including
explicit rules for bare Rails encryption keys and unencrypted signing secrets.
Ignored environment files are deliberately excluded from the release-file scan.
CI checks the complete fetched history on each change.

Publish a verified Git archive or a checked container image. Sharing the whole
working directory can include credentials, logs, database files, and caches that
Git excludes. Keep local recovery bundles outside the project and out of release
archives.

## Rails credentials

Development uses `config/credentials.yml.enc` with the ignored `config/master.key`.
Production uses `config/credentials/production.yml.enc` with the ignored
`config/credentials/production.key`. Store only encrypted files in Git.

To manage production credentials:

```bash
bin/rails credentials:edit --environment production
```

Set `RAILS_MASTER_KEY` in the private production environment to the matching
production key. Keep production keys in a password manager or secret store.
Never reuse a development key for production, commit a key backup, or print
decrypted credentials in CI. A new signing secret invalidates sessions and
signed confirmation/password-reset links that used the previous secret.

## Deployment settings

Copy `.env.example` to the ignored `.env.production`, then supply real server,
registry, and mail settings privately. Use `bin/deploy` so environment values are
loaded before Kamal reads `config/deploy.yml`. Generated `.kamal/secrets` files
have owner-only permissions. Do not run deployment commands just to check a
release archive.

## After a history cleanup

Existing clones, forks, old archives, and images may retain removed data.
Retire exposed credentials even after removing their files. Use a fresh clone
after rewritten history is pushed; merging or pushing an old branch can restore
the removed history.

GitHub pull-request refs and cached commit views are not writable branch refs.
After rewriting branches and tags, inspect retained pull-request history and
contact GitHub Support for sensitive-data removal where necessary. Include the
affected pull-request numbers and original commits, never the secret values.
Keep the repository private until retention has been resolved.

Before any future deployment, revoke and replace registry and email-provider
tokens if an earlier archive or image might have contained them. Updating a local
environment file does not revoke an issued provider token. Replace credentials
on any previously used database server as well as in deployment configuration.
