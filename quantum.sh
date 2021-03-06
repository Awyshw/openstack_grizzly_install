#!/usr/bin/env bash

# --------------------------------------------------------------------------------------
# install quantum
# --------------------------------------------------------------------------------------
function allinone_quantum_setup() {
    # install packages
    install_package quantum-server quantum-plugin-openvswitch quantum-plugin-openvswitch-agent dnsmasq quantum-dhcp-agent quantum-l3-agent quantum-lbaas-agent

    # create database for quantum
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE quantum;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON quantum.* TO '${DB_QUANTUM_USER}'@'%' IDENTIFIED BY '${DB_QUANTUM_PASS}';"

    # set configuration files
    sed -e "s#<CONTROLLER_IP>#127.0.0.1#" -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/metadata_agent.ini > /etc/quantum/metadata_agent.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/api-paste.ini > /etc/quantum/api-paste.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<CONTROLLER_NODE_PUB_IP>#${CONTROLLER_NODE_PUB_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/l3_agent.ini > /etc/quantum/l3_agent.ini
    sed -e "s#<DB_IP>#${DB_IP}#" -e "s#<QUANTUM_IP>#${QUANUTM_IP}#" $BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini > /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini

    # restart processes
    restart_service quantum-server
    restart_service quantum-plugin-openvswitch-agent
    restart_service quantum-dhcp-agent
    restart_service quantum-l3-agent
}

# --------------------------------------------------------------------------------------
# install quantum for controller node
# --------------------------------------------------------------------------------------
function controller_quantum_setup() {
    # install packages
    install_package quantum-server quantum-plugin-openvswitch
    # create database for quantum
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE quantum;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON quantum.* TO 'quantumUser'@'%' IDENTIFIED BY 'quantumPass';"

    # set configuration files
    sed -e "s#<DB_IP>#${DB_IP}#" -e "s#<QUANTUM_IP>#${QUANUTM_IP}#" $BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.controller > /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/api-paste.ini > /etc/quantum/api-paste.ini
    sed -e "s#<CONTROLLER_IP>#localhost#" $BASE_DIR/conf/etc.quantum/quantum.conf > /etc/quantum/quantum.conf
    
    # restart process
    restart_service quantum-server
}

# --------------------------------------------------------------------------------------
# install quantum for network node
# --------------------------------------------------------------------------------------
function network_quantum_setup() {
    # install packages
    install_package mysql-client
    install_package quantum-plugin-openvswitch-agent quantum-dhcp-agent quantum-l3-agent quantum-metadata-agent quantum-lbaas-agent

    # set configuration files
    sed -e "s#<CONTROLLER_IP>#${CONTROLLER_NODE_IP}#" -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/metadata_agent.ini > /etc/quantum/metadata_agent.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/api-paste.ini > /etc/quantum/api-paste.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<CONTROLLER_NODE_PUB_IP>#${CONTROLLER_NODE_PUB_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/l3_agent.ini > /etc/quantum/l3_agent.ini
    sed -e "s#<DB_IP>#${DB_IP}#" -e "s#<QUANTUM_IP>#${NETWORK_NODE_IP}#" $BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini > /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini
    sed -e "s#<CONTROLLER_IP>#${CONTROLLER_NODE_IP}#" $BASE_DIR/conf/etc.quantum/quantum.conf > /etc/quantum/quantum.conf

    # restart processes
    cd /etc/init.d/; for i in $( ls quantum-* ); do sudo service $i restart; done
}

# --------------------------------------------------------------------------------------
# create network via quantum
# --------------------------------------------------------------------------------------
function create_network() {
    # create internal network
    TENANT_ID=$(keystone tenant-list | grep " service " | get_field 1)
    INT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} int_net | grep ' id ' | get_field 2)
    # create internal sub network
    INT_SUBNET_ID=$(quantum subnet-create --tenant-id ${TENANT_ID} --ip_version 4 --gateway ${INT_NET_GATEWAY} ${INT_NET_ID} ${INT_NET_RANGE} | grep ' id ' | get_field 2)
    quantum subnet-update ${INT_SUBNET_ID} list=true --dns_nameservers 8.8.8.8 8.8.4.4
    # create internal router
    INT_ROUTER_ID=$(quantum router-create --tenant-id ${TENANT_ID} router-demo | grep ' id ' | get_field 2)
    INT_L3_AGENT_ID=$(quantum agent-list | grep ' L3 agent ' | get_field 1)
    quantum l3-agent-router-add ${INT_L3_AGENT_ID} router-demo
    quantum router-interface-add ${INT_ROUTER_ID} ${INT_SUBNET_ID}
    # create external network
    EXT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} ext_net -- --router:external=True | grep ' id ' | get_field 2)
    # create external sub network
    quantum subnet-create --tenant-id ${TENANT_ID} --gateway=${EXT_NET_GATEWAY} --allocation-pool start=${EXT_NET_START},end=${EXT_NET_END} ${EXT_NET_ID} ${EXT_NET_RANGE} -- --enable_dhcp=False
    # set external network to demo router
    quantum router-gateway-set ${INT_ROUTER_ID} ${EXT_NET_ID}
}

