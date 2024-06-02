#!/bin/bash

# Set the program arguments
program_args="magnet:?xt=urn:btih:64c524ca515256881f4c91e5aabb47e8b15f3bbe"

# Set the breakpoints (optional)
# breakpoint_name="main"

# Load the program
program_path="./torrent_downloader"

# Launch LLDB and run the program
lldb -o "settings set target.run-args $program_args" \
     -o "file $program_path" \
     -o "process launch"

#    -o "breakpoint set --name $breakpoint_name" \
