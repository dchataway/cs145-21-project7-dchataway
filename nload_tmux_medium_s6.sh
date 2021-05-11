#!/usr/bin/env bash

tmux split-window -h
tmux select-pane -t 0
tmux split-window -v
tmux split-window -t 2 -v
tmux select-pane -t 0

tmux send-keys -t 1 "nload s6-eth2"  ENTER
tmux send-keys -t 2 "nload s6-eth4"  ENTER
tmux send-keys -t 3 "nload s6-eth3"  ENTER

tmux send "nload s6-eth1" ENTER