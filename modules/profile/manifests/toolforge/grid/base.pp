# This establishes the basics for every SGE node

class profile::toolforge::grid::base (
    $external_hostname = hiera('profile::toolforge::external_hostname', undef),
    $external_ip = hiera('profile::toolforge::external_ip', undef),
    $is_mail_relay = hiera('profile::toolforge::is_mail_relay', false),
    $active_mail_relay = hiera('profile::toolforge::active_mail_relay', 'tools-mail.tools.eqiad.wmflabs'),
    $mail_domain = hiera('profile::toolforge::mail_domain', 'tools.wmflabs.org'),
    $active_proxy = hiera('profile::toolforge::active_proxy_host'),
    $etcdir = hiera('profile::toolforge::etcdir'),
) {

    include profile::toolforge::apt_pinning

    class { '::labs_lvm': }

    package { 'nano':
        ensure => latest,
    }

    alternatives::select { 'editor':
        path => '/bin/nano',
    }

    $project_path = '/data/project'
    # should match /etc/default/gridengine
    $sge_root     = '/var/lib/gridengine'
    $sysdir       = "${project_path}/.system_sge"
    $geconf       = "${sysdir}/gridengine"
    $collectors   = "${geconf}/collectors"

    # Weird use of NFS for config centralization.
    # Nodes drop their config into a directory.
    #  - SSH host keys for HBA
    #  - known_hosts
    $store  = "${sysdir}/store"

    exec {'ensure-grid-is-on-NFS':
        command => '/bin/false',
        unless  => "/usr/bin/timeout -k 5s 60s /usr/bin/test -e ${project_path}/herald",
    }

    file { $sysdir:
        ensure  => directory,
        owner   => 'root',
        group   => "${::labsproject}.admin",
        mode    => '2775',
        require => Exec['ensure-grid-is-on-NFS'],
    }

    file { $geconf:
        ensure  => directory,
        require => File[$sysdir],
    }

    file { $sge_root:
        ensure  => link,
        target  => $geconf,
        force   => true,
        require => File[$geconf],
    }

    file { $collectors:
        ensure  => directory,
        require => File[$geconf],
    }

    file { $store:
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        require => File[$sysdir],
    }

    file { "${store}/hostkey-${::fqdn}":
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        content => "${::fqdn},${::hostname},${::ipaddress} ssh-rsa ${::sshrsakey}\n${::fqdn},${::hostname},${::ipaddress} ecdsa-sha2-nistp256 ${::sshecdsakey}\n",
        require => File[$store],
    }

    # The follow conflicts with the ssh-known-hosts stuff with puppetdb
    # exec { 'make_known_hosts':
    #     command => "/bin/cat ${store}/hostkey-* >/etc/ssh/ssh_known_hosts~",
    #     onlyif  => "/usr/bin/test -n \"\$(/usr/bin/find ${store} -maxdepth 1 \\( -type d -or -type f -name hostkey-\\* \\) -newer /etc/ssh/ssh_known_hosts~)\" -o ! -s /etc/ssh/ssh_known_hosts~",
    #     require => File[$store],
    # }

    # file { '/etc/ssh/ssh_known_hosts':
    #     ensure  => file,
    #     source  => '/etc/ssh/ssh_known_hosts~',
    #     owner   => 'root',
    #     group   => 'root',
    #     mode    => '0444',
    #     require => Exec['make_known_hosts'],
    # }

    File['/var/lib/gridengine'] -> Package <| title == 'gridengine-common' |>

    file { '/shared':
        ensure  => link,
        target  => "${project_path}/.shared",
        require => Exec['ensure-grid-is-on-NFS'],
    }

    file { '/root/.bashrc':
        ensure => file,
        source => 'puppet:///modules/profile/toolforge/rootrc',
        owner  => 'root',
        group  => 'root',
        mode   => '0750',
    }

    # Users can choose their shell accounts names freely, and some
    # choose ones that can be misleading to third parties inter alia
    # when they are used to send and receive mail at
    # "$user@tools.wmflabs.org".  The most common ones are already
    # addressed by the default system aliases for "abuse",
    # "postmaster", "webmaster", etc., so we only have to add aliases
    # here that have not been standardized per se, but still bear a
    # high risk of mimicry.
    mailalias { [ 'admin', 'administrator' ]:
        ensure    => present,
        recipient => 'root',
    }

    if !$is_mail_relay {
        class { '::exim4':
            queuerunner => 'combined',
            config      => template('profile/toolforge/route-to-mail-relay.exim4.conf.erb'),
            variant     => 'light',
        }
    }

    # TODO: Remove after Puppet cycle.
    file { '/var/mail':
        ensure => directory,
        owner  => 'root',
        group  => 'mail',
        mode   => '2775',
    }

    # TODO: Remove after Puppet cycle.
    file { "${store}/mail":
        ensure => absent,
        force  => true,
    }

    # Link to currently active proxy
    file { '/etc/active-proxy':
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        content => $active_proxy,
    }

    # Silence e-mails sent when regular users try to sudo (T95882)
    file { '/etc/sudoers.d/40-tools-sudoers-no-warning':
        ensure => file,
        mode   => '0440',
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/profile/toolforge/40-tools-sudoers-no-warning',
    }

    file { '/usr/local/bin/log-command-invocation':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        mode   => '0555',
        source => 'puppet:///modules/profile/toolforge/log-command-invocation',
    }

    diamond::collector::localcrontab { 'localcrontabcollector': }
}
