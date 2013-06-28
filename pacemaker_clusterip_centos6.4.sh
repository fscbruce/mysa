#!/bin/sh
#######################################################################
#                                                                     #
#   Script written by Bruce Dargus for Xchanging Malaysia Sdn. Bhd.   #
#                                                                     #
#######################################################################

# Project Title: pacemaker_clusterip_centos6.4.sh
# Requirements: CentOS 6.4 (tested on x64 minimal install), network configuration, internet access
# Purpose: This script is intended create a cluster from two CentOS 6.4 machines and create the resources necessary for a shared cluster IP (ocf:heartbeat:IPaddr2), high-availability webserving (ocf:heartbeat:apache), and drbd file replication (ocf:linbit:drbd).

clear
_Usage='usage: script <cluster name> <node1 hostname> <node1 ip> <node2 hostname> <node2 ip> <Cluster IP (optional)> <Cluster IP Netmask Prefix without slash  (optional)>'
echo "Pacemaker installation on CentOS 6.4 x64"
echo "Script by Bruce Dargus for Xchanging Malaysia Sdn. Bhd. | 2013-06-24"
echo
echo "Current system is `uname -or`"
echo

[ $# -eq 0 ] && echo $_Usage && echo && exit
[ -z "$2" ] && echo $_Usage && echo && exit
[ -z "$3" ] && echo $_Usage && echo && exit
[ -z "$4" ] && echo $_Usage && echo && exit
[ -z "$5" ] && echo $_Usage && echo && exit

#Define variables
#echo "We will now gather required information by asking you a series of questions."
#echo ""

echo "Cluster will be created: $1"
echo "Node 1 hostname has been set to: $2"
echo "Node 1 ip address has been set to: $3"
echo "Node 2 hostname has been set to: $4"
echo "Node 2 ip address has been set to: $5"
[ -z "$6" ] || [ -z "$7" ] || echo "ClusterIP resource will be created: $6 /$7"
echo "Proceed with installation?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No ) exit;;
    esac
done

#Distribution maintenance
echo "Performing distribution maintenance..."
yum update -y

#Installation of basic tools
echo "Installing basic tools..."
yum install pacemaker ccs pcs cman resource-agents wget man links nano dstat ntsysv -y

echo "Cluster preflight..."
	#Add node entries to hosts file
	echo -n "   Adding node entries to hosts file..."
	echo "$3 $2" >> /etc/hosts
	echo "$5 $4" >> /etc/hosts
	echo "done."

	#Creation of cluster.conf
	echo "   Creating cluster.conf..."
	ccs -f /etc/cluster/cluster.conf --create $1
	echo -n "      " && ccs -f /etc/cluster/cluster.conf --addnode $2
	echo -n "      " && ccs -f /etc/cluster/cluster.conf --addnode $4
	ccs -f /etc/cluster/cluster.conf --addfencedev pcmk agent=fence_pcmk
	echo -n "      " && ccs -f /etc/cluster/cluster.conf --addmethod pcmk-redirect $2
	echo -n "      " && ccs -f /etc/cluster/cluster.conf --addmethod pcmk-redirect $4
	ccs -f /etc/cluster/cluster.conf --addfenceinst pcmk $2 pcmk-redirect port=$2
	ccs -f /etc/cluster/cluster.conf --addfenceinst pcmk $4 pcmk-redirect port=$4

#Configure firewall for CoroSync pass-through (According to Red Hat Cluster Suite Requirements)
echo "Configure Linux firewall pass-through for cluster services?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "   Configuring Linux firewall pass-through for cluster services..." && iptables -I INPUT 1 --protocol udp --dport 5405 -j ACCEPT && iptables -I INPUT 1 --protocol udp --sport 5404 -j ACCEPT && iptables -I OUTPUT 1 --protocol udp --dport 5405 -j ACCEPT && iptables -I OUTPUT 1 --protocol udp --sport 5404 -j ACCEPT && iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 11111 -j ACCEPT && iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 21064 -j ACCEPT && echo -n "      " && service iptables save && break;;
        No ) break;;
    esac
done

	#Disable quorum
	echo "   Disabling quorum..."
	echo "CMAN_QUORUM_TIMEOUT=0" >> /etc/sysconfig/cman

#Launch cluster services
echo "Launching cluster services..."
service cman start > /dev/null
service pacemaker start

while [[ "$cmancheck" != "cluster is running." ]]
do
cmancheck=`service cman status`
sleep 3
service cman start > /dev/null
done
echo -e "\nCluster framework has arrived."

echo -n "Allowing services to coalesce, please be patient..."

while [[ "$pacemakercheck" != "pacemakerd"*"is running..." ]]
do
pacemakercheck=`service pacemaker status`
sleep 3
service pacemaker start > /dev/null
echo -n "..."
done
echo -e "\nServices have coalesced."

echo -n "Bringing node online"
while [[ "$onlinecheck" != "Online: ["* ]]
do
onlinecheck=`pcs status | grep -i online`
echo -n "."
sleep 1
done
echo -e "\nNode: `hostname` is now online."

#Disable irrelevant policies for two-node setup
echo 'Optimize policies for dual-node setup (not normally necessary more than once per cluster)?'
select yn in "Yes" "No"; do
    case $yn in
        Yes ) bash -c "pcs property set stonith-enabled=false && pcs property set no-quorum-policy=ignore && pcs property set migration-threshold=1" && break;;
        No ) break;;
    esac
done

#Create ClusterIP Resource
[ -z "$6" ] || [ -z "$7" ] || echo "Creating ClusterIP service, please be patient..." && bash -c "pcs resource create ClusterIP ocf:heartbeat:IPaddr2 ip=$6 cidr_netmask=$7 op monitor interval=10s"
#[ -z "$6" ] || [ -z "$7" ] || pcs resource create ClusterIP ocf:heartbeat:IPaddr2 ip=$6 cidr_netmask=$7 op monitor interval=30s

#Adding pacemaker to startup
echo "Setting pacemaker to autostart on boot."
chkconfig pacemaker on

echo "Cluster configuration is complete."

echo 'Install Apache web server and configure for firewall pass-through?'
select yn in "Yes" "No"; do
    case $yn in
        Yes ) bash -c "yum install -y httpd && iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 80 -j ACCEPT && iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 443 -j ACCEPT && iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited && iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited && service iptables save" && bash -c "echo '<Location /server-status>' >> /etc/httpd/conf/httpd.conf && echo 'SetHandler server-status' >> /etc/httpd/conf/httpd.conf && echo 'Order deny,allow' >> /etc/httpd/conf/httpd.conf && echo 'Deny from all' >> /etc/httpd/conf/httpd.conf && echo 'Allow from 127.0.0.1' >> /etc/httpd/conf/httpd.conf && echo '</Location>' >> /etc/httpd/conf/httpd.conf" && break;;
        No ) break;;
    esac
done

echo 'Install Apache web server as cluster resource?'
select yn in "Yes" "No"; do
    case $yn in
        Yes ) bash -c 'pcs resource create httpdc ocf:heartbeat:apache configfile=/etc/httpd/conf/httpd.conf op monitor interval=10s' && break;;
        No ) break;;
    esac
done

#echo 'Configure preferred node for services?'
#select prefnode in "No" "$2" "$4"; do
#    case $prefnode in
#        "No" ) break;;
#        "$2" ) break;;
#        "$4" ) break;;
#    esac
#done
#[ $prefnode == "$2" ] && pcs resource move httpdc "$2" && pcs resource move ClusterIP "$2" 
#[ $prefnode == "$4" ] && pcs resource move httpdc "$4" && pcs resource move ClusterIP "$4" 

echo "Download and install DRBD 8.4.3 kernel module from source?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) bash -c "/bin/mkdir -p /tmp/drbdinst && /usr/bin/wget --directory-prefix=/tmp/drbdinst/ http://oss.linbit.com/drbd/8.4/drbd-8.4.3.tar.gz && cd /tmp/drbdinst && /bin/tar xfzp drbd-8.4.3.tar.gz && cd drbd-8.4.3 && /usr/bin/yum -y install kernel\`uname -r| grep -o '5PAE\\|5xen\\|5debug'|tr 5 -\`-devel-\`uname -r|sed 's/\\(PAE\\|xen\\|debug\\)\$//'\` &&/usr/bin/yum -y install flex gcc make && if [ -e configure ]; then ./configure --with-pacemaker --prefix=/usr --with-km --localstatedir=/var --sysconfdir=/etc; fi && make && make install DESTDIR=/ && /bin/rm -rf /tmp/drbdinst && modprobe drbd && echo 'Done.'" && break;;
        No ) break;;
    esac
done

echo "End of script. Send feedback to bd@dargus.co.uk, thanks."
