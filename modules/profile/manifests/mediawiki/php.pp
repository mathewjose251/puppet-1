# === Class profile::mediawiki::php
#
# This class declares packages that make up Wikimedia's PHP7-based
# MediaWiki deployment stack.
# See T172165
#
# overview of modules needed and their use:
#
# apcu - used by MediaWiki for local server caching
# bz2 - dumps
# curl - HTTP requests
# gd - ZeroBanner
# geoip - fundraising
# intl, mbstring, xml - MediaWiki dependencies
# memcached, mysql, redis - obvious from the name
# bcmath, gmp - various extensions and vendor libraries
#
class profile::mediawiki::php(
    Boolean $enable_fpm = hiera('profile::mediawiki::php::enable_fpm'),
    Optional[Hash] $fpm_config = hiera('profile::mediawiki::php::fpm_config', undef),
    Wmflib::Php_version $php_version = hiera('profile::mediawiki::php::php_version', '7.0'),
    Optional[Wmflib::UserIpPort] $port = hiera('profile::php_fpm::fcgi_port', undef),
    String $fcgi_pool = hiera('profile::mediawiki::fcgi_pool', 'www'),
    Integer $request_timeout = hiera('profile::mediawiki::php::request_timeout', 240),
    String $apc_shm_size = hiera('profile::mediawiki::apc_shm_size'),
    # temporary, for php restarts
    String $cluster = lookup('cluster'),
    # Needed for wmerrors
    String $statsd = lookup('statsd'),
    # Allows to tune up or down the number of workers.
    Float $fpm_workers_multiplier = lookup('profile::mediawiki::php::fpm_workers_multiplier', {'default_value' => 1.5}),
    Boolean $enable_request_profiling = lookup('profile::mediawiki::php::enable_request_profiling', {'default_value' => false}),
    Optional[Boolean] $enable_php_core_dumps = lookup('profile::mediawiki::php:::enable_php_core_dumps', {'default_value' => false}),
    Integer $slowlog_limit = lookup('profile::mediawiki::php::slowlog_limit', {'default_value' => 15}),
    Boolean $phpdbg = lookup('profile::mediawiki::php::phpdbg', {'default_value' => false}),
    ) {

    if os_version('debian == stretch') {
        # We get our packages for our repositories again
        file { '/etc/apt/preferences.d/php_wikidiff2.pref':
            ensure => absent,
            notify => Exec['apt_update_php'],
        }
        # Use component/php72. The core php7.2 package is imported from Ondrej Sury's repository,
        # but it's rebuilt (along with a range of extensions) against Stretch only (while
        # the repository also imports/forks a number of low level libraries to accomodate
        # the PHP packages for jessie
        if $php_version == '7.2' {
            apt::repository { 'wikimedia-php72':
                uri        => 'http://apt.wikimedia.org/wikimedia',
                dist       => 'stretch-wikimedia',
                components => 'component/php72',
                notify     => Exec['apt_update_php'],
                before     => Package["php${php_version}-common", "php${php_version}-opcache"]
            }
        }

        # First installs can trip without this
        exec {'apt_update_php':
            command     => '/usr/bin/apt-get update',
            refreshonly => true,
        }
    }

    $config_cli = {
        'include_path'           => '".:/usr/share/php"',
        'error_log'              => 'syslog',
        'pcre.backtrack_limit'   => 5000000,
        'date.timezone'          => 'UTC',
        'display_errors'         => 'stderr',
        'memory_limit'           => '500M',
        'error_reporting'        => 'E_ALL & ~E_STRICT',
        'mysql'                  => { 'connect_timeout' => 3 },
        'default_socket_timeout' => 60,
    }

    # Custom config for php-fpm
    # basic optimizations for opcache. See T206341
    $rlimit_core = $enable_php_core_dumps ? {
        true    => 'unlimited',
        default => '0',
    }
    $base_config_fpm = {
        'opcache.enable'                  => 1,
        'opcache.interned_strings_buffer' => 50,
        'opcache.memory_consumption'      => 300,
        'opcache.max_accelerated_files'   => 24000,
        'opcache.max_wasted_percentage'   => 10,
        'opcache.validate_timestamps'     => 1,
        'opcache.revalidate_freq'         => 10,
        'auto_prepend_file'               => '/srv/mediawiki/wmf-config/PhpAutoPrepend.php',
        'display_errors'                  => 0,
        'session.upload_progress.enabled' => 0,
        'enable_dl'                       => 0,
        'apc.shm_size'                    => $apc_shm_size,
        'rlimit_core'                     => $rlimit_core,
    }
    if $enable_fpm {
        $_sapis = ['cli', 'fpm']
        $_config = {
            'cli' => $config_cli,
            'fpm' => merge($config_cli, $base_config_fpm, $fpm_config)
        }
        # Add systemd override for php-fpm, that should prevent a reload
        # if the fpm config files are broken.
        # This should prevent us from shooting our own foot as happened before.
        systemd::unit { "php${php_version}-fpm.service":
            ensure   => present,
            content  => template('profile/mediawiki/php-fpm-systemd-override.conf.erb'),
            override => true,
            restart  => false,
        }
    } else {
        $_sapis = ['cli']
        $_config = {
            'cli' => $config_cli,
        }
    }
    # Install the runtime
    class { '::php':
        ensure         => present,
        version        => $php_version,
        sapis          => $_sapis,
        config_by_sapi => $_config,
    }

    # Extensions that need no custom settings

    # First, extensions provided as core extensions; these are version-specific
    # and are provided as php$version-$extension
    #
    $core_extensions =  [
        'bcmath',
        'bz2',
        'curl',
        'gd',
        'gmp',
        'intl',
        'mbstring',
    ]

    $core_extensions.each |$extension| {
        php::extension { $extension:
            package_name => "php${php_version}-${extension}"
        }
    }
    # Extensions that are installed with package-name php-$extension and, based
    # on the php version selected above, will install the proper extension
    # version based on apt priorities.
    # php-luasandbox and  php-wikidiff2 are special cases as the package is *not*
    # compatible with all supported PHP versions.
    # Technically, it would be needed to inject ensure => latest in the packages,
    # but we prefer to handle the transitions with other tools than puppet.
    php::extension { [
        'apcu',
        'geoip',
        'msgpack',
        'redis',
        'luasandbox',
        'wikidiff2',
    ]:
        ensure => present
    }

    # Extensions that require configuration.
    php::extension {
        'xml':
            package_name => "php${php_version}-xml",
            priority     => 15;
        'memcached':
            priority => 25,
            config   => {
                'extension'                   => 'memcached.so',
                'memcached.serializer'        => 'php',
                'memcached.store_retry_count' => '0'
            };
        'igbinary':
            config   => {
                'extension'                => 'igbinary.so',
                'igbinary.compact_strings' => 'Off',
            };
        'mysqli':
            package_name => "php${php_version}-mysql",
            config       => {
                'extension'                 => 'mysqli.so',
                'mysqli.allow_local_infile' => 'Off',
            }
            ;

        'dba':
            package_name => "php${php_version}-dba",
    }

    # Additional config files are needed by some extensions, add them
    # MySQL
    php::extension {
        default:
            package_name => '',;
        'pdo_mysql':
            ;
        'mysqlnd':
            priority => 10,
    }
    # XML
    php::extension{ [
        'dom',
        'simplexml',
        'xmlreader',
        'xmlwriter',
        'xsl',
        'wddx',
    ]:
        package_name => '',
    }

    if $phpdbg {
      package { "php${php_version}-phpdbg":
        ensure => present
      }
    }

    ### FPM configuration
    # You can check all configuration options at
    # http://php.net/manual/en/install.fpm.configuration.php
    if $enable_fpm {
        class { '::php::fpm':
            ensure => present,
            config => {
                'emergency_restart_interval'  => '60s',
                'emergency_restart_threshold' => $facts['processors']['count'],
                'process.priority'            => -19,
            }
        }

        # This will add an fpm pool listening on port $port
        # We want a minimum of 8 workers, and (we default to 1.5 * number of processors.
        # That number will be raised. Also move to pm = static as pm = dynamic caused some
        # edge-case spikes in p99 latency
        $num_workers = max(floor($facts['processors']['count'] * $fpm_workers_multiplier), 8)
        php::fpm::pool { $fcgi_pool:
            port   => $port,
            config => {
                'pm'                        => 'static',
                'pm.max_children'           => $num_workers,
                'request_terminate_timeout' => $request_timeout,
                'request_slowlog_timeout'   => $slowlog_limit,
            }
        }

        # Send logs locally to /var/log/php7.x-fpm/error.log
        # Please note: this replaces the logrotate rule coming from the package,
        # because we use syslog-based logging. This will also prevent an fpm reload
        # for every logrotate run.
        $fpm_programname = "php${php_version}-fpm"
        systemd::syslog { $fpm_programname:
            base_dir     => '/var/log',
            owner        => 'www-data',
            group        => 'wikidev',
            readable_by  => 'group',
            log_filename => 'error.log'
        }
    }

    # Set up request profiling (T206152, see also T253547)
    # Install tideways-xhprof and mongodb
    $profiling_ensure = $enable_request_profiling ? {
        true    => 'present',
        default => 'absent'
    }
    php::extension { 'mongodb':
        ensure   => $profiling_ensure,
        priority => 30,
    }
    php::extension { 'tideways-xhprof':
        ensure   => $profiling_ensure,
        priority => 30,
        config   => {
            'extension'                       => 'tideways_xhprof.so',
            'tideways_xhprof.clock_use_rdtsc' => '0',
        }
    }

    ## Install excimer, our php profiler, if we're on a newer version of php
    # Please note this is not a single request profiler, it is rather a profiling sampler.
    # Thus, it is active on all appserver and not just on the ones that allow running profiling.
    if $php_version != '7.0' {
        php::extension { 'excimer':
            ensure => present,
        }
    }

    # Set the default interpreter to php7
    $cli_path = "/usr/bin/php${php_version}"
    $pkg = "php${php_version}-cli"
    alternatives::select { 'php':
        path    => $cli_path,
        require => Package[$pkg],
    }

    ## Install wmerrors, on fpm only.
    if $php_version != '7.0' and $enable_fpm {
        php::extension { 'wmerrors':
            ensure => present,
            sapis  => ['fpm'],
            config => {
                'extension'                  => 'wmerrors.so',
                'wmerrors.error_script_file' => '/etc/php/php7-fatal-error.php',
                'wmerrors.enabled'           => true,
            },
        }
        file { '/etc/php/php7-fatal-error.php':
            ensure => present,
            mode   => '0444',
            owner  => 'root',
            group  => 'root',
            source => 'puppet:///modules/profile/mediawiki/php/php7-fatal-error.php',
        }

        $statsd_parts = split($statsd, ':')
        $statsd_host = $statsd_parts[0]
        $statsd_port = $statsd_parts[1]

        file { '/etc/php/error-params.php':
            ensure  => present,
            mode    => '0444',
            owner   => 'root',
            group   => 'root',
            content => template('profile/mediawiki/error-params.php.erb'),
        }
    }
    else {
        # Temoprary cleanup for the previous error
        php::extension { 'wmerrors':
            ensure => absent,
        }
    }
}
