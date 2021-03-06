# Create remote xtrabackup/mariabackup backups
# By using transfer.py
class profile::mariadb::backup::transfer {
    require ::profile::mariadb::wmfmariadbpy
    require_package(
        'wmfbackups-remote',  # will install also wmfmariadbpy-remote and transferpy
    )

    # we can override transferpy defaults if needed
    file { '/etc/transferpy/transferpy.conf':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        mode   => '0444',
        source => 'puppet:///modules/profile/mariadb/transferpy.conf',
    }

    include ::passwords::mysql::dump
    $stats_user = $passwords::mysql::dump::stats_user
    $stats_password = $passwords::mysql::dump::stats_pass
    # Configuration file where the daily backup routine (source hosts,
    # destination, statistics db is configured
    # Can contain private data like db passwords
    file { '/etc/wmfbackups/remote_backups.cnf':
        ensure    => present,
        owner     => 'root',
        group     => 'root',
        mode      => '0400',
        show_diff => false,
        content   => template("profile/mariadb/backup_config/${::hostname}.cnf.erb"),
        require   => [ Package['wmfbackups-remote'],
        ],
    }

    cron { 'regular_snapshot':
        minute  => 0,
        hour    => 19,
        weekday => [0, 2, 3, 5],
        user    => 'root',
        command => 'remote-backup-mariadb > /dev/null 2>&1',
        require => [File['/etc/wmfbackups/remote_backups.cnf'],
                    Package['wmfbackups-remote'],
        ],
    }
}
