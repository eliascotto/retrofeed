class SiteProfile::SimonWillison < SiteProfile
  host     "simonwillison.net"
  author   static: "Simon Willison"

  detector ArchivePageDetector::SimonWillisonDetector
end
