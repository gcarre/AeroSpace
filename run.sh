#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

supervise_flag='--aerospace-internal-supervise'

if [[ "${1:-}" == "$supervise_flag" ]]; then
    shift
    run_id="$1"
    started_epoch="$2"
    log_file="$3"
    crash_dir="$4"
    pid_file="$5"
    exit_status_file="$6"
    shift 6

    mkdir -p "$(dirname "$log_file")" "$crash_dir"
    {
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] Starting .debug/AeroSpaceApp"
        echo "Run ID: $run_id"
    } >>"$log_file"

    set +e
    ./.debug/AeroSpaceApp "$@" >>"$log_file" 2>&1 &
    aerospace_pid=$!
    echo "$aerospace_pid" >"$pid_file"
    wait "$aerospace_pid"
    app_status=$?
    set -e

    {
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] AeroSpaceApp exited with status $app_status"
        echo "Exit status: $app_status"
    } >>"$log_file"
    echo "$app_status" >"$exit_status_file"

    # CrashReporter writes asynchronously, so give it a few seconds to finish.
    diagnostic_dir="${AEROSPACE_DIAGNOSTIC_REPORT_DIR:-${HOME}/Library/Logs/DiagnosticReports}"
    shopt -s nullglob
    for _ in {1..10}; do
        copied_crash=false
        for report in "$diagnostic_dir"/AeroSpaceApp-*.ips "$diagnostic_dir"/AeroSpaceApp-*.crash; do
            report_mtime="$(stat -f '%m' "$report")"
            if (( report_mtime >= started_epoch )); then
                destination="$crash_dir/$(basename "$report")"
                if [[ ! -e "$destination" ]]; then
                    cp -p "$report" "$destination"
                    echo "Crash report: $destination" >>"$log_file"
                fi
                copied_crash=true
            fi
        done
        if [[ "$copied_crash" == true || "$app_status" -eq 0 ]]; then
            break
        fi
        sleep 1
    done

    exit "$app_status"
fi

if [[ ! -x ./.debug/AeroSpaceApp ]]; then
    echo "Missing .debug/AeroSpaceApp. Run ./build-debug.sh first." >&2
    exit 1
fi

run_id="$(date '+%Y%m%d-%H%M%S')-$$"
log_dir="${AEROSPACE_LOG_DIR:-$PWD/.debug/logs}"
log_file="${AEROSPACE_LOG_FILE:-$log_dir/AeroSpaceApp-$run_id.log}"
crash_dir="${AEROSPACE_CRASH_DIR:-$log_dir/crashes}"
pid_file="$log_dir/AeroSpaceApp-$run_id.pid"
exit_status_file="$log_dir/AeroSpaceApp-$run_id.exit-status"
started_epoch="$(date '+%s')"
script_path="$PWD/run.sh"

mkdir -p "$log_dir" "$crash_dir"
nohup "$script_path" "$supervise_flag" "$run_id" "$started_epoch" "$log_file" "$crash_dir" "$pid_file" "$exit_status_file" "$@" </dev/null >/dev/null 2>&1 &
supervisor_pid=$!
disown "$supervisor_pid" 2>/dev/null || true

# The supervisor writes the application PID immediately after launching it.
for _ in {1..20}; do
    [[ -s "$pid_file" ]] && break
    sleep 0.05
done
if [[ ! -s "$pid_file" ]]; then
    echo "AeroSpace supervisor failed to start the app. Check: $log_file" >&2
    exit 1
fi
aerospace_pid="$(<"$pid_file")"

echo "AeroSpace debug build started (PID $aerospace_pid)"
echo "Logs: $log_file"
echo "Crash reports: $crash_dir"
