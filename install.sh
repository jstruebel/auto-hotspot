#!/bin/bash
interfaceWifi=wlan0
interfaceWired=eth0
ipAddress=192.168.4.1/24

### Check if run as root ############################
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root" 
	echo "Try \"sudo $0\""	
	exit 1
fi
	
## Change over to systemd-networkd
## https://raspberrypi.stackexchange.com/questions/108592
# deinstall classic networking
apt --autoremove -y purge ifupdown dhcpcd5 isc-dhcp-client isc-dhcp-common rsyslog
apt-mark hold ifupdown dhcpcd5 isc-dhcp-client isc-dhcp-common rsyslog raspberrypi-net-mods openresolv
rm -r /etc/network /etc/dhcp

# setup/enable systemd-resolved and systemd-networkd
apt --autoremove -y purge avahi-daemon
apt-mark hold avahi-daemon libnss-mdns
apt install -y libnss-resolve
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-networkd.service systemd-resolved.service

## Install configuration files for systemd-networkd
cat > /etc/systemd/network/04-${interfaceWired}.network <<-EOF
	[Match]
	Name=$interfaceWired
	[Network]
	DHCP=yes
	MulticastDNS=yes
EOF

cat > /etc/systemd/network/08-${interfaceWifi}-CLI.network <<-EOF
	[Match]
	Name=$interfaceWifi
	[Network]
	DHCP=yes
	LinkLocalAddressing=yes
	MulticastDNS=yes
EOF
		
cat > /etc/systemd/network/12-${interfaceWifi}-AP.network <<-EOF
	[Match]
	Name=$interfaceWifi
	[Network]
	Address=$ipAddress
	IPForward=yes
	IPMasquerade=yes
	DHCPServer=yes
	LinkLocalAddressing=yes
	MulticastDNS=yes
	[DHCPServer]
	DNS=84.200.69.80 84.200.70.40 1.1.1.1
EOF

cp $(pwd)/auto-hotspot /usr/local/sbin/
chmod +x /usr/local/sbin/auto-hotspot

## Install systemd-service to configure interface automatically
if [ ! -f /etc/systemd/system/wpa_cli@${interfaceWifi}.service ] ; then
	cat > /etc/systemd/system/wpa_cli@${interfaceWifi}.service <<-EOF
		[Unit]
		Description=Wpa_cli to Automatically Create an Accesspoint if no Client Connection is Available
		After=wpa_supplicant@%i.service
		BindsTo=wpa_supplicant@%i.service
		[Service]
		ExecStart=/sbin/wpa_cli -i %I -a /usr/local/sbin/auto-hotspot
		Restart=on-failure
		RestartSec=1
		[Install]
		WantedBy=multi-user.target
	EOF
else
  echo "wpa_cli@$interfaceWifi.service is already installed"
fi

systemctl daemon-reload
systemctl enable wpa_cli@${interfaceWifi}.service

hostName=$(hostname -s)

## Configure wpa_supplicant.conf file
if [ ! -f /etc/wpa_supplicant/wpa_supplicant-${interfaceWifi}.conf ] ; then
	if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ] ; then
		cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-${interfaceWifi}.conf
	else
		cat > /etc/wpa_supplicant/wpa_supplicant-${interfaceWifi}.conf <<-EOF
			update_config=1
			country=US
		
			network={
			    priority=0
			    ssid="${hostName}"
			    mode=2
			    key_mgmt=WPA-PSK
			    psk="PiBotAccessPoint"
			    frequency=2462
			}
		EOF
	fi
fi

if ! grep -Fq "ssid=\"${hostName}\"" /etc/wpa_supplicant/wpa_supplicant-${interfaceWifi}.conf ; then
	sed -i "s|network={|network={\n    priority=0\n    ssid=\"${hostName}\"\n    mode=2\n    key_mgmt=WPA-PSK\n    psk=\"PiBotAccessPoint\"\n    frequency=2462\n}\n\nnetwork={|" /etc/wpa_supplicant/wpa_supplicant-${interfaceWifi}.conf
fi


echo "Reboot now!"
exit 0
