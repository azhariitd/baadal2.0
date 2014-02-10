function run
{
  check_root

  package_install dnsmasq

  libvirt_install
  virtmanager_install
    
  libvirtd -d 1>>$LOGS/log.out 2>>$LOGS/log.err

  dns_get

  ovsvsctl_del_br $OVS_BRIDGE_EXTERNAL
  ovsvsctl_del_br $OVS_BRIDGE_INTERNAL

	ovsvsctl_add_br $OVS_BRIDGE_EXTERNAL

  config_get INTERFACE
	ovsvsctl_add_port $OVS_BRIDGE_EXTERNAL $INTERFACE
  ovsvsctl_add_br $OVS_BRIDGE_INTERNAL

  ovsvsctl_set_port $OVS_BRIDGE_INTERNAL "tag=1"

  ifconfig $INTERFACE 0
  ifconfig_dhcp $OVS_BRIDGE_EXTERNAL

  config_get NETWORK_INTERNAL_IP_SANDBOX
  ifconfig_ip $OVS_BRIDGE_INTERNAL $NETWORK_INTERNAL_IP_SANDBOX $VLAN_NETMASK

  file_backup /etc/network/interfaces
  
  interfaces_str=" auto lo\n
  iface lo inet loopback\n
  up service openvswitch-switch restart\n
  \n
  auto $OVS_BRIDGE_EXTERNAL\n
  iface $OVS_BRIDGE_EXTERNAL inet dhcp\n
  \n
  auto $INTERFACE\n
  iface $INTERFACE inet static\n
  address 0.0.0.0\n
  \n
  auto $OVS_BRIDGE_INTERNAL\n
  iface $OVS_BRIDGE_INTERNAL inet static\n
  address $NETWORK_INTERNAL_IP_SANDBOX\n
  netmask $VLAN_NETMASK\n
  "
  echo -e $interfaces_str > /etc/network/interfaces

  virsh_force "net-destroy $OVS_NET_INTERNAL"
  virsh_force "net-undefine $OVS_NET_INTERNAL"
	virsh_run "net-define $OVS_NET_XML_INTERNAL"
	virsh_run "net-start $OVS_NET_INTERNAL"
	virsh_run "net-autostart $OVS_NET_INTERNAL"

  virsh_force "net-destroy $OVS_NET_EXTERNAL"
  virsh_force "net-undefine $OVS_NET_EXTERNAL"
	virsh_run "net-define $OVS_NET_XML_EXTERNAL"
	virsh_run "net-start $OVS_NET_EXTERNAL"
	virsh_run "net-autostart $OVS_NET_EXTERNAL"

  config_get NETWORK_INTERNAL
  config_get NETWORK_INTERNAL_IP_SANDBOX
  config_get NETWORK_INTERNAL_IP_CONTROLLER
  config_get NETWORK_INTERNAL_IP_NAT
  config_get NETWORK_INTERNAL_IP_FILER

  $ECHO_PROGRESS "dnsmasq"
  
  # Not really a good idea
  killall dnsmasq 2>/dev/null

  dnsmasq \
    --listen-address=$NETWORK_INTERNAL_IP_SANDBOX \
    --bind-interfaces \
    --dhcp-mac=nat,$MAC_NAT \
    --dhcp-host=$MAC_CONTROLLER,$NETWORK_INTERNAL_IP_CONTROLLER \
    --dhcp-host=$MAC_NAT,$NETWORK_INTERNAL_IP_NAT \
    --dhcp-host=$MAC_FILER,$NETWORK_INTERNAL_IP_FILER \
    --dhcp-option=6,$dns \
    --dhcp-option=nat,option:router,0.0.0.0 \
    --dhcp-option=3,$NETWORK_INTERNAL_IP_GATEWAY \
    --dhcp-range=$NETWORK_INTERNAL,static
  status=$?

  if [[ $status -ne 0 ]]; then
    $ECHO_ER dnsmasq \(check logs\)
    tail -$LOG_SIZE $LOGS/log.err 
    exit 1
  else
    $ECHO_OK dnsmasq
  fi

  $ECHO_OK Switch Installation Complete
}

function dns_get
{
  if [[ $DNS != '' ]]; then
    dns=$DNS
  else
    dns=$(cat /var/run/dnsmasq/resolv.conf | sed "s:nameserver ::g")
  fi

  package_install ipcalc
  ipcalc -b $dns | tee -a $LOGS/log.err | grep INVALID\ ADDRESS 1>>$LOGS/log.out
  status=$?

  if [[ $status -eq 0 ]]; then
    $ECHO_ER Failed to retrieve DNS info from sandbox system \(check logs\) OR \
      manually specify DNS as \'make switch DNS=a.b.c.d\'
    tail -15 $LOGS/log.err
    exit 1
  else
    $ECHO_OK DNS = $dns
  fi
}
