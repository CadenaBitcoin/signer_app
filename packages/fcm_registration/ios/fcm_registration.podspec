Pod::Spec.new do |s|
  s.name = 'fcm_registration'
  s.version = '0.1.0'
  s.summary = 'Registration-only Firebase Messaging FID bridge.'
  s.description = 'Exposes FCM register and registered-FID callbacks to Dart.'
  s.homepage = 'https://firebase.google.com/docs/cloud-messaging'
  s.license = { :type => 'MIT' }
  s.author = { 'Cadena' => 'https://cadenabitcoin.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'Firebase/Messaging', '12.18.0'
  s.platform = :ios, '15.5'
  s.swift_version = '5.0'
end
