require 'beaker-rspec'

# Install Puppet
unless ENV['RS_PROVISION'] == 'no'
  # This will install the latest available package on el and deb based
  # systems fail on windows and osx, and install via gem on other *nixes
  foss_opts = { :default_action => 'gem_install' }

  shell('yum remove puppetlabs-release.noarch -y')

  if default.is_pe?; then install_pe; else install_puppet( foss_opts ); end

  hosts.each do |host|
    on host, "mkdir -p #{host['distmoduledir']}"
  end
end

UNSUPPORTED_PLATFORMS = ['AIX','Solaris']

RSpec.configure do |c|
  # Project root
  proj_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))

  # Readable test descriptions
  c.formatter = :documentation

  # Configure all nodes in nodeset
  c.before :suite do
    # Install module and dependencies
    hosts.each do |host|
      shell('rm -rf /etc/puppet/modules/yum_arch/petems-yum_arch')
      shell('rm -rf /etc/puppet/modules/petems-yum_arch')
      shell('rm -rf /etc/puppet/modules/yum_arch/')
      copy_module_to(host, :source => proj_root, :module_name => 'yum_arch')
    end
  end
end
