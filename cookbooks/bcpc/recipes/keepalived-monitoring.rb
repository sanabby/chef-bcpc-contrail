#
# Cookbook Name:: bcpc
# Recipe:: keepalived-monitoring
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
include_recipe "bcpc::keepalived-common"

ruby_block "initialize-keepalived-config" do
    block do
        make_config('keepalived-monitoring-router-id', generate_vrrp_vrid)
        make_config('keepalived-monitoring-password', secure_password)
    end
end

template "/etc/keepalived/keepalived.conf" do
    source "keepalived-monitoring.conf.erb"
    mode 00640
    variables(
        :group_name => "#{node['bcpc']['region_name']}-Monitoring",
        :router_id_key => "keepalived-monitoring-router-id",
        :password_key => "keepalived-monitoring-password",
        :chk_quorum_script => "/usr/local/bin/chk_mysql_quorum",
        :vip => "#{node['bcpc']['management']['monitoring']['vip']}"
    )
    notifies :restart, "service[keepalived]", :immediately
end
