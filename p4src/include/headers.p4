/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

const bit<16> TYPE_IPV4 = 0x800;

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;


header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

// NEW HEADER
header telemetry_t{
    bit<16> enq_qdepth;
    bit<16> nextHeaderType;    
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<6>    dscp;
    bit<2>    ecn;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}
/*
header tcp_t{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<1>  cwr;
    bit<1>  ece;
    bit<1>  urg;
    bit<1>  ack;
    bit<1>  psh;
    bit<1>  rst;
    bit<1>  syn;
    bit<1>  fin;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
} */

// UDP header
header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length_;
    bit<16> checksum;
}

struct cloned_t {

}

struct metadata {
    bit<14> ecmp_hash;
    bit<14> ecmp_group_id;
    bit<4> egress_type;  //from project 6
    bit<4> priority;  //NEW FIELD FOR PRIORITY
    bit<48> interval; //from project 5
    bit<32> flow_index; //from project 5
    cloned_t cloned; //NEW
}

struct headers {
    ethernet_t   ethernet;
    telemetry_t  telemetry; //NEW LINE
    ipv4_t       ipv4;
    udp_t        udp; // tcp
}

