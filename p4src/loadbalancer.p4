/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

//My includes
#include "include/headers.p4"
#include "include/parsers.p4"

typedef bit<16>  depth; // used to type cast later
#define REGISTER_SIZE 1024

// Copied from p4 documentation
#define PKT_INSTANCE_TYPE_NORMAL 0
#define PKT_INSTANCE_TYPE_INGRESS_CLONE 1
#define PKT_INSTANCE_TYPE_EGRESS_CLONE 2
#define PKT_INSTANCE_TYPE_COALESCED 3
#define PKT_INSTANCE_TYPE_INGRESS_RECIRC 4
#define PKT_INSTANCE_TYPE_REPLICATION 5
#define PKT_INSTANCE_TYPE_RESUBMIT 6

// DEMO OPTIONS
#define PRIORITY_APPLY 1
#define DST_PRIORITY_APPLY 0

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    // Register to store an ID value for each flow - similar to project 5
    register<bit<32>>(REGISTER_SIZE) flow_id;

    action drop() {
        mark_to_drop(standard_metadata);
    }

    // From project 6 - sets egress type in metadata
    action set_type(bit<4> egress_type) {
        meta.egress_type = egress_type;
    }

    // From Project 6
    table egress_type {
        key = {
            standard_metadata.egress_spec: exact;
        }
        actions = {
            set_type;
            NoAction;
        }
        size = 1024;
        default_action = NoAction;
    }

    /********** NEW CODE *******/
    // NEW - SETS PRIORITY IN METADATA AND IN REGISTER
    action set_priority(bit<4> priority) {
        // store in meta data
        meta.priority = priority;
    }
    table priority_type {
        key = {
            hdr.ipv4.srcAddr: lpm;
        }
        actions = {
            set_priority;
            NoAction;
        }
        size = 1024;
        default_action = NoAction;
    }
    table priority_type_dst {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            set_priority;
            NoAction;
        }
        size = 1024;
        default_action = NoAction;
    }

    // From project 6 - Similar to Pset 5:
    // hash based on the 5 tuple, get the flowlet_id from a register and then update random number
    action get_flow_id(){
        bit<32> id;
        bit<32> num;
        // generate a random number
        random(num, (bit<32>)0, (bit<32>)100000);

        // Get the flow_id of a feedback packet     
        hash(id, HashAlgorithm.crc16,(bit<1>)0,
        { hdr.ipv4.dstAddr, //swap the source and destination IPs
          hdr.ipv4.srcAddr, 
          hdr.udp.srcPort, //tcp
          hdr.udp.dstPort, // tcp
          hdr.ipv4.protocol}, 
        (bit<12>)REGISTER_SIZE); 
        // update
        flow_id.write(id, num);
    }


    action ecmp_group(bit<14> ecmp_group_id, bit<16> num_nhops){

      // add a new field to the 5-tuple hash that acts as a randomizer 
      // uses the num from the flow_id register that is updated based on the congestion notifications
        bit<32> id;
        bit<32> num;

        // Use to get the flow_id      
        hash(id, HashAlgorithm.crc16,(bit<1>)0,
        { hdr.ipv4.srcAddr, //normal source and destination IPs
          hdr.ipv4.dstAddr, 
          hdr.udp.srcPort, //tcp
          hdr.udp.dstPort, //tcp
          hdr.ipv4.protocol}, 
        (bit<12>)REGISTER_SIZE); 
        // read random num
        flow_id.read(num, id);

        // 5-tuple + random num id hashing
        hash(meta.ecmp_hash,
	    HashAlgorithm.crc16,
	    (bit<1>)0,
	    { hdr.ipv4.srcAddr,
	      hdr.ipv4.dstAddr,
          hdr.udp.srcPort, //tcp
          hdr.udp.dstPort, //tcp
          hdr.ipv4.protocol,
          num},
	    num_nhops);

	    meta.ecmp_group_id = ecmp_group_id;
    }

    action set_nhop(macAddr_t dstAddr, egressSpec_t port) {

        //set the src mac address as the previous dst, this is not correct right?
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;

        //set the destination mac address that we got from the match in the table
        hdr.ethernet.dstAddr = dstAddr;

        //set the output port that we also get from the table
        standard_metadata.egress_spec = port;

        //decrease ttl by 1
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ecmp_group_to_nhop {
        key = {
            meta.ecmp_group_id:    exact;
            meta.ecmp_hash: exact;
        }
        actions = {
            drop;
            set_nhop;
        }
        size = 1024;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            set_nhop;
            ecmp_group;
            drop;
        }
        size = 1024;
        default_action = drop;
    }

    apply {

        // if this is a recirculated packet, then modify the ethernet type and switch the IP addresses
        if (standard_metadata.instance_type == PKT_INSTANCE_TYPE_INGRESS_RECIRC){
            hdr.ethernet.etherType = 0x7778;
            bit<32> src_ip = hdr.ipv4.srcAddr;
            hdr.ipv4.srcAddr = hdr.ipv4.dstAddr;
            hdr.ipv4.dstAddr = src_ip;
        }

        // forward packets if IP valid
        if (hdr.ipv4.isValid()){
            switch (ipv4_lpm.apply().action_run){
                ecmp_group: {
                    ecmp_group_to_nhop.apply();
                }
            }
        }

        // From project 6 apply the table at the ingress control after the other actions are applied
        egress_type.apply();
        // NEW CODE TO APPLY TABLES FOR PRIORITY
        if (DST_PRIORITY_APPLY == 1) {
            priority_type_dst.apply();    
        }
        priority_type.apply();
   

        // NEW: if sending to a host (type = 1), and it is a notification packet
        if (standard_metadata.instance_type == PKT_INSTANCE_TYPE_NORMAL && hdr.ethernet.etherType == 0x7778 && meta.egress_type == TYPE_EGRESS_HOST){
            get_flow_id(); 
            drop(); //drop it
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {

    /* SIMILAR PROJECT 5: IN ORDER TO ADD A TIMEOUT PER FLOW */
    register<bit<48>>(REGISTER_SIZE) read_timestamp;

    // hash based on the 5 tuple, get the flow timestamp from a register and then store in metadata
    action get_flow_timestamp(){

        // Use to get the flowlet_id      
        hash(meta.flow_index, HashAlgorithm.crc16,(bit<1>)0,
        { hdr.ipv4.srcAddr, 
          hdr.ipv4.dstAddr, 
          hdr.udp.srcPort, //tcp
          hdr.udp.dstPort, //tcp
          hdr.ipv4.protocol}, 
        (bit<12>)REGISTER_SIZE); 

        /* Get the last flowlet timestamp belonging to the 5 tuple */
        read_timestamp.read(meta.interval, meta.flow_index);
    }


    apply {


        // FIRST CHECK IF IT IS A CLONED PACKET
        if (standard_metadata.instance_type == PKT_INSTANCE_TYPE_EGRESS_CLONE) {
            // then recirculate
            recirculate({}); //not {}? // meta.cloned
        }


        else if (standard_metadata.instance_type == PKT_INSTANCE_TYPE_NORMAL && hdr.ethernet.etherType != 0x7778) {

            // NEW CODE BLOCK FOR EGRESS PROCESSING //tcp
            if (hdr.udp.isValid()){
                if (hdr.telemetry.isValid()) {
                    // Then there is a telemetry header

                    // If the next hop is a switch (type = 2)
                    if (meta.egress_type == TYPE_EGRESS_SWITCH) {
                        // update if bigger than the current one
                        if ((depth)standard_metadata.enq_qdepth > hdr.telemetry.enq_qdepth) {
                            // set the depth field
                            hdr.telemetry.enq_qdepth = (depth)standard_metadata.enq_qdepth;
                        }
                    }
                    // if the next hop is a host
                    else if (meta.egress_type == TYPE_EGRESS_HOST){ 
                        // Remove the telemetry header
                        hdr.telemetry.setInvalid();
                        // Set etherType to type IPV4
                        hdr.ethernet.etherType = 0x800;

                        // NEW CODE FOR PROJECT 7- sending notification/feedback that flow is experiencing congestion:
                        // Extend to clone packet and send as feedback to the ingress switch
                        // Condition 1) check if the received queue depth is above a threshold

                        bit<16> queue_threshold;

                        if (PRIORITY_APPLY == 1) {
                             // CODE THAT SETS QUEUE THRESHOLD BASED ON PRIORITY
                            if (meta.priority == TYPE_PRIORITY_HIGH) {
                                queue_threshold = 60; 
                            }
                            else if (meta.priority == TYPE_PRIORITY_LOW) {
                                queue_threshold = 35; 
                            }
                            else {
                                queue_threshold = 50;
                            }   
                        }
                        else {
                            queue_threshold = 45;
                        }

                                                      

                        if (hdr.telemetry.enq_qdepth > queue_threshold){

                            // Condition 2) check time difference in order to see the flow is different
                            get_flow_timestamp();
                            // if the time difference is bigger than a pre-defined value (0.75 s),
                            if ((standard_metadata.ingress_global_timestamp - meta.interval) > 750000) {
                                // write to the register similar to project 5
                                read_timestamp.write(meta.flow_index, standard_metadata.ingress_global_timestamp);

                                // Condition 3) only move a certain % of them (DEPENDING ON PRIORITY)

                                bit<16> probability;
                                bit<16> threshold;
                                
                                if (PRIORITY_APPLY == 1) {
                                    // CODE THAT SETS PROBABILITY THRESHOLD BASED ON PRIORITY
                                    if (meta.priority == TYPE_PRIORITY_HIGH) {
                                        threshold = 10; //originally 10
                                    }
                                    else if (meta.priority == TYPE_PRIORITY_LOW) {
                                        threshold = 90; //originally 90
                                    }
                                    else {
                                        threshold = 50;
                                    }
                                }
                                else {
                                    threshold = 33;
                                }

                                
                                random(probability, (bit<16>)0, (bit<16>)100);
                                    if (probability < threshold) {
                                        // Then clone the packet
                                        // following this code here: http://csie.nqu.edu.tw/smallko/sdn/p4utils_sendtocpu.htm
                                        clone3(CloneType.E2E, 100, meta); // NOTE - DO YOU USE JUST THE META OBJECT OR META.CLONED????
                                    } 
                            }
                        }
                    }
                }

                else {
                    // Then there isn't a telemetry header

                    // if the next hop is a switch (type = 2)
                    if (meta.egress_type == TYPE_EGRESS_SWITCH) {
                        hdr.telemetry.setValid();
                        hdr.telemetry.enq_qdepth = (depth)standard_metadata.enq_qdepth;
                        hdr.telemetry.nextHeaderType = 0x800;
                        hdr.ethernet.etherType = 0x7777;
                    }
                }
            }
        }
    }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
     apply {
	update_checksum(
	    hdr.ipv4.isValid(),
            { hdr.ipv4.version,
	          hdr.ipv4.ihl,
              hdr.ipv4.dscp,
              hdr.ipv4.ecn,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
              hdr.ipv4.hdrChecksum,
              HashAlgorithm.csum16);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

//switch architecture
V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;