# Project 7: David Chataway
Repository for David Chataway's project 7 work for Harvard CS145.

## Objectives
- Implementing simple policies to the [Project 6](https://github.com/Harvard-CS145/cs145-21-project6-dchataway) CONGA load balancing algorithm.
- Experiment with how different policies impact performance of the network as a whole.

## Overview
For my Project 7, I am pursuing an open-ended topic: designing (what I call) "priority"-based CONGA load balancing, whereby certain flows are given priority over others. Please refer to `report/report.md` for more information.

## How to Use
1. Please clone this repository.
2. Make sure you have installed `iperf` and `nload`: 
```
sudo apt-get install nload
```
3. Test the code as follows (using the "medium" topology as a test case):

4. Start the medium size topology:

   ```bash
   sudo p4run --config topology/p4app-medium.json
   ```

5. Open a `tmux` terminal by typing `tmux` (or if you are already using `tmux`, open another window and type `tmux`). And run monitoring script (`nload_tmux_medium.sh`). This script, will use `tmux` to create a window
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

6. Send traffic from `h1-h4` to `h5-h8`. There is a script that will do that for you automatically. It will run 1 flow from each host:

   ```bash
   sudo python send_traffic_onetoone.py 1000
   ```
Note that it can take quite a long time for the flows to converge - it can take as many as ten minutes in some cases.

## Report
Please refer to `report/report.md` for the submission report with further information.

## Citations
The CONGA implementation is based off of [Edgar Costa's](https://github.com/nsg-ethz/p4-learning/tree/master/exercises/10-Congestion_Aware_Load_Balancing/solution) implementation as part of the p4-learning repo.
