#!/bin/bash
# Assumptions: This script assumes that you will be using the root user to manage kvm. For now, to customize for your user, replace root below with your username.
yum install kvm kmod-kvm libvirt qemu virt-manager -y
modprobe kvm-intel
lsmod | grep kvm
usermod -G kvm -a root
groups root
chown root:kvm /dev/kvm
chmod 0660 /dev/kvm
chkconfig libvirtd on
service libvirtd start
