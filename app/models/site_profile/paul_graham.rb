class SiteProfile::PaulGraham < SiteProfile
  host "paulgraham.com"
  author static: "Paul Graham"

  archive_container css: "body > table > tbody > tr > td:nth-child(3) > table:nth-child(6)",
                   fallback_css: "html body table tbody tr td table"
  allowed_external_domains %w[turbifycdn.com]
end
