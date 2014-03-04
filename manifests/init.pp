# Class: jbossMaster
#
# This module manages jbossMaster
#
# Parameters: none
#
# Actions:
#
# Requires: see Modulefile
#
# Sample Usage:
#
class odaijbossmasterbb (
  $package_url             = "http://",
  $bind_address            = $::ipaddress,
  $deploy_dir              = "/opt/jboss",
  $mode                    = "domain",
  $bind_address_management = $::ipaddress,
  $bind_address_unsecure   = $::ipaddress,
  # $domain_role             = 'master',
  $admin_user              = 'admin',
  $admin_user_password     = hiera('jbossadminpwdbb', ""),) {
  $teiidjboss = hiera('teiidjboss', undef)
  $teiid_version = "8.5"

  package { 'unzip': ensure => present, }

  class { 'opendai_java':
    distribution => 'jdk',
    version      => '6u25',
    repos        => $package_url,
  }

  class { 'jbossas':
    package_url             => "http://$package_url/",
    bind_address            => $bind_address,
    deploy_dir              => $deploy_dir,
    mode                    => $mode,
    version                 => 'EAP6.1.a',
    bind_address_management => $bind_address_management,
    bind_address_unsecure   => $bind_address_unsecure,
    domain_master_address   => $::ipaddress,
    role                    => 'master',
    admin_user              => $admin_user,
    admin_user_password     => $admin_user_password,
    require                 => [Class['opendai_java'], Package['unzip']],
    before                  => Anchor['odaijbossmaster:master_installed'],
  }

  jbossas::add_user { $admin_user:
    password => $admin_user_password,
    require  => [Class['jbossas']],
    before   => Anchor['odaijbossmaster:master_installed'],
  }

  # @@odaijbossslavebb::setMaster{'setMasterIP':
  #  ip_master => $::ipaddress,
  #  tag      => $teiidjboss["tag"],
  #  before     => Anchor['odaijbossmaster:master_installed'],
  #}

  anchor { 'odaijbossmaster:master_installed': }

  # now wait for jboss to start
  # curl --digest -L -D - http://admin:opendaiadmin@10.1.1.77:9990/management --header "Content-Type: application/json" -d
  # '{"operation":"read-attribute","name":"release-codename","json.pretty":1}'

  exec { 'check_jboss_service_running':
    command   => "/usr/bin/curl --digest -L -D - http://${admin_user}:${admin_user_password}@${bind_address_management}:9990/management --header \"Content-Type: application/json\" -d '{\"operation\":\"read-attribute\",\"name\":\"release-codename\",\"json.pretty\":1}'",
    logoutput => true,
    tries     => 4,
    try_sleep => 30,
    require   => [Class['jbossas'], Anchor['odaijbossmaster:master_installed']],
  }

  # ########### Setting info for slaves
  # @@jbossas::set_domain_controller { 'jbslave':
  #   deploy_dir => "/opt/jboss",
  # #   deploy_dir => "/opt/jboss",
  #    require    => [Class['jbossas']],
  #    tag        => "domain_controller_jbslave"
  #  }

  Jbossas::Add_user <<| tag == $teiidjboss["user_tag"] |>>

  notice("now create server_groups")

  # need to add the server groups for TEIID, Geoserver and R2RQ

  jbossas::add_server_group { 'teiid-server-group':
    profile              => "ha",
    socket_binding_group => "ha-sockets",
    offset               => "0",
    deploy_dir           => $deploy_dir,
    require              => [Exec['check_jboss_service_running']],
  }

  notice("now create jvm into server_groups")

  jbossas::add_jvm_server_group { 'teiid-server-group':
    heap_size     => "128m",
    max_heap_size => "1024m",
    deploy_dir    => $deploy_dir,
    require       => [Jbossas::Add_server_group['teiid-server-group']],
  }

  notice("now create server")

  #
  jbossas::add_server { 'teiid1':
    jbhost_name  => "master",
    server_group => "teiid-server-group",
    autostart    => "true",
    require      => [Jbossas::Add_jvm_server_group['teiid-server-group']],
  }

  jbossas::run_cli_command { 'set_teiid_multicast':
    command        => "/server-group=teiid-server-group/system-property=jboss.default.multicast.address:add(value=${teiidjboss["multicast_teiid"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"teiid-server-group\"},{\"system-property\":\"jboss.default.multicast.address\"}]",
    require        => [Jbossas::Add_jvm_server_group['teiid-server-group']]
  }

  jbossas::run_cli_command { 'set_teiid_lbgroup':
    command        => "/server-group=teiid-server-group/system-property=mycluster.modcluster.lbgroup:add(value=${teiidjboss["lbgroup_teiid"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"teiid-server-group\"},{\"system-property\":\"mycluster.modcluster.lbgroup\"}]",
    require        => [Jbossas::Add_jvm_server_group['teiid-server-group']]
  }

  jbossas::run_cli_command { 'set_teiid_balancer':
    command        => "/server-group=teiid-server-group/system-property=mycluster.modcluster.balancer:add(value=${teiidjboss["balancer"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"teiid-server-group\"},{\"system-property\":\"mycluster.modcluster.balancer\"}]",
    require        => [Jbossas::Add_jvm_server_group['teiid-server-group']]
  }
  # Install TEIID
  $dist_file = "teiid-${teiid_version}.0.Final-jboss-dist.zip"
  $file_url = "http://$package_url/"

  exec { 'download_teiid':
    command   => "/usr/bin/curl -v --progress-bar -o '/tmp/${dist_file}' '${file_url}${dist_file}'",
    creates   => "/tmp/${dist_file}",
    user      => 'jbossas',
    logoutput => true,
    require   => [Package['curl'], Jbossas::Add_server['teiid1']],
  }
  notice("${jbossas::deploy_dir}/${dist_file}")

  # Extract the TEIID distribution
  jbossas::extract_in_jboss { 'teiid':
    source  => "/tmp/${dist_file}",
    creates => "bin/scripts/teiid-domain-mode-install.cli",
    require => [Exec['download_teiid']],
  }
  notice("/tmp/${dist_file}")

  jbossas::install_teiid_domain { "teiid-server-group":
    require => Jbossas::Extract_in_jboss['teiid'],
    version => '8.5',
    before  => Anchor['odaijbossmaster:teiid_installed'],
  }

  # Install MySQL driver
  $mysql_file = 'mysql-connector-java-5.1.22-bin.jar'

  jbossas::add_jdbc_module { 'mysql':
    driver     => 'mysql-connector-java-5.1.22-bin.jar',
    driver_url => $file_url,
    profile    => 'ha',
    require    => [Class['jbossas'], Anchor['odaijbossmaster:master_installed']]
  }

  jbossas::add_jdbc_module { 'postgresql':
    driver     => 'postgresql-9.2-1002.jdbc4.jar',
    driver_url => $file_url,
    profile    => 'ha',
    require    => [Class['jbossas'], Anchor['odaijbossmaster:master_installed']]
  }

  jbossas::add_jdbc_module { 'oracle':
    driver     => 'ojdbc14.jar',
    driver_url => $file_url,
    profile    => 'ha',
    require    => [Class['jbossas'], Anchor['odaijbossmaster:master_installed']]
  }

  # mod_cluster stuff
  # set the name in the web subsystem so that the correct name is displayed in the proxy
  jbossas::run_cli_command { "set_ha_web_name":
    command => '/profile=ha/subsystem=web:write-attribute(name=instance-id,value="${jboss.node.name}")',
    require => Jbossas::Add_server['teiid1']
  }
  Jbossas::Set_mod_cluster <<| tag == $teiidjboss["mod_cluster_tag"] |>>

  # Install TEIID consolle
  $consolle_file = 'teiid-console-dist-1.1.0-Final-jboss-as7.zip'

  exec { 'download_teiid_consolle':
    command   => "/usr/bin/curl -v --progress-bar -o '/tmp/${consolle_file}' '${file_url}${consolle_file}'",
    creates   => "/tmp/${consolle_file}",
    user      => 'jbossas',
    logoutput => true,
    require   => [Package['curl'], Jbossas::Add_server['teiid1']],
  }

  # Extract the TEIID distribution
  jbossas::extract_in_jboss { 'teiid_consolle':
    source  => "/tmp/${consolle_file}",
    creates => "modules/system/layers/base/org/jboss/as/console/teiid/teiid-console-1.1.0.Final-resources.jar",
    require => [Exec['download_teiid_consolle']],
    before  => Anchor['odaijbossmaster:teiid_installed'],
  }

  # jbossas::run_cli_file { 'teiid-domain-mode-install.cli':
  #   path    => 'bin/scripts/',
  #   require => Jbossas::Extract_in_jboss['teiid'],
  #}

  #
  #  exec { 'extract_teiid':
  #    command   => "/bin/tar -xz -f '$dist_file'",
  #    creates   => "${jbossas::deploy_dir}",
  #    cwd       => $deploy_dir,
  #    user      => 'jbossas',
  #    group     => 'jbossas',
  #    logoutput => true,
  #    #       unless => "/usr/bin/test -d '$jbossas::deploy_dir'",
  #    require   => [Group['jbossas'], User['jbossas'], Exec['download_teiid']]
  #  }
  anchor { 'odaijbossmaster:teiid_installed': }

  jbossas::add_server_group { 'geo-server-group':
    profile              => "ha",
    socket_binding_group => "ha-sockets",
    offset               => "200",
    deploy_dir           => $deploy_dir,
    require              => [[Exec['check_jboss_service_running']], Anchor['odaijbossmaster:teiid_installed']],
  }

  notice("now create jvm into server_group geo")

  jbossas::add_jvm_server_group { 'geo-server-group':
    heap_size     => "128m",
    max_heap_size => "1024m",
    deploy_dir    => $deploy_dir,
    require       => [Jbossas::Add_server_group['geo-server-group']],
  }

  notice("now create server geo1")

  jbossas::add_server { 'geo1':
    jbhost_name  => "master",
    server_group => "geo-server-group",
    autostart    => "true",
    port_offset  => "200",
    require      => [Jbossas::Add_jvm_server_group['geo-server-group']],
  }

  jbossas::run_cli_command { 'set_geo_multicast':
    command        => "/server-group=geo-server-group/system-property=jboss.default.multicast.address:add(value=${teiidjboss["multicast_geo"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"geo-server-group\"},{\"system-property\":\"jboss.default.multicast.address\"}]",
    require        => [Jbossas::Add_jvm_server_group['geo-server-group']]
  }

  jbossas::run_cli_command { 'set_geo_lbgroup':
    command        => "/server-group=geo-server-group/system-property=mycluster.modcluster.lbgroup:add(value=${teiidjboss["lbgroup_geo"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"geo-server-group\"},{\"system-property\":\"mycluster.modcluster.lbgroup\"}]",
    require        => [Jbossas::Add_jvm_server_group['geo-server-group']]
  }

  jbossas::run_cli_command { 'set_geo_balancer':
    command        => "/server-group=geo-server-group/system-property=mycluster.modcluster.balancer:add(value=${teiidjboss["balancer"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"geo-server-group\"},{\"system-property\":\"mycluster.modcluster.balancer\"}]",
    require        => [Jbossas::Add_jvm_server_group['geo-server-group']]
  }

  # Install GeoServer
  $geoserver_file = 'geoserver.war'

  exec { 'download_geoserver':
    command   => "/usr/bin/curl -v --progress-bar -o '/tmp/${geoserver_file}' '${file_url}${geoserver_file}'",
    creates   => "/tmp/${geoserver_file}",
    user      => 'jbossas',
    logoutput => true,
    require   => [Package['curl'], Jbossas::Add_server["geo1"]],
  }

  jbossas::run_cli_command { 'deploy_geoserver':
    command        => "deploy --server-groups=geo-server-group /tmp/${geoserver_file}",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"deployment\":\"${geoserver_file}\"}]",
    require        => [Exec['download_geoserver']]
  }

  # system variables for GEOSERVER
  jbossas::run_cli_command { 'set_GWC_DISKQUOTA_DISABLED':
    command        => "/server-group=geo-server-group/system-property=GWC_DISKQUOTA_DISABLED:add(value=true,boot-time=true)",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"geo-server-group\"},{\"system-property\":\"GWC_DISKQUOTA_DISABLED\"}]",
    require        => [Exec['download_geoserver']]
  }

  jbossas::run_cli_command { 'set_GWC_METASTORE_DISABLED':
    command        => "/server-group=geo-server-group/system-property=GWC_METASTORE_DISABLED:add(value=true,boot-time=true)",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"geo-server-group\"},{\"system-property\":\"GWC_METASTORE_DISABLED\"}]",
    require        => [Exec['download_geoserver']]
  }

  # Add any other servers
  Jbossas::Add_server <<| tag == $teiidjboss["server_slave_tag"] |>>

  # mount NFS
  $geodata = '/var/geo_data'

  include nfs::client
  Nfs::Client::Mount <<| tag == 'nfs_geoserver' |>> {
    ensure  => 'mounted',
    mount   => $geodata,
    options => 'rw,sync,hard,intr',
    before  => Anchor['odaijbossmasterbb:nfs'],
  }

  anchor { 'odaijbossmasterbb:nfs': }

  exec { "geodata_ownership":
    command => "/bin/chown ${jbossas::params::jboss_group}:${jbossas::params::jboss_group} $geodata",
    require => Anchor['odaijbossmaster:nfs'],
  }

  # need to add the geodata dir from the cli
  jbossas::run_cli_command { 'set_GEOSERVER_DATA_DIR':
    command        => "/server-group=geo-server-group/system-property=GEOSERVER_DATA_DIR:add(value=$geodata,boot-time=true)",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"geo-server-group\"},{\"system-property\":\"GEOSERVER_DATA_DIR\"}]",
    require        => [Exec['download_geoserver']],
    before         => Anchor['odaijbossmaster:geo_installed'],
  }

  anchor { 'odaijbossmaster:geo_installed': }

  jbossas::add_server_group { 'd2rq-server-group':
    profile              => "ha",
    socket_binding_group => "ha-sockets",
    offset               => "400",
    deploy_dir           => $deploy_dir,
    require              => [[Exec['check_jboss_service_running']], Anchor['odaijbossmaster:teiid_installed']],
  }

  notice("now create jvm into server_group d2rq")

  jbossas::add_jvm_server_group { 'd2rq-server-group':
    heap_size     => "128m",
    max_heap_size => "1024m",
    deploy_dir    => $deploy_dir,
    require       => [Jbossas::Add_server_group['d2rq-server-group']],
  }

  notice("now create server d2rq1")

  jbossas::add_server { 'd2rq1':
    jbhost_name  => "master",
    server_group => "d2rq-server-group",
    autostart    => "true",
    port_offset  => "400",
    require      => [Jbossas::Add_jvm_server_group['d2rq-server-group']],
  }

  jbossas::run_cli_command { 'set_d2rq_multicast':
    command        => "/server-group=d2rq-server-group/system-property=jboss.default.multicast.address:add(value=${teiidjboss["multicast_d2rq"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"d2rq-server-group\"},{\"system-property\":\"jboss.default.multicast.address\"}]",
    require        => [Jbossas::Add_jvm_server_group['d2rq-server-group']]
  }

  jbossas::run_cli_command { 'set_d2rq_lbgroup':
    command        => "/server-group=d2rq-server-group/system-property=mycluster.modcluster.lbgroup:add(value=${teiidjboss["lbgroup_d2rq"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"d2rq-server-group\"},{\"system-property\":\"mycluster.modcluster.lbgroup\"}]",
    require        => [Jbossas::Add_jvm_server_group['d2rq-server-group']]
  }

  jbossas::run_cli_command { 'set_d2rq_balancer':
    command        => "/server-group=d2rq-server-group/system-property=mycluster.modcluster.balancer:add(value=${teiidjboss["balancer"]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"d2rq-server-group\"},{\"system-property\":\"mycluster.modcluster.balancer\"}]",
    require        => [Jbossas::Add_jvm_server_group['d2rq-server-group']]
  }

  # cleanup from standard servers
  jbossas::run_cli_command { 'set_server_one_autostart':
    command => "/host=master/server-config=server-one:write-attribute(name=auto-start,value=false)",
    require => [Exec['download_geoserver']]
  }

  jbossas::run_cli_command { 'set_server_two_autostart':
    command => "/host=master/server-config=server-two:write-attribute(name=auto-start,value=false)",
    require => [Exec['download_geoserver']]
  }

  Jbossas::Run_cli_command <<| tag == $teiidjboss["server_slave_tag"] |>>


# Configure Zabbix for JBoss
  $cmd1 = "UserParameter=jboss.web[*], curl --digest -D - 'http://${admin_user}:${admin_user_password}@${::ipaddress}:9990/management/' -d '{\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"profile\":\"ha\"},{\"subsystem\":\"web\"},{\"connector\":\"http\"}], \"json.pretty\":1}' -HContent-Type:application/json -s| grep \$1|sed 's/\( \)*\"\$1\" : \([0-9]*\),/\2/'"
  notice("$cmd1")
  exec { 'zabbix-agentd-jboss_mon1':
    command => '/bin/echo "$cmd1" >> /etc/zabbix/zabbix_agentd.conf',
    require => File['/etc/zabbix/zabbix_agentd.conf'],
    unless  => '/bin/grep -q apache.status /etc/zabbix/zabbix_agentd.conf',
  }
  exec { 'zabbix-agent-jboss_mon1':
    command => '/bin/echo "$cmd1" >> /etc/zabbix/zabbix_agent.conf',
    require => File['/etc/zabbix/zabbix_agent.conf'],
    unless  => '/bin/grep -q apache /etc/zabbix/zabbix_agent.conf',
  }
                                                                                                                                                                                                        #/host=master/server=app1/deployment=opendaiexport.war/subsystem=web/servlet=opendaiexport:read-resource(include-runtime=true)
$cmd2 = "UserParameter=jboss.servlet[*], curl --digest -D - 'http://${admin_user}:${admin_user_password}@${::ipaddress}:9990/management/' -d '{\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"host\":\"\$1\"},{\"server\":\"\$2\"},{\"deployment\":\"\$3\"},{\"subsystem\":\"web\"},{\"servlet\":\"\$4\"}], \"json.pretty\":1}' -HContent-Type:application/json -s| grep \$5|sed 's/\( \)*\"\$5\" : \([0-9]*\),/\2/'"
  notice("$cmd2")
  exec { 'zabbix-agentd-jboss_mon2':
    command => '/bin/echo "$cmd2" >> /etc/zabbix/zabbix_agentd.conf',
    require => File['/etc/zabbix/zabbix_agentd.conf'],
    unless  => '/bin/grep -q apache.status /etc/zabbix/zabbix_agentd.conf',
  }
  exec { 'zabbix-agent-jboss_mon2':
    command => '/bin/echo "$cmd2" >> /etc/zabbix/zabbix_agent.conf',
    require => File['/etc/zabbix/zabbix_agent.conf'],
    unless  => '/bin/grep -q apache /etc/zabbix/zabbix_agent.conf',
  }



}