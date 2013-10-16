#!/bin/bash
# script is configured to use the root user
yum install kvm kmod-kvm libvirt qemu virt-manager -y
modprobe kvm-intel
lsmod | grep kvm
usermod -G kvm -a root
groups root
chown root:kvm /dev/kvm
chmod 0660 /dev/kvm
chkconfig libvirtd on
service libvirtd start
