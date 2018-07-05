# == define mediawiki::site
#
# Defines a simple file that can be included in the mediawiki
# apache configuration. This will allow us to convert our sites to using mediawiki::vhost one by one
# if needed (while allowing us to see a diff in the puppet compiler).
#
# This define is transitional and should NOT be used outside of the mediawiki::web hierarchy
define mediawiki_exp::web::site() {
    file { "/etc/apache2/sites-available/${title}.conf":
        content => template("mediawiki_exp/apache/sites/included/${title}.conf.erb"),
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        notify  => Service['apache2'],
        require => Package['apache2'],
    }
}
