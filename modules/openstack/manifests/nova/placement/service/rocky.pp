class openstack::nova::placement::service::rocky (
    Stdlib::Port $placement_api_port,
    ) {
    # simple enough to don't require per-debian release split
    require "openstack::serverpackages::rocky::${::lsbdistcodename}"

    package { 'nova-placement-api':
        ensure => 'present',
    }

    file { '/etc/init.d/nova-placement-api':
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        content => template('openstack/rocky/nova/placement/nova-placement-api.erb'),
    }
}
