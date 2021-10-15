#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/src/jq_to_psql_records.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/assert_record_count.bash"