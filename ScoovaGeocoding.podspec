Pod::Spec.new do |s|
  s.name             = 'ScoovaGeocoding'
  s.version          = '1.1.2'
  s.summary          = 'Geocoding geocoding — forward search, autocomplete, reverse, place lookup, structured search, batch.'

  s.description      = <<-DESC
    Geocoding geocoding — forward search, autocomplete, reverse, place lookup, structured search, batch.

    Pure Swift. Uses URLSession + async/await. Auto-detects
    `Bundle.main.bundleIdentifier` for the X-Ios-Bundle-Identifier
    key-restriction header. Locale-aware (`Accept-Language` + `?locale=`,
    default `en`).
  DESC

  s.homepage         = 'https://cloud.scoo-va.info'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'Scoova' => 'info@scoo-va.info' }
  s.source           = { :git => 'https://github.com/Scoova/scoova-geocoding-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target     = '15.0'
  s.osx.deployment_target     = '12.0'

  s.swift_versions   = ['5.9']
  s.source_files     = 'Sources/ScoovaGeocoding/**/*.swift'
end
