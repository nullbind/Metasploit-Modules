# Super crappy VLAN hopper bf
# Note: Manually change timeout to 2 in /etc/dhcp/dhclient.conf
modprobe 8021q
for i in {1..600}
do 
 echo "Adding interface $i..."
 vconfig add eth0 $i
 `ifconfig eth0.$i up`
 
 echo "Attempting DHCP for VLAN  $i..."
 `dhclient eth0.$i`
done
