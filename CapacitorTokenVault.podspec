require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'CapacitorTokenVault'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = 'https://gitlab.mychili.id/mychili/frontend/mobile/capacitor-token-vault'
  s.author = 'Mobile / frontend'
  s.source = { :git => 'https://gitlab.mychili.id/mychili/frontend/mobile/capacitor-token-vault.git', :tag => s.version.to_s }
  s.source_files = 'ios/Sources/TokenVaultPlugin/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.9'
end
