# Defense-in-depth: even if a sanitizer bug or new attack vector slips raw HTML
# past MarkdownHelper#sanitize_article_html, the browser refuses to execute it.
#
# Notes on the directives chosen:
# - script-src :self only; no 'unsafe-inline'. Inline scripts (importmap, the
#   theme bootstrap in shared/_head) carry the per-request nonce via
#   `javascript_tag` / `javascript_importmap_tags`.
# - style-src allows 'unsafe-inline' because Tailwind/DaisyUI/Turbo inject
#   inline styles. Acceptable: inline CSS cannot execute JS; the article-body
#   sanitizer already strips `style` attributes from untrusted markup.
# - img-src allows https + data: so external blog images render normally.
# - frame-ancestors 'none' prevents clickjacking of the reader.
#
# To debug a policy violation without breaking the app, flip the last line to
# `config.content_security_policy_report_only = true`.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src      :self
    policy.font_src         :self, :data
    policy.img_src          :self, :data, :https
    policy.object_src       :none
    policy.script_src       :self
    policy.style_src        :self, :unsafe_inline
    policy.connect_src      :self
    policy.frame_ancestors  :none
    policy.base_uri         :self
    policy.form_action      :self
  end

  # Nonces are stable per-request, unguessable, and attached automatically to
  # script/style tags emitted by Rails' tag helpers (csp_meta_tag exposes them
  # to the browser).
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto       = true
end
