module ReleaseSecurity
  def self.private_path?(path)
    parts = path.split("/")
    basename = parts.last().to_s()

    environment = basename == ".env" || (basename.start_with?(".env.") && basename != ".env.example")
    key = basename.match?(/\.(?:key(?:[.~_-].*)?|pem|p12|pfx)\z/i) || basename.match?(/\Aid_(?:rsa|dsa|ecdsa|ed25519)(?:\..*)?\z/)
    backup = basename.end_with?(".bak")
    deployment_secret = path.match?(%r{\A\.kamal/secrets(?:[./_-].*)?\z})
    plaintext_credentials = path.match?(%r{\Aconfig/(?:credentials|secrets)(?:/[^/]+)?\.ya?ml\z})
    runtime_data = [ "log", "tmp", "storage" ].include?(parts.first()) && basename != ".keep"

    environment || key || backup || deployment_secret || plaintext_credentials || runtime_data
  end
end
