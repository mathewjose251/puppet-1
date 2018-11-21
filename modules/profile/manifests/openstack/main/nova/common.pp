class profile::openstack::main::nova::common(
    $version = hiera('profile::openstack::main::version'),
    $nova_controller = hiera('profile::openstack::main::nova_controller'),
    $keystone_host = hiera('profile::openstack::main::keystone_host'),
    $glance_host = hiera('profile::openstack::main::glance_host'),
    $nova_api_host = hiera('profile::openstack::main::nova_api_host'),
    $dmz_cidr = hiera('profile::openstack::main::nova::dmz_cidr'),
    $dhcp_domain = hiera('profile::openstack::main::nova::dhcp_domain'),
    $dhcp_start = hiera('profile::openstack::main::nova::dhcp_start'),
    $quota_floating_ips = hiera('profile::openstack::main::nova::quota_floating_ips'),
    $network_flat_interface = hiera('profile::openstack::main::nova::network_flat_interface'),
    $flat_network_bridge = hiera('profile::openstack::main::nova::flat_network_bridge'),
    $fixed_range = hiera('profile::openstack::main::nova::fixed_range'),
    $network_public_interface = hiera('profile::openstack::main::nova::network_public_interface'),
    $network_public_ip = hiera('profile::openstack::main::nova::network_public_ip'),
    $zone = hiera('profile::openstack::main::nova::zone'),
    $scheduler_pool = hiera('profile::openstack::main::nova::scheduler_pool'),
    $db_pass = hiera('profile::openstack::main::nova::db_pass'),
    $db_host = hiera('profile::openstack::main::nova::db_host'),
    $ldap_user_pass = hiera('profile::openstack::main::ldap_user_pass'),
    $live_migration_uri = hiera('profile::openstack::main::nova::live_migration_uri'),
    $rabbit_pass = hiera('profile::openstack::main::nova::rabbit_pass'),
    $spice_hostname = hiera('profile::openstack::main::spice_hostname'),
    $compute_workers = hiera('profile::openstack::main::nova::compute_workers'),
    ) {

    require ::profile::openstack::main::serverpackages

    class {'profile::openstack::base::nova::common::nova_network':
        version                  => $version,
        nova_controller          => $nova_controller,
        keystone_host            => $keystone_host,
        glance_host              => $glance_host,
        nova_api_host            => $nova_api_host,
        dmz_cidr                 => $dmz_cidr,
        dhcp_domain              => $dhcp_domain,
        quota_floating_ips       => $quota_floating_ips,
        dhcp_start               => $dhcp_start,
        network_flat_interface   => $network_flat_interface,
        flat_network_bridge      => $flat_network_bridge,
        fixed_range              => $fixed_range,
        network_public_interface => $network_public_interface,
        network_public_ip        => $network_public_ip,
        zone                     => $zone,
        scheduler_pool           => $scheduler_pool,
        db_pass                  => $db_pass,
        db_host                  => $db_host,
        ldap_user_pass           => $ldap_user_pass,
        live_migration_uri       => $live_migration_uri,
        rabbit_pass              => $rabbit_pass,
        spice_hostname           => $spice_hostname,
        compute_workers          => $compute_workers,
    }
}
