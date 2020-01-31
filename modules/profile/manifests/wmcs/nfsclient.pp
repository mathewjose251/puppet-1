class profile::wmcs::nfsclient(
    String $mode = lookup('profile::wmcs::nfsclient::mode', {'default_value' => 'hard'}),
    String $lookupcache = lookup('profile::wmcs::nfsclient::lookupcache', {'default_value' => 'all'}),
    Array[Stdlib::Host] $dumps_servers = hiera('dumps_dist_nfs_servers'),
    Stdlib::Host $dumps_active_server = hiera('dumps_dist_active_vps'),
    Array[Stdlib::Host] $secondary_servers = lookup('secondary_nfs_servers', {'default_value' => []}),
    Stdlib::Host $scratch_active_server = lookup('scratch_active_server'),
    # The following is intentionally using the same value as for scratch.  This may not always
    # be desireable, so a separate parameter is offered.
    Stdlib::Host $maps_active_server = lookup('scratch_active_server'),
) {

    # TODO: Change these "secondary" mentions to "primary"
    # The primary cluster is mounted as secondary for historical reasons and
    # changing this would be quite disruptive so put off for a while.
    labstore::nfs_mount { 'project-on-labstore-secondary':
        mount_name  => 'project',
        project     => $::labsproject,
        options     => ['rw', $mode],
        mount_path  => '/mnt/nfs/labstore-secondary-project',
        share_path  => "/srv/misc/shared/${::labsproject}/project",
        server      => 'nfs-tools-project.svc.eqiad.wmnet',
        lookupcache => $lookupcache,
    }

    labstore::nfs_mount { 'home-on-labstore-secondary':
        mount_name  => 'home',
        project     => $::labsproject,
        options     => ['rw', 'hard'],
        mount_path  => '/mnt/nfs/labstore-secondary-home',
        share_path  => "/srv/misc/shared/${::labsproject}/home",
        server      => 'nfs-tools-project.svc.eqiad.wmnet',
        lookupcache => $lookupcache,
    }

    if mount_nfs_volume($::labsproject, 'project') {
        file { '/data/project':
            ensure  => 'link',
            force   => true,
            target  => '/mnt/nfs/labstore-secondary-project',
            require => Labstore::Nfs_mount['project-on-labstore-secondary'],
        }
    }

    if mount_nfs_volume($::labsproject, 'home') {
        file { '/home':
            ensure  => 'link',
            force   => true,
            target  => '/mnt/nfs/labstore-secondary-home',
            require => Labstore::Nfs_mount['home-on-labstore-secondary'],
        }
    }

    # These are actually the secondary servers, not the servers formerly known as
    # secondary.  These are not connected to the above TODO
    $secondary_servers.each |String $server| {
        labstore::nfs_mount { $server:
            mount_name  => 'scratch',
            project     => $::labsproject,
            options     => ['rw', 'soft', 'timeo=300', 'retrans=3'],
            mount_path  => "/mnt/nfs/secondary-${server}-scratch",
            share_path  => '/scratch',
            server      => $server,
            lookupcache => $lookupcache,
        }
    }
    if mount_nfs_volume($::labsproject, 'scratch') {
        file { '/data/scratch':
            ensure  => 'link',
            target  => "/mnt/nfs/secondary-${scratch_active_server}-scratch",
            require => Labstore::Nfs_mount[$scratch_active_server]
        }
    }

    if $::labsproject == 'maps' {

        labstore::nfs_mount { 'maps-on-secondary':
            mount_name  => 'maps',
            project     => $::labsproject,
            options     => ['rw', 'hard'],
            mount_path  => '/mnt/nfs/secondary-maps',
            server      => 'nfs-maps.wikimedia.org',
            share_path  => '/srv/maps',
            lookupcache => $lookupcache,
        }

        if mount_nfs_volume($::labsproject, 'maps') {

            file { '/data/project':
                ensure  => 'link',
                force   => true,
                target  => '/mnt/nfs/secondary-maps/project',
                require => Labstore::Nfs_mount['maps-on-secondary'],
            }

            file { '/home':
                ensure  => 'link',
                force   => true,
                target  => '/mnt/nfs/secondary-maps/home',
                require => Labstore::Nfs_mount['maps-on-secondary'],
            }
        }
    }

    if $::labsproject == 'tools' {

        labstore::nfs_mount { 'tools-home-on-labstore-secondary':
            mount_name  => 'tools-home',
            project     => $::labsproject,
            options     => ['rw', 'hard'],
            mount_path  => '/mnt/nfs/labstore-secondary-tools-home',
            server      => 'nfs-tools-project.svc.eqiad.wmnet',
            share_path  => '/srv/tools/shared/tools/home',
            lookupcache => $lookupcache,
        }

        labstore::nfs_mount { 'tools-project-on-labstore-secondary':
            mount_name  => 'tools-project',
            project     => $::labsproject,
            options     => ['rw', 'hard'],
            mount_path  => '/mnt/nfs/labstore-secondary-tools-project',
            server      => 'nfs-tools-project.svc.eqiad.wmnet',
            share_path  => '/srv/tools/shared/tools/project',
            lookupcache => $lookupcache,
        }

        # Sets up symlinks from new tools mounts to /data/project and /home
        if mount_nfs_volume($::labsproject, 'tools-project') {
            file { '/data/project':
                ensure  => 'link',
                force   => true,
                target  => '/mnt/nfs/labstore-secondary-tools-project',
                require => Labstore::Nfs_mount['tools-project-on-labstore-secondary'],
            }
        }
        if mount_nfs_volume($::labsproject, 'tools-home') {
            file { '/home':
                ensure  => 'link',
                force   => true,
                target  => '/mnt/nfs/labstore-secondary-tools-home',
                require => Labstore::Nfs_mount['tools-home-on-labstore-secondary'],
            }
        }
    }

    $dumps_servers.each |String $server| {
        labstore::nfs_mount { $server:
            mount_name  => 'dumps',
            project     => $::labsproject,
            options     => ['ro', 'soft', 'timeo=300', 'retrans=3'],
            mount_path  => "/mnt/nfs/dumps-${server}",
            share_path  => '',
            server      => $server,
            lookupcache => $lookupcache,
        }
    }

    if mount_nfs_volume($::labsproject, 'dumps') {

        file { '/public/dumps':
            ensure => 'directory',
            owner  => 'root',
            group  => 'root',
            mode   => '0755',
        }

        $dumps_share_root = "/mnt/nfs/dumps-${dumps_active_server}"

        $defaults = {
            ensure => 'link',
            require => Labstore::Nfs_mount[$dumps_active_server]
        }

        $symlinks = {
            '/public/dumps/public' => {
                target  => "${dumps_share_root}/",
            },
            '/public/dumps/incr' => {
                target  => "${dumps_share_root}/other/incr",
            },
            '/public/dumps/pagecounts-all-sites' => {
                target  => "${dumps_share_root}/other/pagecounts-all-sites",
            },
            '/public/dumps/pagecounts-raw' => {
                target  => "${dumps_share_root}/other/pagecounts-raw",
            },
            '/public/dumps/pageviews' => {
                target  => "${dumps_share_root}/other/pageviews",
            },
        }

        create_resources(file, $symlinks, $defaults)
    }
}
