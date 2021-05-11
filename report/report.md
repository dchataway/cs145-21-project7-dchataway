# CS 145 Project 7

## Author and collaborators
### Author name
David Chataway - davidchataway@g.harvard.edu

### Collaborators
Yang and Mason helped guide the project. Also I asked a few questions on Ed.

## Report
### Goal
- The advantage of CONGA is that it is distributed and can dynamically detect and react to congestion in the flow in order to improve load balancing, especially with flows of varied size. The disadvantage is that packet reordering may occur (since typical CONGA load balances on a packet or flowlet level) and it does not scale well to "large multi-tier networks" because of its 2-way "leaf-to-leaf" sharing feedback mechanism between nodes.

### Design
In contrast, the new CONGA implementation in this project randomly re-hashes flows that are congested based on certain conditions. The conditions defining "congestion" in my implementation are as follows:
1. The flow's queued packet depth (carried in the `telemetry` header) is greater than 45;
2. The incoming packet has a timestamp greater than a timeout threshold of 0.75 s per flow;
3. The flow meets the 33% movement ratio.  <p>

Similar to my CONGA implementation in Project 6, the mechanism through which we notify ingress switches of congestion is through a feedback packet (created through cloning and recirculating externs with a unique ethernet type (i.e. 0x7778)) that triggers the `get_flow_id` action which generates and writes a random number corresponding to the flow to a register. That random number is then read and taken into account when hashing the 5-tuple according to the ECMP action.

### Implementation

I implement this by creating a match-action table based on the `srcAddr` that sets a `priority` attribute in the metadata:
```
    action set_priority(bit<4> priority) {
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
```
Then in the Egress processing, at the condition were a congestion notification packet is sent, I change the conditions based on the priority in the metadata, for example for the queue length:
```
        bit<16> queue_threshold;
         // CODE THAT SETS QUEUE THRESHOLD BASED ON PRIORITY
        if (meta.priority == TYPE_PRIORITY_HIGH) {
            queue_threshold = 50; //originally 45
        }
        else if (meta.priority == TYPE_PRIORITY_LOW) {
            queue_threshold = 35; //originally 45
        }
        else {
            queue_threshold = 45;
        }
                                      

        if (hdr.telemetry.enq_qdepth > queue_threshold){
        ...
        }
```
and now for the probability:
```
 	bit<16> probability;
        bit<16> threshold;

        // CODE THAT SETS PROBABILITY THRESHOLD BASED ON PRIORITY
        if (meta.priority == TYPE_PRIORITY_HIGH) {
            threshold = 10; //originally 10
        }
        else if (meta.priority == TYPE_PRIORITY_LOW) {
            threshold = 90; //originally 90
        }
        else {
            threshold = 90;
        }
        

        random(probability, (bit<16>)0, (bit<16>)100);
            if (probability < threshold) {
                // Then clone the packet
               clone3(CloneType.E2E, 100, meta); 
            } 
```

The controller sets the specific priority numbers: 1 for h1, 3 for h4 and 2 for all others. I think it does this correctly based on the print statement.



### Challenges
I expected h1 to have much higher average throughput than h4, but this isn't the case. h4 always has very high throughput.

Yang [posted in Ed](https://edstem.org/us/courses/3092/discussion/431758): Maybe you would need more powerful VM (with more cores) for mininet simulation to see the difference, or try to scale down the link bandwidth. 

### Testing


### Results and Performance Analysis 


## Citations
The CONGA implementation is based off of [Edgar Costa's](https://github.com/nsg-ethz/p4-learning/tree/master/exercises/10-Congestion_Aware_Load_Balancing/solution) implementation as part of the p4-learning repo.

## Grading notes


