from p4utils.utils.topology import Topology
from p4utils.utils.sswitch_API import SimpleSwitchAPI

class RoutingController(object):

    def __init__(self):

        self.topo = Topology(db="topology.db")
        self.controllers = {}
        self.init()

    def init(self):
        self.connect_to_switches()
        self.reset_states()
        self.set_table_defaults()

    def reset_states(self):
        [controller.reset_state() for controller in self.controllers.values()]

    def connect_to_switches(self):
        for p4switch in self.topo.get_p4switches():
            thrift_port = self.topo.get_thrift_port(p4switch)
            self.controllers[p4switch] = SimpleSwitchAPI(thrift_port)

    def set_table_defaults(self):
        for controller in self.controllers.values():
            controller.table_set_default("ipv4_lpm", "drop", [])
            controller.table_set_default("ecmp_group_to_nhop", "drop", [])

    def set_egress_type_table(self):
        # From project 6
        # Function outside of route() that sets the egress type table

        # loops through all switches
        for sw_name, controller in self.controllers.items():
            # gets the interface and node type
            for interface, node in self.topo.get_interfaces_to_node(sw_name).items():
                node_type = self.topo.get_node_type(node)
                port_number = self.topo.interface_to_port(sw_name, interface)

                # numerates the node types to be put in the table
                if node_type == 'host':
                    node_type_num = 1
                elif node_type == 'switch':
                    node_type_num = 2

                # fills the table
                self.controllers[sw_name].table_add("egress_type", "set_type", [str(port_number)], [str(node_type_num)])

    def set_priority_table(self):
        # NEW - SETS THE PRIORITY BASED ON THE HOST NUMBER
        # Function outside of route() that sets the priority table

        # loops through all switches
        for sw_name, controller in self.controllers.items():

            # gets the node type
            node_type = self.topo.get_node_type(node)

            priority_num = 2
            # numerates the node types to be put in the table
            if node_type == 'host':
                host_ip = self.topo.get_host_ip(sw_name) + "/24"
                priority_num = 1
            elif node_type == 'switch':
                pass

            print "Switch name {}:, ip address {}:".format(sw_name, str(host_ip))

            # fills the table
            self.controllers[sw_name].table_add("priority_type", "set_priority", [str(host_ip)], [str(priority_num)])


    def add_mirroring_ids(self):

        for sw_name, controller in self.controllers.items():
            # adding port 1 (it seems like the first argument is standard)
            controller.mirroring_add(100, 1)

    def route(self):

        switch_ecmp_groups = {sw_name:{} for sw_name in self.topo.get_p4switches().keys()}

        for sw_name, controller in self.controllers.items():
            print "Switch name {}:, ip address {}:".format(sw_name, str(host_ip))

            for sw_dst in self.topo.get_p4switches():

                #if its ourselves we create direct connections
                if sw_name == sw_dst:
                    for host in self.topo.get_hosts_connected_to(sw_name):
                        sw_port = self.topo.node_to_node_port_num(sw_name, host)
                        host_ip = self.topo.get_host_ip(host) + "/32"
                        host_mac = self.topo.get_host_mac(host)

                        #add rule
                        print "table_add at {}:".format(sw_name)
                        self.controllers[sw_name].table_add("ipv4_lpm", "set_nhop", [str(host_ip)], [str(host_mac), str(sw_port)])

                #check if there are directly connected hosts
                else:
                    if self.topo.get_hosts_connected_to(sw_dst):
                        paths = self.topo.get_shortest_paths_between_nodes(sw_name, sw_dst)
                        for host in self.topo.get_hosts_connected_to(sw_dst):

                            if len(paths) == 1:
                                next_hop = paths[0][1]

                                host_ip = self.topo.get_host_ip(host) + "/24"
                                sw_port = self.topo.node_to_node_port_num(sw_name, next_hop)
                                dst_sw_mac = self.topo.node_to_node_mac(next_hop, sw_name)

                                #add rule
                                print "table_add at {}:".format(sw_name)
                                self.controllers[sw_name].table_add("ipv4_lpm", "set_nhop", [str(host_ip)],
                                                                    [str(dst_sw_mac), str(sw_port)])

                            elif len(paths) > 1:
                                next_hops = [x[1] for x in paths]
                                dst_macs_ports = [(self.topo.node_to_node_mac(next_hop, sw_name),
                                                   self.topo.node_to_node_port_num(sw_name, next_hop))
                                                  for next_hop in next_hops]
                                host_ip = self.topo.get_host_ip(host) + "/24"

                                #check if the ecmp group already exists. The ecmp group is defined by the number of next
                                #ports used, thus we can use dst_macs_ports as key
                                if switch_ecmp_groups[sw_name].get(tuple(dst_macs_ports), None):
                                    ecmp_group_id = switch_ecmp_groups[sw_name].get(tuple(dst_macs_ports), None)
                                    print "table_add at {}:".format(sw_name)
                                    self.controllers[sw_name].table_add("ipv4_lpm", "ecmp_group", [str(host_ip)],
                                                                        [str(ecmp_group_id), str(len(dst_macs_ports))])

                                #new ecmp group for this switch
                                else:
                                    new_ecmp_group_id = len(switch_ecmp_groups[sw_name]) + 1
                                    switch_ecmp_groups[sw_name][tuple(dst_macs_ports)] = new_ecmp_group_id

                                    #add group
                                    for i, (mac, port) in enumerate(dst_macs_ports):
                                        print "table_add at {}:".format(sw_name)
                                        self.controllers[sw_name].table_add("ecmp_group_to_nhop", "set_nhop",
                                                                            [str(new_ecmp_group_id), str(i)],
                                                                            [str(mac), str(port)])

                                    #add forwarding rule
                                    print "table_add at {}:".format(sw_name)
                                    self.controllers[sw_name].table_add("ipv4_lpm", "ecmp_group", [str(host_ip)],
                                                                        [str(new_ecmp_group_id), str(len(dst_macs_ports))])


    def main(self):
        self.set_egress_type_table()
        self.set_priority_table()
        self.add_mirroring_ids()
        self.route()


if __name__ == "__main__":
    controller = RoutingController().main()
