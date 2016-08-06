#
# Cookbook Name:: bcpc
# Recipe:: openstack
#
# Copyright 2013, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "bcpc::default"

package "ubuntu-cloud-keyring" do
    action :upgrade
end

apt_repository "openstack" do
    uri node['bcpc']['repos']['openstack']
    distribution "#{node['lsb']['codename']}-#{node['bcpc']['openstack_branch']}/#{node['bcpc']['openstack_release']}"
    components ["main"]
end

%w{ python-novaclient
    python-cinderclient
    python-glanceclient
    python-nova
    python-memcache
    python-keystoneclient
    python-nova-adminclient
    python-heatclient
    python-ceilometerclient
    python-mysqldb
    python-six
    python-ldap
}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

%w{hup_openstack logwatch}.each do |script|
    template "/usr/local/bin/#{script}" do
        source "#{script}.erb"
        mode 0755
        owner "root"
        group "root"
        variables(:servers => get_head_nodes)
    end
end

cookbook_file "/tmp/heatclient.patch" do
    source "heatclient.patch"
    owner "root"
    mode 0644
end

bash "patch-for-heatclient-bugs" do
    user "root"
    code <<-EOH
        cd /usr/lib/python2.7/dist-packages/heatclient
        patch < /tmp/heatclient.patch
        rv=$?
        if [ $rv -ne 0 ]; then
          echo "Error applying patch ($rv) - aborting!"
          exit $rv
        fi
        cp /tmp/heatclient.patch .
    EOH
    not_if "test -f /usr/lib/python2.7/dist-packages/heatclient/heatclient.patch"
end
