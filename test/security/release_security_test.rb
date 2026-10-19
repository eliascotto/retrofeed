require "minitest/autorun"
require "open3"
require_relative "../../lib/release_security"

class ReleaseSecurityTest < Minitest::Test
  def test_rejects_private_files_at_release_boundaries
    paths = [
      "config/master.key", "config/master.key.bak", "config/master.key.old",
      "config/credentials/production.key", "config/credentials/production.key.backup",
      "config/credentials.yml.enc.bak", "config/credentials/production.yml",
      "config/credentials.yml", "config/secrets.yml", "keys/deploy.pem",
      ".env", ".env.production", "tools/scraper/.env.local", ".env.production.backup",
      ".kamal/secrets", ".kamal/secrets.bak", "keys/id_ed25519",
      "log/development.log", "tmp/cache/data", "storage/development.sqlite3"
    ]

    paths.each do |path|
      assert(ReleaseSecurity.private_path?(path), "Expected private path: #{path}")
    end
  end

  def test_allows_encrypted_credentials_and_public_examples
    paths = [
      "config/credentials.yml.enc", "config/credentials/production.yml.enc",
      ".env.example", "tools/scraper/.env.example", ".kamal/hooks/pre-connect",
      "config/storage.yml", "log/.keep", "tmp/pids/.keep", "storage/.keep"
    ]

    paths.each do |path|
      refute(ReleaseSecurity.private_path?(path), "Expected public path: #{path}")
    end
  end

  def test_gitignore_protects_nested_environments_and_key_backups
    paths = [
      ".env.production", "tools/scraper/.env.staging", "config/master.key.bak",
      "config/master.key~", "config/credentials/production.key.backup", "keys/deploy.pem"
    ]

    paths.each do |path|
      _, status = Open3.capture2("git", "check-ignore", "--no-index", path)
      assert(status.success?(), "Git must ignore #{path}")
    end

    _, status = Open3.capture2("git", "check-ignore", "--no-index", ".env.example")
    refute(status.success?(), "The public environment example must remain available")
  end
end
