#!/usr/bin/env bash
# scripts/lib/lock.sh — File-based lock primitives for apply.sh
#
# Provides serialized access to the Agamemnon reconciliation loop.
# Uses flock(1) for atomic kernel-level locking with PID tracking.
#
# Functions:
#   acquire_lock <lockfile> <force>   — acquire exclusive lock, timeout 60s
#   release_lock <lockfile>           — release lock and remove lockfile
#   break_stale_lock <lockfile>       — remove lockfile if held by a dead PID
#
# Lock file descriptor: 9 (arbitrary, unlikely to conflict with script FDs)

_LOCK_FD=9

# acquire_lock <lockfile> <force>
#
# Opens <lockfile> on fd 9 and acquires an exclusive flock with a 60-second
# timeout. If <force> is 1 and the lockfile already exists, calls
# break_stale_lock first; if the existing lock is held by a live process,
# break_stale_lock exits with an error.
#
# On timeout, prints a message to stderr and exits with code 1.
acquire_lock() {
    local lockfile="$1"
    local force="${2:-0}"

    if [[ "$force" -eq 1 && -f "$lockfile" ]]; then
        break_stale_lock "$lockfile"
    fi

    # Open the lockfile on the dedicated fd (create if missing)
    eval "exec ${_LOCK_FD}>\"${lockfile}\""

    if ! flock -w 60 "${_LOCK_FD}"; then
        echo "ERROR: Could not acquire lock on ${lockfile} within 60 seconds." >&2
        echo "       Another apply.sh process may be running." >&2
        echo "       Use --force to break a stale lock (only if the process is dead)." >&2
        exit 1
    fi

    # Write our PID so stale detection works
    echo "$$" >&"${_LOCK_FD}"
}

# release_lock <lockfile>
#
# Releases the flock by closing fd 9 and removes the lockfile.
# Safe to call even if the lock was never acquired (no-op).
release_lock() {
    local lockfile="$1"

    # Close fd — this drops the flock automatically
    eval "exec ${_LOCK_FD}>&-" 2>/dev/null || true

    rm -f "$lockfile"
}

# break_stale_lock <lockfile>
#
# Reads the PID stored in <lockfile> and checks whether that process is alive.
#
#   - Dead PID  → removes lockfile with a warning, returns 0 (caller may proceed)
#   - Live PID  → prints error with PID and exits with code 1
#   - Unreadable PID in file → treats as stale, removes and warns
break_stale_lock() {
    local lockfile="$1"

    if [[ ! -f "$lockfile" ]]; then
        return 0
    fi

    local pid
    pid="$(cat "$lockfile" 2>/dev/null || true)"

    if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]]; then
        echo "WARNING: Lock file ${lockfile} contains invalid PID '${pid}'. Removing stale lock." >&2
        rm -f "$lockfile"
        return 0
    fi

    if kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: Lock file ${lockfile} is held by PID ${pid} (still running)." >&2
        echo "       Cannot break a live lock. Wait for the process to finish or kill it first." >&2
        exit 1
    else
        echo "WARNING: Removing stale lock file ${lockfile} (PID ${pid} is no longer running)." >&2
        rm -f "$lockfile"
        return 0
    fi
}
