# Designate provides DNSaaS services for OpenStack
# https://wiki.openstack.org/wiki/Designate

class openstack::designate::service(
    $active,
    $version,
    $designate_host,
    $designate_host_standby,
    $keystone_host,
    $db_user,
    $db_pass,
    $db_host,
    $db_name,
    $domain_id_internal_forward,
    $domain_id_internal_reverse,
    $puppetmaster_hostname,
    $nova_controller,
    $ldap_user_pass,
    $pdns_db_user,
    $pdns_db_pass,
    $pdns_db_name,
    $db_admin_user,
    $db_admin_pass,
    $primary_pdns_ip,
    $secondary_pdns_ip,
    $rabbit_user,
    $rabbit_pass,
    $rabbit_host_primary,
    $rabbit_host_secondary,
    $keystone_public_port,
    $keystone_auth_port,
    $region,
    $coordination_host,
    $puppet_git_repo_name,
    $puppet_git_repo_user,
    ) {

    $keystone_host_ip   = ipresolve($keystone_host,4)
    $nova_controller_ip = ipresolve($nova_controller)
    $keystone_public_uri = "http://${keystone_host}:${keystone_public_port}"
    $keystone_admin_uri = "http://${keystone_host}:${keystone_auth_port}"
    $designate_host_ip = ipresolve($designate_host,4)
    $designate_host_standby_ip = ipresolve($designate_host_standby,4)
    $puppetmaster_hostname_ip = ipresolve($puppetmaster_hostname,4)

    class { "openstack::designate::service::${version}": }

    file { '/usr/lib/python2.7/dist-packages/wmf_sink':
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        source  => "puppet:///modules/openstack/${version}/designate/wmf_sink",
        recurse => true,
    }

    file { '/usr/lib/python2.7/dist-packages/wmf_sink.egg-info':
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        source  => "puppet:///modules/openstack/${version}/designate/wmf_sink.egg-info",
        recurse => true,
    }

    file { '/usr/lib/python2.7/dist-packages/nova_fixed_multi':
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        source  => "puppet:///modules/openstack/${version}/designate/nova_fixed_multi",
        recurse => true,
    }

    file { '/usr/lib/python2.7/dist-packages/nova_fixed_multi.egg-info':
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        source  => "puppet:///modules/openstack/${version}/designate/nova_fixed_multi.egg-info",
        recurse => true,
    }

    # We'll need this key to push to the instance-puppet repo
    $puppet_git_repo_key_path = '/var/lib/designate/.ssh/instance-puppet-user.priv'

    file {
        '/etc/designate/designate.conf':
            owner     => 'designate',
            group     => 'designate',
            mode      => '0440',
            show_diff => false,
            content   => template("openstack/${version}/designate/designate.conf.erb"),
            notify    => Service[
              'designate-api',
              'designate-sink',
              'designate-central',
              'designate-mdns',
              'designate-producer',
              'designate-worker'],
            require   => Package['designate-common'];
        '/etc/designate/api-paste.ini':
            content => template("openstack/${version}/designate/api-paste.ini.erb"),
            owner   => 'designate',
            group   => 'designate',
            notify  => Service['designate-api','designate-sink','designate-central'],
            require => Package['designate-api'],
            mode    => '0440';
        '/etc/designate/policy.json':
            source  => "puppet:///modules/openstack/${version}/designate/policy.json",
            owner   => 'designate',
            group   => 'designate',
            notify  => Service['designate-api','designate-sink','designate-central'],
            require => Package['designate-common'],
            mode    => '0440';
        '/etc/designate/rootwrap.conf':
            source  => "puppet:///modules/openstack/${version}/designate/rootwrap.conf",
            owner   => 'root',
            group   => 'root',
            notify  => Service['designate-api','designate-sink','designate-central'],
            require => Package['designate-common'],
            mode    => '0440';
    }

    # Designate logrotate configurations were messed up for a long time
    # late Liberty versions fix this but this logrotate setup here should
    # ensure consistent state (T186142).  Absented things here can be removed
    # at a later date esp post Liberty.
    logrotate::conf { 'designate-common':
        ensure => 'present',
        source => 'puppet:///modules/openstack/designate/designate-common.logrotate',
    }

    file {'/etc/logrotate.d/designate-api':
        ensure => 'absent',
    }

    file {'/etc/logrotate.d/designate-central':
        ensure => 'absent',
    }

    file {'/etc/logrotate.d/designate-sink':
        ensure => 'absent',
    }

    file {'/etc/logrotate.d/designate-mdns':
        ensure => 'absent',
    }

    file {'/etc/logrotate.d/designate-pool-manager':
        ensure => 'absent',
    }

    file { '/var/lib/designate/.ssh/':
        ensure => 'directory',
        owner  => 'designate',
        group  => 'designate',
    }

    file { '/var/lib/designate/.ssh/id_rsa':
        owner     => 'designate',
        group     => 'designate',
        mode      => '0400',
        content   => secret('ssh/puppet_cert_manager/cert_manager'),
        show_diff => false,
    }

    # include rootwrap.d entries

    service {'designate-api':
        ensure  => $active,
        require => Package['designate-api'];
    }

    service {'designate-sink':
        ensure  => $active,
        require => Package['designate-sink'];
    }

    service {'designate-central':
        ensure  => $active,
        require => Package['designate-central'];
    }

    service {'designate-mdns':
        ensure  => $active,
        require =>  [
            Package['designate'],
        ],
    }

    service {'designate-pool-manager':
        ensure  => stopped,
    }

    service {'designate-zone-manager':
        ensure  => stopped,
    }

    $systemd_ensure = $active ? {
        true => 'present',
        default => 'absent',
    }

    # The Newton designate packages don't include service defs for
    #  the -worker or -producer services.  Hopefully we can replace these
    #  with simple service defines in O.
    systemd::service { 'designate-producer':
        ensure  => $systemd_ensure,
        content => systemd_template('designate-producer'),
        restart => true,
        require =>  [
            Package['designate'],
        ],
    }

    systemd::service { 'designate-worker':
        ensure  => $systemd_ensure,
        content => systemd_template('designate-worker'),
        restart => true,
        require =>  [
            Package['designate'],
        ],
    }

    # Get ready to host a local git repo of instance puppet config
    file { $puppet_git_repo_key_path:
        ensure    => file,
        owner     => 'designate',
        group     => 'designate',
        mode      => '0600',
        content   => secret('ssh/instance-puppet-user/instance-puppet-user_privkey.pem'),
        show_diff => false,
    }
}
