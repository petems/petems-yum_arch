require 'spec_helper_acceptance'

describe 'nothing installed to ensure latest works', :unless => UNSUPPORTED_PLATFORMS.include?(fact('osfamily')),
  :if => (Gem::Version.new(fact('puppetversion','-p')) < Gem::Version.new('4.5.0')) do
  before(:each) do
    # Make sure package already removed
    shell("yum remove -y firefox*", :acceptable_exit_codes => [0,1,2])
  end

  it 'should run successfully' do
    pp = <<-EOS
    package{ 'firefox.x86_64':
      ensure   => 'latest',
      provider => yum_arch,
    }

    package{ 'firefox.i686':
      ensure   => 'latest',
      provider => yum_arch,
    }
    EOS

    apply_manifest(pp, :debug => true, :catch_failures => true)
    apply_manifest(pp, :catch_changes => true)
  end
end
