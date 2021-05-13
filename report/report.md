# CS 145 Project 7

## Author and collaborators
### Author name
David Chataway - davidchataway@g.harvard.edu

### Collaborators
Yang and Mason helped guide the project following review of the Proposal. Also I asked a few questions on Ed.

## Report
### Goal
The goal of this project was to design (what I call) "priority"-based CONGA load balancing, whereby certain flows are given priority over others. Flows with higher priority would react less to congestion in the flow (whereas the other flows with lower priority would be more likely to shift routes) in order for high priority flows to maintain stability and hopefully more traffic throughput. In other words, the "low priority" flows would "get out of the way" of the "high priority" flows. 

Furthermore, a goal of this project was to implement this mechanism together with CONGA in the control plane so that the load balancing would be done on a distributed basis and the logic dictating the flow priority would be implemented only by a controller. 

### Design and Implementation
The design of the priority-based CONGA load balancing was primarily centered around modifying the conditions by which an egress sends a congestion notification message to the ingress switch, for different flows based on their designated "priority". In particular, modifications were made to the base CONGA code in the following files:
1. Headers
2. Load Balancer
3. Routing Controller

Relevant code blocks in the above files are described in the sub-sections below. Refer to `README.md` in the parent directory for a list of, and more information about, the included files and configuration fields.

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

However, in my design of the "priority-based" CONGA, conditions 1 and 3 were modified based on the packet's `meta.priority` value in order for high priority flows to send relatively fewer congestions notification messages. In particular, the changes were implemented (arbitarily through testing as follows):

| Packet Priority      | Queued Depth | Probability |
| ----------- | ----------- | ----------- |
| High (1)      | 60       | 10%       |
| Medium (2)   | 50        | 50%       |
| Low (3)   | 35        | 90%       |

First, in order to set the `meta.priority` value of a packet, match-action tables were applied in the ingress processing based off of `srcAddr` and/or `dstAddr` as follows:

```
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
```
Then in the Egress processing, the conditions for congestion notification are different based on the priority in the metadata (according to the table included above). The code for the queued condition is as follows:
```
	bit<16> queue_threshold;
	if (PRIORITY_APPLY == 1) {
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
	...
	}
```
and the code for the probability threshold is as follows:
```
        bit<16> probability;
        bit<16> threshold;
        if (PRIORITY_APPLY == 1) {
            if (meta.priority == TYPE_PRIORITY_HIGH) {
                threshold = 10;
            }
            else if (meta.priority == TYPE_PRIORITY_LOW) {
                threshold = 90; 
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
                clone3(CloneType.E2E, 100, meta);
            }
```

#### Controller

The controller fills the match-action tables with the priority numbers configured in the instance attributes: 
```
        self.apply_src_priority = True
        self.apply_dst_priority = False
        self.src_high_priority = 'h1'
        self.src_low_priority = 'h4'
        self.dst_high_priority = 'h5'
        self.dst_low_priority = 'h8'
```
Then in the `set_tables` function, the `table_add` methods are designed to do lpm matching based on the (source or destination) host ip and calling the `set_priority` action:
```
	if node_type == 'host':
	    host_ip = self.topo.get_host_ip(node) + "/24"
	    priority_num = 2
	    if str(node) == self.src_high_priority and self.apply_src_priority:
		priority_num = 1
	    elif str(node) == self.src_low_priority and self.apply_src_priority:
		priority_num = 3
	    elif str(node) == self.dst_high_priority and self.apply_dst_priority:
		priority_num = 1
	    elif str(node) == self.dst_low_priority and self.apply_dst_priority:
		priority_num = 3                     
	    print "Node name: {}, ip address: {}, priority: {}".format(str(node), str(host_ip), str(priority_num))
	    self.controllers[sw_name].table_add("priority_type", "set_priority", [str(host_ip)], [str(priority_num)])
	    if self.apply_dst_priority:
		self.controllers[sw_name].table_add("priority_type_dst", "set_priority", [str(host_ip)], [str(priority_num)])
```

### Challenges

I expected that in the base CONGA case, running the main test script `send_traffic_onetoone.py` would result in approximately equal traffic output across h1 to h4, allowing for easy evaluation of configuration fields. 

However that isn't the case: when running `send_traffic_onetoone.py`, h4 always seems to have much higher average output than the other hosts (followed by h2 and h3 and then h1 last). When analysing `send_traffic_onetoone.py`, nothing seemed to suggest that h4 had a designed greater traffic output. In response to this [query in Ed](https://edstem.org/us/courses/3092/discussion/431758), Yang replied: "Maybe you would need more powerful VM (with more cores) for mininet simulation to see the difference, or try to scale down the link bandwidth." While I was unable to test with more cores, I did scale down the link bandwidth, which did appear to help accentuate the congestion performance difference. Specifically, at link bandwidths of 5 and 10 mbps, there didn't seem to be a noticable difference between giving h1 "high priority" or "low priority" (see Results and Performance Analysis section below).

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
The performance of the priority-based CONGA implementation was primarily evaluated by observing the average traffic output from hosts h1 to h4 after reaching approximately steady state, across different configuration settings. These results are shown in the table below and in screenshots included in the Appendix:

*Note that in the table below, normal "priority CONGA" is configured such that h1 is high priority and h4 is low priority. The "reversed" configuration is such that h4 is high priority and h1 is low priority.*

| Case      | h1 (avg. mbps) | h2 (avg. mbps) | h3 (avg. mbps) | h4 (avg. mbps) |
| ----------- | ----------- | ----------- | ----------- | ----------- |
| A) Base CONGA, 1mpbs links                  | 0.36961       | 0.34288       | 0.28784       | 0.82619       |
| B) Priority CONGA, 1mpbs links              | 0.46878        | 0.23878       | 0.48362       | 0.88512       |
| C) Base CONGA, 2mpbs links                  | 0.59838       | 0.64392       | 0.74589       | 1.66       |
| D) Priority CONGA, 2mpbs links              | 0.64849        | 0.72938       | 0.71935       | 1.54       |
| E) Priority CONGA (reversed), 2mpbs links   | 0.58988        | 0.8848       | 0.57487       | 1.56       |
| F) Priority CONGA, 5mpbs links              | 1.46        | 1.71       | 1.35       | 3.68       |
| G) Priority CONGA (reversed), 5mpbs links   | 1.43        | 1.61       | 1.55       | 3.69       |

The avg. traffic output results from the testing seem to suggest that the priority-based CONGA may be effective when the link bandwidths are lower than 5 mpbs (perhaps due to the generation of more congestion on the smaller links). With 5 mbps links, there was little difference in the results when h1 was given high priority and h4 was given low priority (Case F) vs the opposite configuration (Case G). However, with 1 and 2 mbps links, subtle differences were observed. In particular, when h1 was given high priority it resulted in higher traffic output for both 1 mbps and 2 mbps links (cases B and D) as compared to the respective base CONGA (cases A and C). This was the intended performance as it was hoped that moving flows less frequently from h1 would result in higher traffic output relative to the base CONGA case in which flows were moved equally. However, as discussed in the Challenges section, it is unclear if these results are significant considering the high variability and randomness of the testing script. 

In general, the subtleness of the differences in output from the "priority-based" CONGA (CONGA with priority-based congestion notification conditions) suggest that it may not be the best manner to implement priority-based routing. Granted, it is possible that a more advanced algorithm (rather than just randomly re-hashing flows upon receiving a congestion notification) along with the priority-based design may result in better performance with this design. However, the results of this exercise demonstrate to me that a distributed solution is likely not best and that a global congestion aware solution would be best to implement priority-based routing. Furthermore, my design - in which high priority flows are re-hashed relatively less frequently - may be susceptible to congestion deeper in the network and/or to link failures.

## Citations
The base CONGA implementation utilizes code snippets from [Edgar Costa's](https://github.com/nsg-ethz/p4-learning/tree/master/exercises/10-Congestion_Aware_Load_Balancing/solution) implementation as part of the p4-learning repo.

## Grading notes
While this work was not specifically listed as a "direction" for project 7, I assumed it was within scope based on feedback from my submitted Proposal. I had hoped that this project would would serve as an interesting extension for future CONGA class work as part of Project 6.

## Appendix
##### Case A: Base CONGA, 1mpbs links
![Case A]("CaseA.PNG").

##### Case B: Priority CONGA, 1mpbs links
![Case B]("CaseB.PNG").

##### Case C: Base CONGA, 2mpbs links
![Case C]("CaseC.PNG").

##### Case D: Priority CONGA, 2mpbs links 
![Case D]("CaseD.PNG").

##### Case E: Priority CONGA (reversed), 2mpbs links
![Case E]("CaseE.PNG").

##### Case F: Priority CONGA, 5mpbs links 
![Case F]("CaseF.PNG").

##### Case G: Priority CONGA (reversed), 5mpbs links
![Case G]("CaseG.PNG").

