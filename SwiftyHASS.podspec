Pod::Spec.new do |s|
  s.name             = 'SwiftyHASS'
  s.version          = '0.2.0'
  s.summary          = 'SwiftyHASS is a Framework for accessing Home Assistant for iOS.'

  s.description      = <<-DESC
    SwiftyHASS is a Framework that exposes the Home Assistant API for use within an iOS project.  Currently only supports retrieving and setting states on switches.
                       DESC

  s.homepage         = 'https://github.com/mikepm35/SwiftyHASS'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'mikepm35' => 'mike.p.moritz@gmail.com' }
  s.source           = { :git => 'https://github.com/mikepm35/SwiftyHASS.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'

  s.source_files = 'SwiftyHASS/Classes/**/*'
  
  s.dependency 'Alamofire', '~> 4.3'
end
