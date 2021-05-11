#!/usr/bin/env bash

tmux split-window -h
tmux select-pane -t 0
tmux split-window -v
tmux split-window -t 2 -v
tmux select-pane -t 0

tmux send-keys -t 1 "nload s1-eth1"  ENTER
tmux send-keys -t 2 "nload s1-eth2"  ENTER
tmux send-keys -t 3 "nload s2-eth1"  ENTER

tmux send "nload s2-eth2" ENTER