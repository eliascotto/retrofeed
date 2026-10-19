class SiteProfile::Antirez < SiteProfile
  host "antirez.com"
  author static: "Salvatore Sanfilippo"

  date css: "span.info",
       # Robust regex for "X time ago" or "just now"
       regex: /(\d+\s+(?:second|minute|hour|day|week|month|year)s?\s+ago|just now)/,
       capture: 1,
       transform: :relative_date
end
