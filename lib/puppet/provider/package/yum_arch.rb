Puppet::Type.type(:package).provide :yum_arch, :parent => :rpm, :source => :rpm do
  desc "An extension to the native 'Yum' provider as a workaround for PUP-3263"

  has_feature :install_options, :versionable, :virtual_packages

  commands :cmd => "yum", :rpm => "rpm"

  PUP1364_YUM_ARCH_LIST = [
    'i386',
    'i686',
    'ppc',
    'ppc64',
    'armv3l',
    'armv4b',
    'armv4l',
    'armv4tl',
    'armv5tel',
    'armv5tejl',
    'armv6l',
    'armv7l',
    'm68kmint',
    's390',
    's390x',
    'ia64',
    'x86_64',
    'sh3',
    'sh4',
  ]

  PUP1364_ARCH_REGEX = Regexp.new(PUP1364_YUM_ARCH_LIST.join('|\.'))

  if command('rpm')
    confine :true => begin
      rpm('--version')
      rescue Puppet::ExecutionFailure
        false
      else
        true
      end
  end

  def self.prefetch(packages)
    raise Puppet::Error, "The yum provider can only be used as root" if Process.euid != 0
    super
  end

  # Retrieve the latest package version information for a given package name
  # and combination of repos to enable and disable.
  #
  # @note If multiple package versions are defined (such as in the case where a
  #   package is built for multiple architectures), the first package found
  #   will be used.
  #
  # @api private
  # @param package [String] The name of the package to query
  # @param enablerepo [Array<String>] A list of repositories to enable for this query
  # @param disablerepo [Array<String>] A list of repositories to disable for this query
  # @param disableexcludes [Array<String>] A list of repository excludes to disable for this query
  # @return [Hash<Symbol, String>]
  def self.latest_package_version(package, enablerepo, disablerepo, disableexcludes)

    key = [enablerepo, disablerepo, disableexcludes]

    @latest_versions ||= {}
    if @latest_versions[key].nil?
      @latest_versions[key] = check_updates(enablerepo, disablerepo, disableexcludes)
    end

    if @latest_versions[key][package]
      @latest_versions[key][package].first
    end
  end

  # Search for all installed packages that have newer versions, given a
  # combination of repositories to enable and disable.
  #
  # @api private
  # @param enablerepo [Array<String>] A list of repositories to enable for this query
  # @param disablerepo [Array<String>] A list of repositories to disable for this query
  # @param disableexcludes [Array<String>] A list of repository excludes to disable for this query
  # @return [Hash<String, Array<Hash<String, String>>>] All packages that were
  #   found with a list of found versions for each package.
  def self.check_updates(enablerepo, disablerepo, disableexcludes)
    args = [command(:cmd), 'check-update']
    args.concat(enablerepo.map { |repo| ["--enablerepo=#{repo}"] }.flatten)
    args.concat(disablerepo.map { |repo| ["--disablerepo=#{repo}"] }.flatten)
    args.concat(disableexcludes.map { |repo| ["--disableexcludes=#{repo}"] }.flatten)

    output = Puppet::Util::Execution.execute(args, :failonfail => false, :combine => false)

    updates = {}
    if output.exitstatus == 100
      updates = parse_updates(output)
    elsif output.exitstatus == 0
      self.debug "#{command(:cmd)} check-update exited with 0; no package updates available."
    else
      self.warning "Could not check for updates, '#{command(:cmd)} check-update' exited with #{output.exitstatus}"
    end
    updates
  end

  def self.parse_updates(str)
    # Strip off all content before the first blank line
    body = str.partition(/^\s*\n/m).last

    updates = Hash.new { |h, k| h[k] = [] }
    body.split.each_slice(3) do |tuple|
      break if tuple[0] =~ /^(Obsoleting|Security:|Update)/
      hash = update_to_hash(*tuple[0..1])
      # Create entries for both the package name without a version and a
      # version since yum considers those as mostly interchangeable.
      short_name = hash[:name]
      long_name  = "#{hash[:name]}.#{hash[:arch]}"

      updates[short_name] << hash
      updates[long_name] << hash
    end

    updates
  end

  def self.update_to_hash(pkgname, pkgversion)
    name, arch = pkgname.split('.')

    match = pkgversion.match(/^(?:(\d+):)?(\S+)-(\S+)$/)
    epoch = match[1] || '0'
    version = match[2]
    release = match[3]

    {
      :name => name,
      :epoch => epoch,
      :version => version,
      :release => release,
      :arch    => arch,
    }
  end

  def self.clear
    @latest_versions = nil
  end

  def self.error_level
    '0'
  end

  def install
    check_puppet_version
    wanted = @resource[:name]
    error_level = self.class.error_level
    # If not allowing virtual packages, do a query to ensure a real package exists
    unless @resource.allow_virtual?
      execute([command(:cmd), '-d', '0', '-e', error_level, '-y', install_options, :list, wanted].compact)
    end

    should = @resource.should(:ensure)
    self.debug "Ensuring => #{should}"
    operation = :install

    case should
    when true, false, Symbol
      # pass
      should = nil
    else
      # Add the package version
      wanted += "-#{should}"
      if wanted.scan(PUP1364_ARCH_REGEX)
        self.debug "Detected Arch argument in package! - Moving arch to end of version string"
        wanted.gsub!(/(.+)(#{PUP1364_ARCH_REGEX})(.+)/,'\1\3\2')
      end
      is = self.query
      if is && yum_compareEVR(yum_parse_evr(should), yum_parse_evr(is[:ensure])) < 0
        self.debug "Downgrading package #{@resource[:name]} from version #{is[:ensure]} to #{should}"
        operation = :downgrade
      end
    end

    # Yum on el-4 and el-5 returns exit status 0 when trying to install a package it doesn't recognize;
    # ensure we capture output to check for errors.
    no_debug = if Facter.value(:operatingsystemmajrelease).to_i > 5 then ["-d", "0"] else [] end
    command = [command(:cmd)] + no_debug + ["-e", error_level, "-y", install_options, operation, wanted].compact
    output = execute(command)

    if output =~ /^No package #{wanted} available\.$/
      raise Puppet::Error, "Could not find package #{wanted}"
    end

    # If a version was specified, query again to see if it is a matching version
    if should
      is = self.query
      raise Puppet::Error, "Could not find package #{self.name}" unless is

      # FIXME: Should we raise an exception even if should == :latest
      # and yum updated us to a version other than @param_hash[:ensure] ?
      vercmp_result = yum_compareEVR(yum_parse_evr(should), yum_parse_evr(is[:ensure]))
      raise Puppet::Error, "Failed to update to version #{should}, got version #{is[:ensure]} instead" if vercmp_result != 0
    end
  end

  # What's the latest package version available?
  def latest
    check_puppet_version
    upd = self.class.latest_package_version(@resource[:name], enablerepo, disablerepo, disableexcludes)
    unless upd.nil?
      # FIXME: there could be more than one update for a package
      # because of multiarch
      return "#{upd[:epoch]}:#{upd[:version]}-#{upd[:release]}"
    else
      # Yum didn't find updates, pretend the current version is the latest
      version = properties[:ensure]
      raise Puppet::DevError, "Tried to get latest on a missing package" if version == :absent || version == :purged
      return version
    end
  end

  def update
    # Install in yum can be used for update, too
    check_puppet_version
    self.install
  end

  def purge
    check_puppet_version
    execute([command(:cmd), "-y", :erase, @resource[:name]])
  end

  def check_puppet_version
    unless Puppet::Util::Package.versioncmp(Puppet::PUPPETVERSION, '4.5.0') == -1
      error_string = "Good news! The Yum Arch issue (PUP-1364) is resolved in Puppet >= 4.5.0 (you are on #{Puppet::PUPPETVERSION}).
      To resolve this error, remove `provider => yum_arch` from your packages. The regular provider => yum will now accept arch strings"
      raise Puppet::Error, error_string
    end
  end

  # parse a yum "version" specification
  # this re-implements yum's
  # rpmUtils.miscutils.stringToVersion() in ruby
  def yum_parse_evr(s)
    ei = s.index(':')
    if ei
      e = s[0,ei]
      s = s[ei+1,s.length]
    else
      e = nil
    end
    e = String(Bignum(e)) rescue '0'
    ri = s.index('-')
    if ri
      v = s[0,ri]
      r = s[ri+1,s.length]
    else
      v = s
      r = nil
    end
    return { :epoch => e, :version => v, :release => r }
  end

  # how yum compares two package versions:
  # rpmUtils.miscutils.compareEVR(), which massages data types and then calls
  # rpm.labelCompare(), found in rpm.git/python/header-py.c, which
  # sets epoch to 0 if null, then compares epoch, then ver, then rel
  # using compare_values() and returns the first non-0 result, else 0.
  # This function combines the logic of compareEVR() and labelCompare().
  #
  # "version_should" can be v, v-r, or e:v-r.
  # "version_is" will always be at least v-r, can be e:v-r
  def yum_compareEVR(should_hash, is_hash)
    # pass on to rpm labelCompare
    rc = compare_values(should_hash[:epoch], is_hash[:epoch])
    return rc unless rc == 0
    rc = compare_values(should_hash[:version], is_hash[:version])
    return rc unless rc == 0

    # here is our special case, PUP-1244.
    # if should_hash[:release] is nil (not specified by the user),
    # and comparisons up to here are equal, return equal. We need to
    # evaluate to whatever level of detail the user specified, so we
    # don't end up upgrading or *downgrading* when not intended.
    #
    # This should NOT be triggered if we're trying to ensure latest.
    return 0 if should_hash[:release].nil?

    rc = compare_values(should_hash[:release], is_hash[:release])
    return rc
  end

  # this method is a native implementation of the
  # compare_values function in rpm's python bindings,
  # found in python/header-py.c, as used by yum.
  def compare_values(s1, s2)
    if s1.nil? && s2.nil?
      return 0
    elsif ( not s1.nil? ) && s2.nil?
      return 1
    elsif s1.nil? && (not s2.nil?)
      return -1
    end
    return rpmvercmp(s1, s2)
  end

  private

  def enablerepo
    scan_options(resource[:install_options], '--enablerepo')
  end

  def disablerepo
    scan_options(resource[:install_options], '--disablerepo')
  end

  def disableexcludes
    scan_options(resource[:install_options], '--disableexcludes')
  end

  # Scan a structure that looks like the package type 'install_options'
  # structure for all hashes that have a specific key.
  #
  # @api private
  # @param options [Array<String | Hash>, nil] The options structure. If the
  #   options are nil an empty array will be returned.
  # @param key [String] The key to look for in all contained hashes
  # @return [Array<String>] All hash values with the given key.
  def scan_options(options, key)
    return [] if options.nil?
    options.inject([]) do |repos, opt|
      if opt.is_a? Hash and opt[key]
        repos << opt[key]
      end
      repos
    end
  end

  # This is an attempt at implementing RPM's
  # lib/rpmvercmp.c rpmvercmp(a, b) in Ruby.
  #
  # Some of the things in here look REALLY
  # UGLY and/or arbitrary. Our goal is to
  # match how RPM compares versions, quirks
  # and all.
  #
  # I've kept a lot of C-like string processing
  # in an effort to keep this as identical to RPM
  # as possible.
  #
  # returns 1 if str1 is newer than str2,
  #         0 if they are identical
  #        -1 if str1 is older than str2
  def rpmvercmp(str1, str2)
    return 0 if str1 == str2

    front_strip_re = /^[^A-Za-z0-9~]+/

    while str1.length > 0 or str2.length > 0
      # trim anything that's in front_strip_re and != '~' off the beginning of each string
      str1 = str1.gsub(front_strip_re, '')
      str2 = str2.gsub(front_strip_re, '')

      # "handle the tilde separator, it sorts before everything else"
      if /^~/.match(str1) && /^~/.match(str2)
        # if they both have ~, strip it
        str1 = str1[1..-1]
        str2 = str2[1..-1]
      elsif /^~/.match(str1)
        return -1
      elsif /^~/.match(str2)
        return 1
      end

      break if str1.length == 0 or str2.length == 0

      # "grab first completely alpha or completely numeric segment"
      isnum = false
      # if the first char of str1 is a digit, grab the chunk of continuous digits from each string
      if /^[0-9]+/.match(str1)
        if str1 =~ /^[0-9]+/
          segment1 = $~.to_s
          str1 = $~.post_match
        else
          segment1 = ''
        end
        if str2 =~ /^[0-9]+/
          segment2 = $~.to_s
          str2 = $~.post_match
        else
          segment2 = ''
        end
        isnum = true
      # else grab the chunk of continuous alphas from each string (which may be '')
      else
        if str1 =~ /^[A-Za-z]+/
          segment1 = $~.to_s
          str1 = $~.post_match
        else
          segment1 = ''
        end
        if str2 =~ /^[A-Za-z]+/
          segment2 = $~.to_s
          str2 = $~.post_match
        else
          segment2 = ''
        end
      end

      # if the segments we just grabbed from the strings are different types (i.e. one numeric one alpha),
      # where alpha also includes ''; "numeric segments are always newer than alpha segments"
      if segment2.length == 0
        return 1 if isnum
        return -1
      end

      if isnum
        # "throw away any leading zeros - it's a number, right?"
        segment1 = segment1.gsub(/^0+/, '')
        segment2 = segment2.gsub(/^0+/, '')
        # "whichever number has more digits wins"
        return 1 if segment1.length > segment2.length
        return -1 if segment1.length < segment2.length
      end

      # "strcmp will return which one is greater - even if the two segments are alpha
      # or if they are numeric. don't return if they are equal because there might
      # be more segments to compare"
      rc = segment1 <=> segment2
      return rc if rc != 0
    end #end while loop

    # if we haven't returned anything yet, "whichever version still has characters left over wins"
    if str1.length > str2.length
      return 1
    elsif str1.length < str2.length
      return -1
    else
      return 0
    end
  end

end
