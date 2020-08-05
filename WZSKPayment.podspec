Pod::Spec.new do |spec|

spec.name         = 'WZSKPayment'
spec.version      = '0.3.5'
spec.summary      = 'WZSKPayment内购购买组件.'

spec.description  = <<-DESC
苹果内购购买组件、钥匙串存储
DESC

spec.homepage     = 'https://github.com/WZLYiOS/WZSKPayment'
spec.license      = 'MIT'
spec.author       = { 'qixiang qiu' => '739140860@qq.com' }
spec.source       = { :git => 'https://github.com/WZLYiOS/WZSKPayment', :tag => spec.version.to_s }

spec.swift_version         = '5.0'
spec.ios.deployment_target = '9.0'
spec.requires_arc = true
spec.static_framework = true

spec.source_files = 'WZSKPayment/*/*.{h,m}'


end
