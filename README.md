# Project 7: David Chataway
Repository for David Chataway's project 7 work for Harvard CS145.

## Objectives
- Implementing simple policies to the [Project 6](https://github.com/Harvard-CS145/cs145-21-project6-dchataway) CONGA load balancing algorithm.
- Experiment with how different policies impact performance of the network as a whole.

## Overview
For my Project 7, I am pursuing an open-ended topic: designing (what I call) "priority"-based CONGA load balancing, whereby certain flows are given priority over others. Please refer to `report/report.md` for more information.

## Report
Please refer to `report/report.md` for the submission report with further information.

## What is Provided
- `topology/p4app-medium.json`: creates the topology for testing and performance analysis with the help of mininet and - p4-utils package.
- `p4src/loadbalancer.p4`: we will use the solution of the 08-Simple_Routing exercise as starting point.
- `routing-controller.py`: routing controller.
- `nload_tmux_*.sh`: scripts that will create a tmux window, and nload in different panes.
And copied from the Project 6 repo: 
- `send.py`: a small python script to generate tcp probe packets to read queues.
- `receive.py`: a small python script to receive tcp probes that include a telemetry header.
- `send_traffic_*.py`: python scripts that use iperf to automatically generate flows to test.

## Configuration Fields
* `topology/p4app-medium.json`:
    * `default_bw`: sets the default bandwidth of the links in the topology. The value is set to 2 mbps as it appears to generate the best topology for testing.
*  `p4src/loadbalancer.p4`:
    * `PRIORITY_APPLY`: binary value used to select "priority-based" CONGA switching based on `srcAddr` or not (1 = selected, 0 = not selected)
    * `DST_PRIORITY_APPLY`: binary value used to select "priority-based" CONGA switching based on `dstAddr` or not (1 = selected, 0 = not selected)
    * `queue_threshold`: condition for congestion notification based on the maximum enqueued packet depth experienced along the flow.
    * `threshold`: condition for congestion notification based on random number generation.
* `routing-controller.py`:
    * `self.apply_src_priority`: binary instance attribute that determines whether or not the controller fills the `priority_type` table
    * `self.apply_dst_priority`: binary instance attribute that determines whether or not the controller fills the `priority_type_dst` table
    * `self.*_priority`: instance attributes that set the low and high priority values for specific source and destination host names 

## How to Use
1. Please clone this repository.
2. Make sure you have installed `iperf` and `nload`: 
```
sudo apt-get install nload
```
3. Modify any configuration fields, if necessary.
4. Test the code as follows (using the "medium" topology as a test case):

#### Testing

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
Or if you want to launch a `nload` session on s6 (from `s6-eth1` to `s6-eth4`), which are the interfaces directly connected to `h5-h8`:
   ```bash
   tmux
   ./nload_tmux_medium_s6.sh
   ```

3. Send traffic from `h1-h4` to `h5-h8`. There is a script that will do that for you automatically. It will run 1 flow from each host:

   ```bash
   sudo python send_traffic_onetoone.py 1000
   ```
Note that it can take quite a long time for the flows to converge - it can take as many as ten minutes in some cases.

## Citations
The CONGA implementation is based off of [Edgar Costa's](https://github.com/nsg-ethz/p4-learning/tree/master/exercises/10-Congestion_Aware_Load_Balancing/solution) implementation as part of the p4-learning repo.
