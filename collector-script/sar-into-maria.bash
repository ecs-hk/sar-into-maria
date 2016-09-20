#!/bin/bash

# Intended to be run as a cronjob shortly after each sar(1) data collection
# period. On most default installs, sar(1) data collection runs at:
#   00, 10, 20, 30, 40, 50
#
# so we'd like to run this script at:
#   03, 13, 23, 33, 43, 53
#
# YMMV. Adapt the run times as needed.

# -------------------------------------------------------------------------------- #
#                       VARIABLE DEFINITIONS
# -------------------------------------------------------------------------------- #

PATH=/bin:/usr/bin

readonly _uqhost="${HOSTNAME%%.*}"

readonly _dout="$(mktemp -d)"
readonly _sar_output="${_dout}/sarout"
readonly _matches="${_dout}/regmatches"
readonly _errors="${_dout}/errors"
readonly _sql="${_dout}/sql"

readonly _maria_conn='/usr/local/etc/sar-into-maria.json'

_just_after_midnight=0

# -------------------------------------------------------------------------------- #
#                       FUNCTIONS
# -------------------------------------------------------------------------------- #

errout() {
        local _msg="${0##*/}: ${1} (See: ${_dout})"

        logger -p local3.err "${_msg}"
        printf '%s\n' "${_msg}" >> "${_errors}"

	exit 1
}

cleanup() {
        rm -fr "${_dout}"
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
        local _t1
        local _t2

        # Set the sar(1) data report start and end times (%T is HH:MM:SS).
        _t1="$(date --date='-30 minutes' +%T)"
        _t2="$(date +%T)"

        # However, if the starting hour is 23 and the ending hour is 00, it
        # means we jumped back into the previous day, which confuses sar(1)
        # queries. In that case, just set start time to midnight exactly.
        if [ "${_t1: 0: 2}" == '23' ] && [ "${_t2: 0: 2}" == '00' ] ; then
                _t1='-s 00:00:00'
                _just_after_midnight=1
        fi

        readonly _sar_opt="-s ${_t1} -e ${_t2}"
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
        cp /dev/null "${_sar_output}"

        (       sadf -p ${_sadf_opt} -- ${_sar_opt} -r -S &&                    \
                sadf -p ${_sadf_opt} -- ${_sar_opt} -P ALL &&                   \
                sadf -p ${_sadf_opt} -- ${_sar_opt} -p -d                       \
        )       >> "${_sar_output}" 2>> "${_errors}"

        if [ ${?} -ne 0 ] ; then
                errout "Problem querying sar for reports"
        fi
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

# If we're just after the midnight hour, it's possible sar(1) doesn't
# have any report data yet. In that case, get out quietly.
if [ ${_just_after_midnight} -eq 1 ] && [ ! -s "${_sar_output}" ] ; then
        cleanup
        exit 0
fi

generate_sql_upserts "\s(all|cpu[0-9])+\s+%+idle\s" "CPUIdlePct"
generate_sql_upserts "\s(all|cpu[0-9])+\s+%+iowait\s" "CPUIOWaitPct"
generate_sql_upserts "\s%+memused\s" "RAMUsedPct"
generate_sql_upserts "\s%+swpused\s" "SwapUsedPct"
generate_sql_upserts "\s%+util\s" "IOUtilPct"
generate_sql_upserts "\sawait\s" "IOWaitMsecsAvg"
generate_sql_upserts "\savgqu-sz\s" "QueueLengthAvg"

sleep_a_bit
write_to_database

cleanup
exit 0
