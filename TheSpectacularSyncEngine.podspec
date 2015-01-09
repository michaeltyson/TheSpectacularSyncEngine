Pod::Spec.new do |s|
  s.name         = "TheSpectacularSyncEngine"
  s.version      = "1.0"
  s.summary      = "A standards-compliant, solid MIDI sync engine for iOS"
  s.homepage     = "http://thesplendidsyncengine.com"
  s.license      = 'zlib'
  s.author       = { "Michael Tyson" => "michael@atastypixel.com" }
  s.source       = { :git => "https://github.com/TheSpectacularSyncEngine/TheSpectacularSyncEngine.git", :tag => "1.0" }
  s.platform     = :ios, '6.0'
  s.source_files = 'TheSpectacularSyncEngine/**/*.{h,m,c}', 'Modules/*.{h,m,c}'
  s.frameworks = 'CoreMIDI'
  s.requires_arc = true
end
