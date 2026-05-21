#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_NAME="${OPENMUX_PROCESS_NAME:-OpenMUXApp}"
OUT_ROOT="${POWER_PROFILE_OUT_ROOT:-$ROOT_DIR/.build/power-profile}"
POLL_SECONDS="${POWER_PROFILE_POLL_SECONDS:-5}"
SAMPLE_SECONDS="${POWER_PROFILE_SAMPLE_SECONDS:-5}"
ENABLE_POWERMETRICS="${POWER_PROFILE_ENABLE_POWERMETRICS:-0}"
LABEL="${POWER_PROFILE_LABEL:-}"
WAIT_SECONDS="${POWER_PROFILE_WAIT_SECONDS:-1}"
CLEANED_UP=0

usage() {
  cat <<'EOF'
Usage: Scripts/capture-openmux-power-profile.sh [options]

Run in a separate terminal, then launch and use OpenMUX normally.
Press Ctrl-C when you want the script to stop and generate a report.

Options:
  --label <name>           Optional label included in output directory names
  --out-dir <path>         Root directory for capture artifacts
  --poll-seconds <n>       Interval between lightweight ps snapshots (default: 5)
  --sample-seconds <n>     Duration for the final sample capture (default: 5)
  --powermetrics           Also run powermetrics during final capture
  --help                   Show this help text

Environment overrides:
  POWER_PROFILE_LABEL
  POWER_PROFILE_OUT_ROOT
  POWER_PROFILE_POLL_SECONDS
  POWER_PROFILE_SAMPLE_SECONDS
  POWER_PROFILE_ENABLE_POWERMETRICS=1
  POWER_PROFILE_WAIT_SECONDS
  OPENMUX_PROCESS_NAME
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      shift
      LABEL="${1:-}"
      ;;
    --out-dir)
      shift
      OUT_ROOT="${1:-}"
      ;;
    --poll-seconds)
      shift
      POLL_SECONDS="${1:-}"
      ;;
    --sample-seconds)
      shift
      SAMPLE_SECONDS="${1:-}"
      ;;
    --powermetrics)
      ENABLE_POWERMETRICS=1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      printf "Unknown option: %s\n\n" "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

sanitize_slug() {
  value="$(printf '%s' "$1" | tr '/[:space:]' '--' | tr -cd 'A-Za-z0-9._-')"
  if [ -z "$value" ]; then
    value="unnamed"
  fi
  printf '%s' "$value"
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

latest_app_pid() {
  pgrep -x "$APP_NAME" 2>/dev/null | tail -n 1
}

current_timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

thread_count_for_pid() {
  ps -M -p "$1" 2>/dev/null | awk '
    NR == 1 { next }
    { count += 1 }
    END { print count + 0 }
  '
}

append_process_snapshot() {
  pid="$1"
  timestamp="$2"
  threads="$(thread_count_for_pid "$pid")"
  ps -o pid=,etime=,%cpu=,rss=,state=,command= -p "$pid" \
    | awk -v ts="$timestamp" -v threads="$threads" '
        NF {
          pid=$1; etime=$2; cpu=$3; rss=$4; state=$5
          $1=$2=$3=$4=$5=""
          sub(/^[[:space:]]+/, "", $0)
          printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", ts, pid, etime, cpu, rss, threads, state, $0
        }
      '
}

write_final_ps_snapshot() {
  pid="$1"
  threads="$(thread_count_for_pid "$pid")"
  {
    printf "PID ELAPSED %%CPU RSS_KB THREADS STATE COMMAND\n"
    ps -o pid=,etime=,%cpu=,rss=,state=,command= -p "$pid" \
      | awk -v threads="$threads" '
          NF {
            pid=$1; etime=$2; cpu=$3; rss=$4; state=$5
            $1=$2=$3=$4=$5=""
            sub(/^[[:space:]]+/, "", $0)
            printf "%s %s %s %s %s %s %s\n", pid, etime, cpu, rss, threads, state, $0
          }
        '
  } >"$FINAL_PS_FILE"
}

branch_name="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown-branch')"
branch_slug="$(sanitize_slug "$branch_name")"
commit_sha="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
dirty_state="clean"
if ! git -C "$ROOT_DIR" diff --quiet --ignore-submodules HEAD -- 2>/dev/null; then
  dirty_state="dirty"
fi

run_slug="$(date '+%Y%m%d-%H%M%S')-${branch_slug}"
if [ -n "$LABEL" ]; then
  run_slug="${run_slug}-$(sanitize_slug "$LABEL")"
fi

RUN_DIR="$OUT_ROOT/$run_slug"
TIMELINE_FILE="$RUN_DIR/process-timeline.tsv"
LIFECYCLE_FILE="$RUN_DIR/lifecycle.log"
METADATA_FILE="$RUN_DIR/metadata.txt"
FINAL_PS_FILE="$RUN_DIR/final.ps.txt"
FINAL_TOP_FILE="$RUN_DIR/final.top.txt"
FINAL_SAMPLE_FILE="$RUN_DIR/final.sample.txt"
FINAL_VMMAP_FILE="$RUN_DIR/final.vmmap.txt"
FINAL_POWERMETRICS_FILE="$RUN_DIR/final.powermetrics.txt"
FINAL_SIGNAL_FILE="$RUN_DIR/final.sample.signals.txt"
REPORT_FILE="$RUN_DIR/report.md"
STOP_FILE="$RUN_DIR/.stop"

mkdir -p "$RUN_DIR"
rm -f "$STOP_FILE"

cat >"$METADATA_FILE" <<EOF
capture_started_at=$(current_timestamp)
repository=$ROOT_DIR
branch=$branch_name
commit=$commit_sha
git_state=$dirty_state
process_name=$APP_NAME
poll_seconds=$POLL_SECONDS
sample_seconds=$SAMPLE_SECONDS
powermetrics_enabled=$ENABLE_POWERMETRICS
hostname=$(scutil --get LocalHostName 2>/dev/null || hostname)
os_version=$(sw_vers -productVersion 2>/dev/null || uname -r)
EOF

printf "timestamp\tpid\tetime\tcpu\trss_kb\tthreads\tstate\tcommand\n" >"$TIMELINE_FILE"
: >"$LIFECYCLE_FILE"

printf "Waiting for %s to appear. Output: %s\n" "$APP_NAME" "$RUN_DIR"
printf "Branch: %s (%s, %s)\n" "$branch_name" "$commit_sha" "$dirty_state"
printf "Press Ctrl-C when you want to stop the capture and generate the report.\n"

MONITORED_PID=""
while [ -z "$MONITORED_PID" ]; do
  MONITORED_PID="$(latest_app_pid || true)"
  if [ -z "$MONITORED_PID" ]; then
    sleep "$WAIT_SECONDS"
  fi
done

printf "%s attached pid=%s\n" "$(current_timestamp)" "$MONITORED_PID" | tee -a "$LIFECYCLE_FILE" >/dev/null

monitor_loop() {
  current_pid="$MONITORED_PID"
  while [ ! -f "$STOP_FILE" ]; do
    next_pid="$(latest_app_pid || true)"
    timestamp="$(current_timestamp)"

    if [ -n "$next_pid" ] && [ "$next_pid" != "$current_pid" ]; then
      current_pid="$next_pid"
      printf "%s attached pid=%s\n" "$timestamp" "$current_pid" >>"$LIFECYCLE_FILE"
    fi

    if [ -n "$current_pid" ] && kill -0 "$current_pid" 2>/dev/null; then
      append_process_snapshot "$current_pid" "$timestamp" >>"$TIMELINE_FILE"
    else
      if [ -n "$current_pid" ]; then
        printf "%s missing pid=%s\n" "$timestamp" "$current_pid" >>"$LIFECYCLE_FILE"
      else
        printf "%s no-process\n" "$timestamp" >>"$LIFECYCLE_FILE"
      fi
      current_pid=""
    fi

    sleep "$POLL_SECONDS"
  done
}

monitor_loop &
MONITOR_PID=$!

capture_signal_summary() {
  sample_file="$1"
  {
    printf "renderer_frames=%s\n" "$(grep -Ec 'renderer\.generic\.Renderer\(renderer\.Metal\)\.(drawFrame|updateFrame)' "$sample_file" || true)"
    printf "cvdisplaylink=%s\n" "$(grep -Ec 'CVDisplayLink' "$sample_file" || true)"
    printf "quartzcore_commits=%s\n" "$(grep -Ec 'CA::Transaction::commit|CA::Context::commit_transaction' "$sample_file" || true)"
    printf "metal_queue_submits=%s\n" "$(grep -Ec '_MTLCommandQueue|IOGPUMetalCommandQueue|IOGPUMetalCommandBuffer' "$sample_file" || true)"
    printf "iosurface=%s\n" "$(grep -Ec 'IOSurface' "$sample_file" || true)"
    printf "icon_refresh=%s\n" "$(grep -Ec 'refreshTerminalAppIconsIfNeeded|iconKindSignature' "$sample_file" || true)"
    printf "terminal_text_snapshot=%s\n" "$(grep -Ec 'terminalTextSnapshot' "$sample_file" || true)"
  } >"$FINAL_SIGNAL_FILE"
}

generate_report() {
  end_timestamp="$(current_timestamp)"
  latest_pid="$(latest_app_pid || true)"
  if [ -n "$latest_pid" ] && kill -0 "$latest_pid" 2>/dev/null; then
    write_final_ps_snapshot "$latest_pid" || true
    top -l 1 -pid "$latest_pid" -stats pid,command,cpu,mem,threads,time >"$FINAL_TOP_FILE" 2>&1 || true
    sample "$latest_pid" "$SAMPLE_SECONDS" 1 >"$FINAL_SAMPLE_FILE" 2>&1 || true
    vmmap -summary "$latest_pid" >"$FINAL_VMMAP_FILE" 2>&1 || true
    if [ "$ENABLE_POWERMETRICS" = "1" ]; then
      if have_command powermetrics; then
        sudo powermetrics --samplers tasks --show-process-energy -n 1 -i 1000 >"$FINAL_POWERMETRICS_FILE" 2>&1 || true
      else
        printf "powermetrics unavailable\n" >"$FINAL_POWERMETRICS_FILE"
      fi
    else
      printf "powermetrics capture disabled; rerun with --powermetrics to enable\n" >"$FINAL_POWERMETRICS_FILE"
    fi
    capture_signal_summary "$FINAL_SAMPLE_FILE"
  else
    printf "OpenMUXApp was not running during final capture\n" >"$FINAL_PS_FILE"
    printf "OpenMUXApp was not running during final capture\n" >"$FINAL_TOP_FILE"
    printf "OpenMUXApp was not running during final capture\n" >"$FINAL_SAMPLE_FILE"
    printf "OpenMUXApp was not running during final capture\n" >"$FINAL_VMMAP_FILE"
    printf "OpenMUXApp was not running during final capture\n" >"$FINAL_POWERMETRICS_FILE"
    printf "renderer_frames=0\ncvdisplaylink=0\nquartzcore_commits=0\nmetal_queue_submits=0\niosurface=0\nicon_refresh=0\nterminal_text_snapshot=0\n" >"$FINAL_SIGNAL_FILE"
  fi

  timeline_summary="$(
    awk '
      BEGIN {
        max_cpu = -1
        max_rss = -1
        max_threads = -1
        first_ts = ""
        last_ts = ""
        samples = 0
      }
      NR > 1 && NF >= 7 {
        samples += 1
        if (first_ts == "") first_ts = $1
        last_ts = $1
        cpu = $4 + 0
        rss = $5 + 0
        threads = $6 + 0
        if (cpu > max_cpu) max_cpu = cpu
        if (rss > max_rss) max_rss = rss
        if (threads > max_threads) max_threads = threads
      }
      END {
        printf "samples=%d\nfirst=%s\nlast=%s\nmax_cpu=%.2f\nmax_rss=%d\nmax_threads=%d\n",
          samples, first_ts, last_ts, max_cpu, max_rss, max_threads
      }
    ' "$TIMELINE_FILE"
  )"

  samples_collected="$(printf '%s\n' "$timeline_summary" | awk -F= '/^samples=/{print $2}')"
  first_sample_at="$(printf '%s\n' "$timeline_summary" | awk -F= '/^first=/{print $2}')"
  last_sample_at="$(printf '%s\n' "$timeline_summary" | awk -F= '/^last=/{print $2}')"
  max_cpu="$(printf '%s\n' "$timeline_summary" | awk -F= '/^max_cpu=/{print $2}')"
  max_rss="$(printf '%s\n' "$timeline_summary" | awk -F= '/^max_rss=/{print $2}')"
  max_threads="$(printf '%s\n' "$timeline_summary" | awk -F= '/^max_threads=/{print $2}')"

  renderer_frames="$(awk -F= '/^renderer_frames=/{print $2}' "$FINAL_SIGNAL_FILE")"
  cvdisplaylink="$(awk -F= '/^cvdisplaylink=/{print $2}' "$FINAL_SIGNAL_FILE")"
  quartzcore_commits="$(awk -F= '/^quartzcore_commits=/{print $2}' "$FINAL_SIGNAL_FILE")"
  metal_queue_submits="$(awk -F= '/^metal_queue_submits=/{print $2}' "$FINAL_SIGNAL_FILE")"
  iosurface_hits="$(awk -F= '/^iosurface=/{print $2}' "$FINAL_SIGNAL_FILE")"
  icon_refresh_hits="$(awk -F= '/^icon_refresh=/{print $2}' "$FINAL_SIGNAL_FILE")"
  terminal_text_snapshot_hits="$(awk -F= '/^terminal_text_snapshot=/{print $2}' "$FINAL_SIGNAL_FILE")"

  cat >"$REPORT_FILE" <<EOF
# OpenMUX Runtime Power Profile

- capture_started_at: $(awk -F= '/^capture_started_at=/{print $2}' "$METADATA_FILE")
- capture_finished_at: $end_timestamp
- repository: $ROOT_DIR
- branch: $branch_name
- commit: $commit_sha
- git_state: $dirty_state
- process_name: $APP_NAME
- output_dir: $RUN_DIR

## Timeline summary

- samples_collected: $samples_collected
- first_sample_at: $first_sample_at
- last_sample_at: $last_sample_at
- max_cpu_percent: $max_cpu
- max_rss_kb: $max_rss
- max_threads: $max_threads

## Final sample signal counts

- renderer_frames: $renderer_frames
- cvdisplaylink: $cvdisplaylink
- quartzcore_commits: $quartzcore_commits
- metal_queue_submits: $metal_queue_submits
- iosurface_hits: $iosurface_hits
- icon_refresh_hits: $icon_refresh_hits
- terminal_text_snapshot_hits: $terminal_text_snapshot_hits

## Artifacts

- metadata: \`$METADATA_FILE\`
- lifecycle log: \`$LIFECYCLE_FILE\`
- timeline: \`$TIMELINE_FILE\`
- final ps: \`$FINAL_PS_FILE\`
- final top: \`$FINAL_TOP_FILE\`
- final sample: \`$FINAL_SAMPLE_FILE\`
- final vmmap: \`$FINAL_VMMAP_FILE\`
- final powermetrics: \`$FINAL_POWERMETRICS_FILE\`
- final signal summary: \`$FINAL_SIGNAL_FILE\`

## Share with Copilot

Share this report plus the raw artifact files above, especially:

1. \`report.md\`
2. \`final.sample.txt\`
3. \`process-timeline.tsv\`
4. \`final.ps.txt\`
5. \`final.top.txt\`
6. \`final.vmmap.txt\`

Optional notes to include when sharing:

- what workflow you exercised
- whether inactive workspaces kept running visible commands
- whether switching back showed current output immediately
- whether the app was hidden, minimized, or fully visible during the idle window
EOF
}

cleanup() {
  if [ "$CLEANED_UP" = "1" ]; then
    return
  fi
  CLEANED_UP=1
  : >"$STOP_FILE"
  if kill -0 "$MONITOR_PID" 2>/dev/null; then
    wait "$MONITOR_PID" 2>/dev/null || true
  fi
  generate_report
  printf "\nCapture complete. Report: %s\n" "$REPORT_FILE"
}

handle_interrupt() {
  cleanup
  exit 0
}

trap handle_interrupt INT TERM
trap cleanup EXIT

while :; do
  sleep 3600
done
