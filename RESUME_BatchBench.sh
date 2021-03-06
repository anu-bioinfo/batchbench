#/bin/bash

set -euo pipefail

unset http_proxy
unset https_proxy

source_dir="/home/ubuntu/BatchBench/runbb/git_batchbench"
output_dir="${source_dir=}/results"
report_dir="${output_dir}/reports"
$HOME/bin/nextflow run "${source_dir}/main.nf"\
        -profile docker,local\
        -with-report "${report_dir}/report.html"\
        -with-trace "${report_dir}/trace.txt"\
        -with-timeline "${report_dir}/timeline.html"\
        -resume
