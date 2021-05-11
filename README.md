# Project 7: David Chataway
Repository for David Chataway's project 7 work for Harvard CS145.

## Objectives
- Implementing simple policies to the [Project 6](https://github.com/Harvard-CS145/cs145-21-project6-dchataway) CONGA load balancing algorithm.
- Experiment with how different policies impact performance of the network as a whole.

## Overview
For my Project 7, I am pursuing an open-ended topic: designing (what I call) "priority"-based CONGA load balancing, whereby certain flows are given priority over others.

## How to Use
1. Please clone this repository.
2. Make sure you have installed `nload`: 
```
sudo apt-get install nload
```
3. Make sure you have installed `iperf` or `iperf3`.
4. Test the code as follows:

## Report
Please refer to `report/report.md` for the submission report with further information.

## Citations
The CONGA implementation is based off of [Edgar Costa's](https://github.com/nsg-ethz/p4-learning/tree/master/exercises/10-Congestion_Aware_Load_Balancing/solution) implementation as part of the p4-learning repo.
