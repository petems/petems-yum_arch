# petems-yum_arch

[![Build Status](https://travis-ci.org/petems/petems-yum_arch.svg?branch=master)](https://travis-ci.org/petems/petems-yum_arch)

# PUP-1364 now fixed in Puppet 4.5 onwards!

[PUP-1364](https://tickets.puppetlabs.com/browse/PUP-1364) has now been fixed. It should now be resolved in Puppet 4.5 onwards.

This module is for people using the older version of Puppet, a error has been added if you're using a Puppet version >= 4.5, as this module is a workaround.

## Usage

```puppet
package{ "firefox.x86_64":
  ensure => "45.2.0-1.el6.centos",
  provider => yum_arch,
}
```

## What is this?

This is a basic workaround module for PUP-1364

It basically takes the code from the Yum provider, and adds a bit of a hacky regex to move the arch to the end of the version string.

A better solution would be to have an `arch` parameter for the Package type.

## Example

Right now the way to declare an arch for a package version is like so:

```puppet
package{ "firefox.x86_64":
  ensure   => "45.2.0-1.el6.centos",
  provider => yum_arch,
}
```

However, this adds the version number to the package name with the arch in the middle of the string, so you get a failure like this:

```
==> default: Error: Could not update: Execution of '/usr/bin/yum -d 0 -e 0 -y install firefox.x86_64-45.2.0-1.el6.centos' returned 1: Error: Nothing to do
==> default: Wrapped exception:
==> default: Execution of '/usr/bin/yum -d 0 -e 0 -y install firefox.x86_64-45.2.0-1.el6.centos' returned 1: Error: Nothing to do
```

So, I made a bit of a hacky change to move the arch string to the end of the package:

```ruby
if wanted.scan(/(\.i686|\.x86_64)/)
  self.debug "Detected Arch argument in package! - Moving arch to end of version string"
  wanted.gsub!(/(.+)(\.i686|\.x86_64)(.+)/,'\1\3\2')
end
```

So you get this instead:

```bash
Debug: Package[firefox.x86_64](provider=yum_arch): Detected Arch argument in package! - Moving arch to end of version string
Debug: Executing '/bin/rpm -q firefox.x86_64 --nosignature --nodigest --qf %{NAME} %|EPOCH?{%{EPOCH}}:{0}| %{VERSION} %{RELEASE} %{ARCH}\n'
Debug: Executing '/usr/bin/yum -d 0 -e 0 -y install firefox-45.2.0-1.el6.centos.x86_64'
```

