require 'spec_helper_acceptance'

describe 'yum_arch example from PUP-1364', :unless => UNSUPPORTED_PLATFORMS.include?(fact('osfamily')) do
  it 'should run successfully' do
    pp = <<-EOS
    package{ "firefox.x86_64":
      ensure => "38.0.1-1.el6.centos",
      provider => yum_arch,
    }

    package{ "firefox.i686":
      ensure => "38.0.1-1.el6.centos",
      provider => yum_arch,
    }
    EOS

    apply_manifest(pp, :debug => true, :catch_failures => true)
    apply_manifest(pp, :catch_changes => true)
  end
end
