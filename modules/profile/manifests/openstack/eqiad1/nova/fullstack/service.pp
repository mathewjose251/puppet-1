class profile::openstack::eqiad1::nova::fullstack::service(
    $osstackcanary_pass = hiera('profile::openstack::eqiad1::nova::fullstack_pass'),
    Array[Stdlib::Fqdn] $openstack_controllers = lookup('profile::openstack::eqiad1::openstack_controllers'),
    $region = hiera('profile::openstack::eqiad1::region'),
    $network = hiera('profile::openstack::eqiad1::nova::instance_network_id'),
    $puppetmaster = hiera('profile::openstack::eqiad1::puppetmaster_hostname'),
    ) {

    require ::profile::openstack::eqiad1::clientpackages
    class { '::profile::openstack::base::nova::fullstack::service':
        openstack_controllers => $openstack_controllers,
        osstackcanary_pass    => $osstackcanary_pass,
        region                => $region,
        network               => $network,
        puppetmaster          => $puppetmaster,
    }

    # We only want this running in one place; just pick the first
    #  option in the list.
    if ($::fqdn == $openstack_controllers[0]) {
        class {'::openstack::nova::fullstack::monitor':}
    }
}
