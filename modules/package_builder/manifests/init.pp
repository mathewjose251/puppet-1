# Class package_builder
# Packaging environment building class
#
# Actions:
#   Installs Debian package creation/building tools and creates environments to
#   help with easy package building.
#
# Usage:
#   include package_builder
class package_builder(
    Stdlib::Unixpath $basepath='/var/cache/pbuilder',
) {
    class { '::package_builder::hooks':
        basepath => $basepath,
    }
    class { '::package_builder::environments':
        basepath => $basepath,
    }
    systemd::timer::job { 'package_builder_Clean_up_build_directory':
        ensure      => present,
        user        => 'root',
        description => 'Delete builds older the 2 weeks',
        command     => "/usr/bin/find ${basepath}/build -type f -daystart -mtime +14 -delete",
        interval    => {
            'start'    => 'OnCalendar',
            'interval' => '*-*-* 02:00:00',  # Every day at 2:00
        }
    }
    systemd::timer::job { 'package_builder_Clean_up_result_directory':
        ensure      => present,
        user        => 'root',
        description => 'Delete results older the 6 months',
        command     => "/usr/bin/find ${basepath}/result -type f -daystart -mtime +180 -delete",
        interval    => {
            'start'    => 'OnCalendar',
            'interval' => '*-*-* 03:00:00',  # Every day at 3:00
        }
    }

    # Install lintian from backports to make sure it checks the latest version
    # of the Debian Policy
    apt::pin { 'lintian':
        pin      => "release a=${::lsbdistcodename}-backports",
        package  => 'lintian',
        priority => '1001',
        before   => Package['lintian'],
    }

    package { 'lintian':
        ensure => present,
    }

    require_package([
        'cowbuilder',
        'build-essential',
        'fakeroot',
        'debhelper',
        'cdbs',
        'devscripts',
        'patchutils',
        'debian-keyring',
        'dh-make',
        'dh-autoreconf',
        'dh-golang',
        'dh-systemd',
        'openstack-pkg-tools',
        'git-buildpackage',
        'equivs',
        'quilt',
        'wdiff',
        'zip',
        'unzip',
        'debian-archive-keyring',
        'gnome-pkg-tools',
        'gobject-introspection',
        'libdistro-info-perl',
        'maven-repo-helper',
        'gradle',
        'pkg-php-tools',
        'kernel-wedge',
        'javahelper',
        'pkg-kde-tools',
        'subversion',
        'sphinx-common',
        'scons',
        'apache2-dev',
        'ivy-debian-helper',
        'maven-debian-helper',
        'haveged',
        'ubuntu-archive-keyring',
        'dh-python',
        'python3-setuptools',
        'dh-exec',
        'python3-setuptools-scm',
        'dh-make-golang',
        'dh-sysuser',
        'php-dev',
        'dh-php',
    ])

    file { '/etc/pbuilderrc':
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        content => template('package_builder/pbuilderrc.erb'),
    }

    file { '/usr/share/lintian/profiles/wikimedia':
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        require => Package['lintian'],
    }

    file { '/usr/share/lintian/profiles/wikimedia/main.profile':
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        source  => 'puppet:///modules/package_builder/wikimedia.profile',
        require => File['/usr/share/lintian/profiles/wikimedia'],
    }

    file { '/usr/share/lintian/vendors/wikimedia':
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        recurse => remote,
        source  => 'puppet:///modules/package_builder/lintian-wikimedia',
        require => Package['lintian'],
    }

    # Ship an apt configuration to integrate deb-src entries for jessie and
    # stretch, simplifies fetching the source for older distros by using
    # "apt-get source foo=VERSION" on the package build host
    ['stretch'].each |String $dist| {
        apt::repository{"${dist}-wikimedia_source_only":
            uri        => 'http://apt.wikimedia.org/wikimedia',
            dist       => "${dist}-wikimedia",
            bin        => false,
            components => 'main',
        }
        apt::repository{"${dist}_source_only":
            uri        => 'http://mirrors.wikimedia.org/debian/',
            dist       => $dist,
            bin        => false,
            components => 'main non-free contrib',
        }
        apt::repository{"${dist}-security_source_only":
            uri        => 'http://security.debian.org/debian-security',
            dist       => "${dist}/updates",
            bin        => false,
            components => 'main non-free contrib',
        }
    }
    # Ship an apt configuration to integrate deb-src entries for unstable,
    # simplifies fetching the source by using"apt-get source foo=VERSION"
    apt::repository{'unstable_source_only':
        uri        => 'http://mirrors.wikimedia.org/debian',
        dist       => 'unstable',
        bin        => false,
        components => 'main non-free contrib',
    }

    file { '/etc/lintianrc':
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        source  => 'puppet:///modules/package_builder/lintianrc',
        require => Package['lintian'],
    }

    # Dependency info
    Package['cowbuilder'] -> File['/etc/pbuilderrc']
    Package['cowbuilder'] -> Class['package_builder::environments']
    Package['cowbuilder'] -> Class['package_builder::hooks']
}
