# == Class puppetmaster::puppetdb::database
#
# Sets up the postgresql database
#
# === Parameters
# [*master*] is the master server fqdn
#
# [*pgversion*] The postgresql version.
#
# [*shared_buffers*] The size of the postgresql shared buffer to use
#
# [*replication_pass*] The replication password
#
# [*puppetdb_pass*] Password for the puppetdb user,
#
# [*puppetdb_users*] Hash of users to create (if any), additionally to the local ones
#
class puppetmaster::puppetdb::database(
    String            $master,
    Numeric           $pgversion,
    String            $shared_buffers,
    String            $replication_pass,
    String            $puppetdb_pass,
    String            $log_line_prefix            = '%t ',
    Optional[String]  $ssldir                     = undef,
    Hash              $puppetdb_users             = {},
    Optional[Integer] $log_min_duration_statement = undef,
) {
    unless $pgversion in  [9.6, 11] {
        fail("Unsupported pgversion: ${pgversion}")
    }
    # Tuning
    file { "/etc/postgresql/${pgversion}/main/tuning.conf":
        ensure  => 'present',
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        content => template('puppetmaster/puppetdb/tuning.conf.erb'),
        require => Package["postgresql-${pgversion}"]
    }

    sysctl::parameters { 'postgres_shmem':
        values => {
            # That is derived after tuning postgresql, deriving automatically is
            # not the safest idea yet.
            'kernel.shmmax' => 8388608000,
        },
    }

    $on_master = ($master == $::fqdn)
    if $on_master {
        class { 'postgresql::master':
            includes                   => ['tuning.conf'],
            root_dir                   => '/srv/postgres',
            use_ssl                    => true,
            ssldir                     => $ssldir,
            log_line_prefix            => $log_line_prefix,
            log_min_duration_statement => $log_min_duration_statement,
        }
    } else {
        class { 'postgresql::slave':
            includes         => ['tuning.conf'],
            master_server    => $master,
            root_dir         => '/srv/postgres',
            replication_pass => $replication_pass,
            use_ssl          => true,
        }
    }

    # Postgres users
    $puppetdb_users.each |$pg_name, $config| {
        # TODO: make this more flexible?
        $pass = $config['attrs'] ? {
            'REPLICATION' => $replication_pass,
            default       => $puppetdb_pass,
        }

        $additional_config = {'master' => $on_master, 'pgversion' => $pgversion, 'password' => $pass}
        $actual_config = merge($config, $additional_config)

        postgresql::user { $pg_name:
            * => $actual_config
        }
    }
    # Create the puppetdb user for localhost
    # This works on every server and is used for read-only db lookups
    postgresql::user { 'puppetdb@localhost':
        ensure    => present,
        user      => 'puppetdb',
        database  => 'puppetdb',
        password  => $puppetdb_pass,
        cidr      => "${::ipaddress}/32",
        pgversion => $pgversion,
        master    => $on_master,
    }

    postgresql::user { 'prometheus@localhost':
        user     => 'prometheus',
        database => 'postgres',
        type     => 'local',
        method   => 'peer',
    }

    # Create the database
    postgresql::db { 'puppetdb':
        owner   => 'puppetdb',
    }

    exec { 'create_tgrm_extension':
        command => '/usr/bin/psql puppetdb -c "create extension pg_trgm"',
        unless  => '/usr/bin/psql puppetdb -c \'\dx\' | /bin/grep -q pg_trgm',
        user    => 'postgres',
        require => Postgresql::Db['puppetdb'],
    }
}
