# frozen_string_literal: true

Pod::Spec.new do |s|
  s.name = 'CapacitorTwilioVoice'
  s.version = '0.0.1'
  s.summary = 'Capacitor twilio voice plugin'
  s.license = 'MIT'
  s.homepage = 'https://github.com/werecover/capacitor-twilio-voice'
  s.author = 'Werecover'
  s.source = { git: 'https://github.com/werecover/capacitor-twilio-voice', tag: s.version.to_s }
  s.source_files = 'ios/Plugin/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target = '11.0'
  s.dependency 'Capacitor'
  s.dependency 'TwilioVoice', '~> 5.1.1'
end
