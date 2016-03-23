#! /usr/bin/env ruby
require 'spec_helper'

provider_class = Puppet::Type.type(:package).provider(:yum_arch)

describe provider_class do
  let(:name) { 'mypackage' }
  let(:resource) do
    Puppet::Type.type(:package).new(
      :name     => name,
      :ensure   => :installed,
      :provider => 'yum_arch'
    )
  end

  let(:provider) do
    provider = provider_class.new
    provider.resource = resource
    provider
  end

  before do
    provider_class.stubs(:command).with(:cmd).returns('/usr/bin/yum')
    provider.stubs(:rpm).returns 'rpm'
    provider.stubs(:get).with(:version).returns '1'
    provider.stubs(:get).with(:release).returns '1'
    provider.stubs(:get).with(:arch).returns 'i386'
  end

  describe 'provider features' do
    it { is_expected.to be_versionable }
    it { is_expected.to be_install_options }
    it { is_expected.to be_virtual_packages }
  end

  # provider should repond to the following methods
   [:install, :latest, :update, :purge, :install_options].each do |method|
     it "should have a(n) #{method}" do
       expect(provider).to respond_to(method)
    end
  end

  shared_examples "arch in version string" do |arch|
    let(:name) { "mypackage.#{arch}" }
    let(:resource) do
      Puppet::Type.type(:package).new(
        :name          => name,
        :ensure        => :installed,
        :provider      => 'yum_arch',
        :allow_virtual => false,
      )
    end

    it 'should be able to set version and detect arch' do
      version = '1.2'
      resource[:ensure] = version
      Facter.stubs(:value).with(:operatingsystemmajrelease).returns('6')
      Puppet::Util::Execution.expects(:execute).with(['/usr/bin/yum', '-d', '0', '-e', '0', '-y', :list, "mypackage.#{arch}"])
      Puppet::Util::Execution.expects(:execute).with(['/usr/bin/yum', '-d', '0', '-e', '0', '-y', :install, "mypackage-1.2.#{arch}"])
      provider.stubs(:query).returns :ensure => '1.2'
      provider.install
    end
  end

  it_behaves_like "arch in version string", 'i686'

  it_behaves_like "arch in version string", 'x86_64'

  it 'should be versionable' do
    expect(provider).to be_versionable
  end
end
