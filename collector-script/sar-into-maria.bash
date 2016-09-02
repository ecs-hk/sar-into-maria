#!/bin/bash

# Managed by CFEngine

# Intended to be run as a cronjob - every ten to thirty minutes. Each time it
# runs it will process sar data starting from "one hour ago".
#
# To preserve (rather than clean up) the output files to diagnose problems,
# call the script with the "debug" parameter.

# -------------------------------------------------------------------------------- #
#                       VARIABLE DEFINITIONS
# -------------------------------------------------------------------------------- #

PATH=/bin:/usr/bin

if [ "${1}" == "debug" ] ; then
        readonly _debug='on'
fi

readonly _uqhost="${HOSTNAME%%.*}"

readonly _sar_output="$(mktemp)"
readonly _matches="$(mktemp)"
readonly _errors="$(mktemp)"
readonly _sql="$(mktemp)"

readonly _maria_conn='/usr/local/etc/sar-into-maria.json'

# -------------------------------------------------------------------------------- #
#                       FUNCTIONS
# -------------------------------------------------------------------------------- #

errout() {
        local _this="${0##*/}"
        local _msg="${_this}: ${1} (Try: '${_this} debug')"

        logger -p local3.err "${_msg}"
        printf '%s\n' "${_msg}" >> "${_errors}"

        if [ -z "${_debug}" ] ; then
                cleanup
        fi

	exit 1
}

cleanup() {
        rm -f "${_sar_output}" "${_matches}" "${_errors}" "${_sql}"
}

sleep_a_bit() {
	sleep ${RANDOM: 0: 2}
}

audit_cli() {
        local _i
        for _i in jq sadf mysql gawk ; do
                which "${_i}" >/dev/null 2>&1

                if [ ${?} -ne 0 ] ; then
                        errout "Cannot run without (${_i}) in my PATH"
                fi
        done
}

suck_in_database_connection_info() {
        local _i

        if [ ! -e "${_maria_conn}" ] ; then
                errout "DB connection info file (${_maria_conn}) does not exist"
        fi

        readonly _my_host="$(jq -r '.host' ${_maria_conn})"
        readonly _my_port="$(jq -r '.port' ${_maria_conn})"
        readonly _my_user="$(jq -r '.user' ${_maria_conn})"
        readonly _my_password="$(jq -r '.password' ${_maria_conn})"
        readonly _my_database="$(jq -r '.database' ${_maria_conn})"

        for _i in "${_my_host}" "${_my_port}" "${_my_user}"                     \
        "${_my_password}" "${_my_database}" ; do
                if [ -z "${_i}" ] || [ "${_i}" == "null" ] ; then
                        errout "DB connection info (${_maria_conn}) is incomplete"
                fi
        done
}

set_sadf_options() {
        local _o

        # We wish to gather epoch timestamp for all our sar(1) entries;
        # however, EL6 prints epoch by default (i.e. no -U option exists)
        # and other OSes require the -U option to print epoch. Instead
        # of screwing around with OS detection, let's just see if the
        # -U option works. If so, use it.
        sadf -U >/dev/null 2>&1

        if [ ${?} -eq 0 ] ; then
                _o="-U"
        fi

        readonly _sadf_opt="${_o}"
}

set_sar_options() {
        local _o

        # Set the start time to one hour ago (%T is HH:MM:SS).
        _o="-s $(date --date='-1 hour' +%T)"

        readonly _sar_opt="${_o}"
}

audit_int() {
        # Validate that we have grabbed looks like an integer.
        grep -E '^[0-9]+$' <<<"${1}" >/dev/null 2>&1

        if [ ${?} -ne 0 ] ; then
                errout 'Value (${1}) does not look like a number'
        fi
}

audit_float() {
        # Validate that we have grabbed floating point data.
        grep -E '^[0-9]+\.[0-9]{2}$' <<<"${1}" >/dev/null 2>&1

        if [ ${?} -ne 0 ] ; then
                errout 'Value (${1}) does not look like a floating point'
        fi
}

build_sar_data_matches_file() {
        cp /dev/null "${_matches}"
        grep -E "${1}" "${_sar_output}" > "${_matches}"  2>> "${_errors}"

        if [ ${?} -ne 0 ] ; then
                errout "regex (${1}) did not match any sar data"
        fi
}

generate_sql_upserts() {
        local _regex="${1}"
        local _table_col="${2}"
        local _table
        local _epoch_secs
        local _percent
        local _val
        local _cpu_num
        local _rc

        build_sar_data_matches_file "${_regex}"

        while read -r _line ; do
                unset _sql_upsert

                _epoch_secs="$(gawk '{print $3}' <<<${_line})"
                audit_int "${_epoch_secs}"

                case "${_table_col}" in
                RAM*|Swap*)     _percent="$(gawk '{print $6}' <<<${_line})"
                                audit_float "${_percent}"

                                _table='QuickPerf'
                                build_quickperf_sql                             \
                                "${_table}" "${_table_col}"                     \
                                "${_epoch_secs}" "${_percent}"
                                ;;
                CPU*)           _percent="$(gawk '{print $6}' <<<${_line})"
                                audit_float "${_percent}"

                                _cpu_num="$(gawk '{print $4}' <<<${_line})"

                                # Summarized (all) CPU lines go into the
                                # QuickPerf table.
                                if [ "${_cpu_num}" == "all" ] ; then
                                        _table='QuickPerf'
                                        build_quickperf_sql                     \
                                        "${_table}" "${_table_col}"             \
                                        "${_epoch_secs}" "${_percent}"
                                else
                                        _cpu_num="${_cpu_num//cpu/}"
                                        audit_int "${_cpu_num}"

                                        _table='CPU'
                                        build_cpu_sql                           \
                                        "${_table}" "${_table_col}"             \
                                        "${_epoch_secs}" "${_percent}"          \
                                        "${_cpu_num}"
                                fi
                                ;;
                IO*|Queue*)     _val="$(gawk '{print $6}' <<<${_line})"
                                audit_float "${_val}"

                                _dev_name="$(gawk '{print $4}' <<<${_line})"

                                _table='Disk'
                                build_disk_sql                                  \
                                "${_table}" "${_table_col}"                     \
                                "${_epoch_secs}" "${_val}" "${_dev_name}"
                                ;;
                *)              errout "Invalid column name"
                                ;;
                esac

                printf '%s\n' "${_sql_upsert}" >> "${_sql}"

                if [ ${?} -ne 0 ] ; then
                        errout "Cannot write SQL to ${_sql}"
                fi
        done < "${_matches}"
}

build_quickperf_sql() {
        local _q

        _q="INSERT INTO ${1} (Hostname,LoggedTime,${2})"
        _q="${_q} VALUES ('${_uqhost}',FROM_UNIXTIME(${3}),${4})"
        _q="${_q} ON DUPLICATE KEY UPDATE ${2}=${4};"

        _sql_upsert="${_q}"
}

build_cpu_sql() {
        local _q

        _q="INSERT INTO ${1} (Hostname,LoggedTime,CPUNumber,${2})"
        _q="${_q} VALUES ('${_uqhost}',FROM_UNIXTIME(${3}),${5},${4})"
        _q="${_q} ON DUPLICATE KEY UPDATE ${2}=${4};"

        _sql_upsert="${_q}"
}

build_disk_sql() {
        local _q

        _q="INSERT INTO ${1} (Hostname,LoggedTime,Devname,${2})"
        _q="${_q} VALUES ('${_uqhost}',FROM_UNIXTIME(${3}),'${5}',${4})"
        _q="${_q} ON DUPLICATE KEY UPDATE ${2}=${4};"

        _sql_upsert="${_q}"
}

gather_sar_output() {
        local _rc=0

        (       sadf -p ${_sadf_opt} -- ${_sar_opt} -r -S &&                    \
                sadf -p ${_sadf_opt} -- ${_sar_opt} -P ALL &&                   \
                sadf -p ${_sadf_opt} -- ${_sar_opt} -p -d                       \
        )       > "${_sar_output}" 2>> "${_errors}"

        if [ ${?} -ne 0 ] ; then
                errout "Problem querying sar for reports"
        fi
}

check_for_empty_sar_data_if_it_is_just_after_midnight() {
        local _hour="$(date +%H)"

        # If the file is empty, and we're in the midnight hour, it means
        # we don't have any sar data to process yet. Get out quietly.
        if [ "${_hour}" == "00" ] && [ ! -s "${_sar_output}" ] ; then
                return 1
        fi

        return 0
}

write_to_database() {
        mysql                                                                   \
        --host="${_my_host}"                                                    \
        --port="${_my_port}"                                                    \
        --user="${_my_user}"                                                    \
        --password="${_my_password}"                                            \
        --database="${_my_database}"                                            \
        < "${_sql}"                                                             \
        > "${_errors}" 2>&1

        if [ ${?} -ne 0 ] ; then
                errout "Error during DB connect/update"
        fi
}

# -------------------------------------------------------------------------------- #
#                       MAIN LOGIC
# -------------------------------------------------------------------------------- #

audit_cli
suck_in_database_connection_info
set_sadf_options
set_sar_options

gather_sar_output
check_for_empty_sar_data_if_it_is_just_after_midnight

if [ ${?} -eq 1 ] ; then
        exit 0
fi

generate_sql_upserts "\s(all|cpu[0-9])+\s+%+idle\s" "CPUIdlePct"
generate_sql_upserts "\s(all|cpu[0-9])+\s+%+iowait\s" "CPUIOWaitPct"
generate_sql_upserts "\s%+memused\s" "RAMUsedPct"
generate_sql_upserts "\s%+swpused\s" "SwapUsedPct"
generate_sql_upserts "\s%+util\s" "IOUtilPct"
generate_sql_upserts "\sawait\s" "IOWaitMsecsAvg"
generate_sql_upserts "\savgqu-sz\s" "QueueLengthAvg"

if [ -z "${_debug}" ] ; then
        sleep_a_bit
        write_to_database
        cleanup
else
        printf '%s\n%s\n%s\n%s\n%s\n'                                           \
        'Debug mode is on. No DB updates. See:'                                 \
        "sar output: ${_sar_output}"                                            \
        "Last regex match: ${_matches}"                                         \
        "Errors: ${_errors}"                                                    \
        "Generated SQL upserts: ${_sql}"
fi

exit 0
