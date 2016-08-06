#
# Cookbook Name:: bcpc
# Recipe:: haproxy-monitoring
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
include_recipe "bcpc::haproxy-common"

template "/etc/haproxy/haproxy.cfg" do
    source "haproxy-monitoring.cfg.erb"
    mode 00644
    variables(
        :servers => search_nodes("role", "BCPC-Monitoring")
    )
    notifies :restart, "service[haproxy]", :immediately
end
