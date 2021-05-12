# CS 145 Project 7

## Author and collaborators
### Author name
David Chataway - davidchataway@g.harvard.edu

### Collaborators
Yang and Mason helped guide the project following review of the Proposal. Also I asked a few questions on Ed.

## Report
### Goal
The goal of this project was to design (what I call) "priority"-based CONGA load balancing, whereby certain flows are given priority over others. Flows with higher priority would react less to congestion in the flow (whereas the other flows with lower priority would be more likely to shift routes) in order for high priority flows to maintain stability and hopefully more traffic throughput. In other words, the "low priority" flows would "get out of the way" of the "high priority" flows. 

Furthermore, a goal of this project was to implement this mechanism with CONGA in the control plane so that the load balancing could continue to be done on a distributed basis and the logic dictating flow priority would be implemented only by a controller. 

### Design and Implementation
The design of the priority-based CONGA load balancing was primarily centered around modifying the conditions by which an egress sends a congestion notification message to the ingress switch, for different flows based on their designated "priority". In particular, modifications were made to the base CONGA code in the following files:
1. Headers
2. Load Balancer
3. Routing Controller

#### Headers
A new metadata attribute was declared in the `p4src/include/headers.p4` file to be used to store the `priority` integer.
```
bit<4> priority;
```

#### Load Balancer
In the base CONGA implementation, congestion was attempted to be avoided using a very simple technique: every time an egress (switch before the destination host) detects that a packet experienced congestion it will send a notification message to the ingress switch, which upon receiving it will randomly move the flow to another path (source: Edgar Costa - see Citations below). The conditions defining "congestion" in my implementation of the base CONGA were as follows:
1. The flow's queued packet depth (carried in the `telemetry` header) is greater than 45;
2. The incoming packet has a timestamp greater than a timeout threshold of 0.75 s per flow;
3. The flow was randomly selected 33% of the time.  <p>

However, in my design of the "priority-based" CONGA, conditions 1 and 3 were modified based on the packet's `meta.priority` value in order for high priority flows to send relatively fewer congestions notification messages. In particular, the changes were implemented (arbitarily as follows):

| Priority      | Queued Depth | Probability |
| ----------- | ----------- | ----------- |
| High (1)      | 60       | 10%       |
| Medium (2)   | 50        | 50%       |
| Low (3)   | 35        | 90%       |

First, in order to set the `meta.priority` value of a packet, match-action tables were created in the ingress processing based off of `srcAddr` and/or `dstAddr` as follows:

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

#### C

The controller sets the specific priority numbers: 1 for h1, 3 for h4 and 2 for all others. I think it does this correctly based on the print statement.



### Challenges

I expected that in the base case, the CONGA implementation from Project 6 would have equal output across h1 to h4. 

However that isn't the case: when running `sudo python send_traffic_onetoone.py 1000`, h4 always seems to have much higher average output than the other hosts (followed by h2 and h3 and then h1 last). When analysing `send_traffic_onetoone.py`, nothing seemed to suggest that h4 had a designed greater traffic output. In response to this [query in Ed](https://edstem.org/us/courses/3092/discussion/431758), Yang replied: "Maybe you would need more powerful VM (with more cores) for mininet simulation to see the difference, or try to scale down the link bandwidth." While I was unable to test with more cores, I did scale down the link bandwidth, which did appear to help accentuate the congestion performance difference. Specifically, at link bandwidths of 5 and 10 mbps, there didn't seem to be a noticable difference between giving h1 "high priority" or "low priority" (see Results and Performance Analysis section below).

Similarly, another challenge was the random nature of the testing scripts and the lack of standardized tools to evaluate network performance. For instance, since `send_traffic_onetoone.py` randomly sends traffic, it was very challenging to interpret the performance results from one trial to the next.

As a result, performance evaluation of CONGA vs priority-based CONGA was done on a not very scientific basis by comparing the `nload` sessions (see below) from runs with different settings.

## Testing
Testing can be done on the medium topology from project 6 as follows:
![medium topology](MediumTopologyDiagram.png).

1. Start the medium size topology:

   ```bash
   sudo p4run --config topology/p4app-medium.json
   ```

2. Open a `tmux` terminal by typing `tmux` (or if you are already using `tmux`, open another window and type `tmux`). And run monitoring script (`nload_tmux_medium.sh`). This script, will use `tmux` to create a window
with 4 panes, in each pane it will lunch a `nload` session with a different interface (from `s1-eth1` to `s1-eth4`), which are the interfaces directly connected to `h1-h4`.

   ```bash
   tmux
   ./nload_tmux_medium.sh
   ```
Or if you want to launch a `nload` session on s6 to observe the output to destination hosts(from `s6-eth1` to `s6-eth4`), which are the interfaces directly connected to `h5-h8` respectively:
   ```bash
   tmux
   ./nload_tmux_medium_s6.sh
   ```

3. Send traffic from `h1-h4` to `h5-h8`. There is a script that will do that for you automatically. It will run 1 flow from each host:

   ```bash
   sudo python send_traffic_onetoone.py 1000
   ```
Note that it can take quite a long time for the flows to converge - it can take as many as ten minutes in some cases.

4. If you want to send 4 different flows, you can just run the command again, it will first stop all the `iperf` sessions, alternatively, if you want
to stop the flow generation you can kill them:

   ```bash
   sudo killall iperf
   ```

### Results and Performance Analysis 


## Citations
The base CONGA implementation utilizes code snippets from [Edgar Costa's](https://github.com/nsg-ethz/p4-learning/tree/master/exercises/10-Congestion_Aware_Load_Balancing/solution) implementation as part of the p4-learning repo.

## Grading notes
While this work was not specifically listed as a "direction" for project 7, I assumed it was within scope based on feedback from the Proposal. I had hoped that this would would serve as an interesting extension for future CONGA work as part of Project 6.


