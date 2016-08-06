#
# Cookbook Name:: bcpc
# Recipe:: cobalt
#
# Copyright 2013, Bloomberg Finance L.P.
# Copyright 2013, Gridcentric Inc.
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

if not node["bcpc"]["vms_key"].nil?
    apt_repository "cobalt" do
        uri node['bcpc']['repos']['gridcentric'] % ["cobalt", node['bcpc']['openstack_release']]
        distribution "gridcentric"
        components ["multiverse"]
        key "gridcentric.key"
    end

    apt_repository "cobaltclient" do
        uri node['bcpc']['repos']['gridcentric'] % ["cobaltclient", node['bcpc']['openstack_release']]
        distribution "gridcentric"
        components ["multiverse"]
        key "gridcentric.key"
    end

    apt_repository "vms" do
        uri node['bcpc']['repos']['gridcentric'] % [node['bcpc']['vms_key'], 'vms']
        distribution "gridcentric"
        components ["multiverse"]
        key "gridcentric.key"
    end

    package "cobalt-novaclient" do
        action :upgrade
        options "-o APT::Install-Recommends=0 -o Dpkg::Options::='--force-confnew'"
    end

    template "/etc/nova/cobalt-compute.conf" do
        source "cobalt-compute.conf.erb"
        owner "root"
        group "root"
        mode 00644
    end

    directory "/etc/sysconfig" do
        owner "root"
        group "root"
        mode 00755
    end

    template "/etc/sysconfig/vms" do
        source "vms.erb"
        owner "root"
        group "root"
        mode 00644
    end

    %w{vms vms-apparmor vms-rados vms-libvirt}.each do |pkg|
        package pkg do
            action :upgrade
            options "-o APT::Install-Recommends=0 -o Dpkg::Options::='--force-confnew'"
        end
    end

    %w{cobalt-api cobalt-compute}.each do |pkg|
        package pkg do
            action :upgrade
            options "-o APT::Install-Recommends=0 -o Dpkg::Options::='--force-confnew'"
        end
    end

    service "cobalt-compute" do
        action [:enable, :start]
    end

    bash "restart-cobalt" do
        subscribes :run, resources("template[/etc/nova/nova.conf]"), :delayed
        subscribes :run, resources("template[/etc/nova/cobalt-compute.conf]"), :delayed
        subscribes :run, resources("template[/etc/sysconfig/vms]"), :delayed
        notifies :restart, "service[cobalt-compute]", :immediately
    end

    bash "create-vms-disk-rados-pool" do
        user "root"
        optimal = power_of_2(get_ceph_osd_nodes.length*node['bcpc']['ceph']['pgs_per_node']/node['bcpc']['ceph']['vms_disk']['replicas']*node['bcpc']['ceph']['vms_disk']['portion']/100)
        code <<-EOH
            ceph osd pool create #{node['bcpc']['ceph']['vms_disk']['name']} #{optimal}
            ceph osd pool set #{node['bcpc']['ceph']['vms_disk']['name']} crush_ruleset #{(node['bcpc']['ceph']['vms_disk']['type']=="ssd") ? node['bcpc']['ceph']['ssd']['ruleset'] : node['bcpc']['ceph']['hdd']['ruleset']}
        EOH
        not_if "rados lspools | grep #{node['bcpc']['ceph']['vms_disk']['name']}"
        notifies :run, "bash[wait-for-pgs-creating]", :immediately
    end

    bash "set-vms-disk-rados-pool-replicas" do
        user "root"
        replicas = [search_nodes("recipe", "ceph-work").length, node['bcpc']['ceph']['vms_disk']['replicas']].min
        if replicas < 1; then
            replicas = 1
        end
        code "ceph osd pool set #{node['bcpc']['ceph']['vms_disk']['name']} size #{replicas}"
        not_if "ceph osd pool get #{node['bcpc']['ceph']['vms_disk']['name']} size | grep #{replicas}"
    end

    (node['bcpc']['ceph']['pgp_auto_adjust'] ? %w{pg_num pgp_num} : %w{pg_num}).each do |pg|
        bash "set-vms-disk-rados-pool-#{pg}" do
            user "root"
            optimal = power_of_2(get_ceph_osd_nodes.length*node['bcpc']['ceph']['pgs_per_node']/node['bcpc']['ceph']['vms_disk']['replicas']*node['bcpc']['ceph']['vms_disk']['portion']/100)
            code "ceph osd pool set #{node['bcpc']['ceph']['vms_disk']['name']} #{pg} #{optimal}"
            not_if "((`ceph osd pool get #{node['bcpc']['ceph']['vms_disk']['name']} #{pg} | awk '{print $2}'` >= #{optimal}))"
            notifies :run, "bash[wait-for-pgs-creating]", :immediately
        end
    end

    bash "create-vms-mem-rados-pool" do
        user "root"
        optimal = power_of_2(get_cepg_osd_nodes.length*node['bcpc']['ceph']['pgs_per_node']/node['bcpc']['ceph']['vms_mem']['replicas']*node['bcpc']['ceph']['vms_mem']['portion']/100)
        code <<-EOH
            ceph osd pool create #{node['bcpc']['ceph']['vms_mem']['name']} #{optimal}
            ceph osd pool set #{node['bcpc']['ceph']['vms_mem']['name']} crush_ruleset #{(node['bcpc']['ceph']['vms_mem']['type']=="ssd") ? node['bcpc']['ceph']['ssd']['ruleset'] : node['bcpc']['ceph']['hdd']['ruleset']}
        EOH
        not_if "rados lspools | grep #{node['bcpc']['ceph']['vms_mem']['name']}"
        notifies :run, "bash[wait-for-pgs-creating]", :immediately
    end

    bash "set-vms-mem-rados-pool-replicas" do
        user "root"
        replicas = [search_nodes("recipe", "ceph-work").length, node['bcpc']['ceph']['vms_mem']['replicas']].min
        code "ceph osd pool set #{node['bcpc']['ceph']['vms_mem']['name']} size #{replicas}"
        not_if "ceph osd pool get #{node['bcpc']['ceph']['vms_mem']['name']} size | grep #{replicas}"
    end

    (node['bcpc']['ceph']['pgp_auto_adjust'] ? %w{pg_num pgp_num} : %w{pg_num}).each do |pg|
        bash "set-vms-mem-rados-pool-#{pg}" do
            user "root"
            optimal = power_of_2(get_ceph_osd_nodes.length*node['bcpc']['ceph']['pgs_per_node']/node['bcpc']['ceph']['vms_mem']['replicas']*node['bcpc']['ceph']['vms_mem']['portion']/100)
            code "ceph osd pool set #{node['bcpc']['ceph']['vms_mem']['name']} #{pg} #{optimal}"
            not_if "((`ceph osd pool get #{node['bcpc']['ceph']['vms_mem']['name']} #{pg} | awk '{print $2}'` >= #{optimal}))"
            notifies :run, "bash[wait-for-pgs-creating]", :immediately
        end
    end
end
