require 'spec_helper_acceptance'

describe 'yum_arch example from PUP-1364', :if => (fact('osfamily') == 'RedHat' && (fact('operatingsystemmajrelease') == '6')),
  :if => (Gem::Version.new(fact('puppetversion','-p')) < Gem::Version.new('4.5.0')) do

  before(:each) do
    # Make sure package already removed
    shell("yum remove -y firefox*", :acceptable_exit_codes => [0,1,2])
  end

  it 'should run successfully' do
    pp = <<-EOS
    package{ 'firefox.x86_64':
      ensure   => '45.2.0-1.el6.centos',
      provider => yum_arch,
    }

    package{ 'firefox.i686':
      ensure   => '45.2.0-1.el6.centos',
      provider => yum_arch,
    }
    EOS

    apply_manifest(pp, :debug => true, :catch_failures => true) do |r|
      expect(r.stdout).to match(/Detected Arch argument in package! - Moving arch to end of version string/)
    end
    apply_manifest(pp, :catch_changes => true)
  end
end
