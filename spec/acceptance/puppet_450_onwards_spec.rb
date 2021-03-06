require 'spec_helper_acceptance'

describe 'raise error on Puppet 4.5.0', :if => (fact('osfamily') == 'RedHat' && (fact('operatingsystemmajrelease') == '6')),
  :if => (Gem::Version.new(fact('puppetversion','-p')) >= Gem::Version.new('4.5.0')) do
  before(:each) do
    # Make sure package already removed
    shell("yum remove -y firefox*", :acceptable_exit_codes => [0,1,2])
  end

  it 'should raise error' do
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

    apply_manifest(pp, :catch_failures => false) do |r|
      expect(r.stderr).to match(/Good news! The Yum Arch issue \(PUP-1364\) is resolved in Puppet >= 4.5.0/)
    end

  end

end
