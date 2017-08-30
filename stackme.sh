#!/bin/bash

FWAAS_PATCH=""
FWAAS_DASHBOARD_PATCH=""

# Quick sanity check (should be run on Ubuntu 16.04 and MUST be run as root directly)
if [ `lsb_release -rs` != "16.04" ]
then
  echo -n "Warning: This script is only tested against Ubuntu xenial. Press <enter> to continue at your own risk... "
  read
fi
if [ `whoami` != "root" -o -n "$SUDO_COMMAND" ]
then
  echo "This script must be run as root, and not using 'sudo'!"
  exit 1
fi

# Set up the packages we need
apt-get update
apt-get install git vim jq -y

# Clone the devstack repo
git clone https://github.com/openstack-dev/devstack.git /tmp/devstack

wget -O - https://raw.githubusercontent.com/xgerman/devstack_deploy/master/local.conf > /tmp/devstack/local.conf

# Create the stack user
/tmp/devstack/tools/create-stack-user.sh

# Apparently the group for libvirt changed to libvirtd in parallels?
usermod -a -G libvirtd stack

# Move everything into place
mv /tmp/devstack /opt/stack/
chown -R stack:stack /opt/stack/devstack/

cat >>/opt/stack/.profile <<EOF
# Prepare patches for local.conf
export FWAAS_PATCH="$FWAAS_PATCH"
export FWAAS_DASHBOARD_PATCH="$FWAAS_DASHBOARD_PATCH"
EOF

# Precreate .cache so it won't have the wrong perms
su - stack -c 'mkdir /opt/stack/.cache'

# Let's rock
su - stack -c /opt/stack/devstack/stack.sh

# Immediately delete spurious o-hm default route
route > ~/routes.log
route del default gw 192.168.0.1 &> /dev/null

# Install tox globally
pip install tox &> /dev/null

# Install Dashboard
git clone https://github.com/openstack/neutron-fwaas-dashboard
cd neutron-fwaas-dashboard
git fetch https://git.openstack.org/openstack/neutron-fwaas-dashboard FWAAS_DASHBOARD_PATCH && git checkout FETCH_HEAD
pip install .
rm /opt/stack/horizon/openstack_dashboard/local/enabled/*_project_firewalls_v2_panel.py*
cp neutron_fwaas_dashboard/enabled/_70*_project_firewalls*.py  /opt/stack/horizon/openstack_dashboard/local/enabled/
service apache2 restart
# Drop into a shell
su - stack
