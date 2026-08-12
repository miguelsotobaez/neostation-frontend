#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'external_folder_access'
  s.version          = '0.0.1'
  s.summary          = 'iOS folder picker with persisted security-scoped bookmark access.'
  s.description      = <<-DESC
Lets NeoStation pick a folder exposed by another app (e.g. RetroArch) via
the system document picker, and keeps access to it valid across app
relaunches using a security-scoped bookmark, so ROMs can be scanned in
place without copying them into NeoStation's own sandbox.
                       DESC
  s.homepage         = 'https://neostation.dev'
  s.license          = { :type => 'MIT' }
  s.author           = { 'NeoStation' => 'contact@neostation.dev' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks = 'Security'

  s.platform = :ios, '14.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
