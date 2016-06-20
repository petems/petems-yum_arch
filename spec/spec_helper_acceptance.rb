require 'beaker-rspec'
require 'beaker/puppet_install_helper'

run_puppet_install_helper unless ENV['BEAKER_provision'] == 'no'

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
