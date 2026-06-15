#!/usr/bin/env bash
set -euo pipefail

target="${1:-net/ipv4/tcp_bbr.c}"

if [[ ! -f "$target" ]]; then
  echo "BBRv3 source file not found: $target" >&2
  exit 1
fi

if ! grep -q '^#define BBR_VERSION[[:space:]]*3' "$target"; then
  echo "BBRv3 max profile requires BBR_VERSION=3 in $target." >&2
  exit 1
fi

python3 - "$target" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

replacements = {
    r"static const u32 bbr_probe_rtt_win_ms = .*?;": "static const u32 bbr_probe_rtt_win_ms = 10000;",
    r"static const u32 bbr_probe_rtt_cwnd_gain = .*?;": "static const u32 bbr_probe_rtt_cwnd_gain = BBR_UNIT * 2;",
    r"static const u32 bbr_probe_rtt_mode_ms = .*?;": "static const u32 bbr_probe_rtt_mode_ms = 10;",
    r"static const u32 bbr_tso_rtt_shift = .*?;": "static const u32 bbr_tso_rtt_shift = 2;",
    r"static const int bbr_pacing_margin_percent = .*?;": "static const int bbr_pacing_margin_percent = 0;",
    r"static const int bbr_startup_pacing_gain = .*?;": "static const int bbr_startup_pacing_gain = BBR_UNIT * 4;",
    r"static const int bbr_startup_cwnd_gain = .*?;": "static const int bbr_startup_cwnd_gain = BBR_UNIT * 4;",
    r"static const int bbr_drain_gain = .*?;": "static const int bbr_drain_gain = BBR_UNIT / 2;",
    r"static const int bbr_cwnd_gain  = .*?;": "static const int bbr_cwnd_gain  = BBR_UNIT * 4;",
    r"static const u32 bbr_cwnd_min_target = .*?;": "static const u32 bbr_cwnd_min_target = 64;",
    r"static const u32 bbr_full_bw_thresh = .*?;": "static const u32 bbr_full_bw_thresh = BBR_UNIT * 101 / 100;",
    r"static const u32 bbr_full_bw_cnt = .*?;": "static const u32 bbr_full_bw_cnt = 16;",
    r"static const int bbr_extra_acked_gain = .*?;": "static const int bbr_extra_acked_gain = BBR_UNIT * 4;",
    r"static const u32 bbr_extra_acked_max_us = .*?;": "static const u32 bbr_extra_acked_max_us = 750 * 1000;",
    r"static const bool bbr_precise_ece_ack = .*?;": "static const bool bbr_precise_ece_ack = true;",
    r"static const u32 bbr_ecn_max_rtt_us = .*?;": "static const u32 bbr_ecn_max_rtt_us = 0;",
    r"static const u32 bbr_beta = .*?;": "static const u32 bbr_beta = BBR_UNIT * 5 / 100;",
    r"static const u32 bbr_ecn_alpha_gain = .*?;": "static const u32 bbr_ecn_alpha_gain = BBR_UNIT * 1 / 64;",
    r"static const u32 bbr_ecn_alpha_init = .*?;": "static const u32 bbr_ecn_alpha_init = BBR_UNIT * 1 / 4;",
    r"static const u32 bbr_ecn_factor = .*?;": "static const u32 bbr_ecn_factor = BBR_UNIT * 5 / 100;",
    r"static const u32 bbr_ecn_thresh = .*?;": "static const u32 bbr_ecn_thresh = BBR_UNIT * 9 / 10;",
    r"static const u32 bbr_ecn_reprobe_gain = .*?;": "static const u32 bbr_ecn_reprobe_gain = BBR_UNIT;",
    r"static const u32 bbr_loss_thresh = [^\n]*": "static const u32 bbr_loss_thresh = BBR_UNIT * 10 / 100;  /* max: tolerate 10% loss before backing off */",
    r"static const bool bbr_loss_probe_recovery = .*?;": "static const bool bbr_loss_probe_recovery = true;",
    r"static const u32 bbr_full_loss_cnt = .*?;": "static const u32 bbr_full_loss_cnt = 24;",
    r"static const u32 bbr_full_ecn_cnt = .*?;": "static const u32 bbr_full_ecn_cnt = 8;",
    r"static const u32 bbr_inflight_headroom = .*?;": "static const u32 bbr_inflight_headroom = BBR_UNIT * 1 / 100;",
    r"static const u32 bbr_bw_probe_cwnd_gain = .*?;": "static const u32 bbr_bw_probe_cwnd_gain = 3;",
    r"static const u32 bbr_bw_probe_max_rounds = .*?;": "static const u32 bbr_bw_probe_max_rounds = 4;",
    r"static const u32 bbr_bw_probe_rand_rounds = .*?;": "static const u32 bbr_bw_probe_rand_rounds = 1;",
    r"static const u32 bbr_bw_probe_base_us = .*?;": "static const u32 bbr_bw_probe_base_us = 100 * 1000;",
    r"static const u32 bbr_bw_probe_rand_us = .*?;": "static const u32 bbr_bw_probe_rand_us = 50 * 1000;",
}

missing = []
for pattern, replacement in replacements.items():
    text, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        missing.append(pattern)

pacing_pattern = re.compile(
    r"static const int bbr_pacing_gain\[\] = \{\n"
    r".*?\n"
    r"\};",
    re.S,
)
pacing_replacement = """static const int bbr_pacing_gain[] = {
\tBBR_UNIT * 7 / 2,\t/* UP: extreme but still feedback-bound */
\tBBR_UNIT / 2,\t\t/* DOWN: preserve a minimal drain phase */
\tBBR_UNIT * 5 / 4,\t/* CRUISE: keep pressure on the pipe */
\tBBR_UNIT * 2,\t\t/* REFILL: refill aggressively */
};"""
text, pacing_count = pacing_pattern.subn(pacing_replacement, text, count=1)
if pacing_count != 1:
    missing.append("static const int bbr_pacing_gain[]")

if missing:
    print("Failed to apply BBRv3 max profile; missing patterns:", file=sys.stderr)
    for item in missing:
        print(f"  {item}", file=sys.stderr)
    sys.exit(1)

path.write_text(text)
PY

grep -nE 'bbr_(startup_pacing_gain|startup_cwnd_gain|cwnd_gain|pacing_gain|beta|loss_thresh|full_loss_cnt|full_ecn_cnt|inflight_headroom|bw_probe_cwnd_gain|probe_rtt_mode_ms|pacing_margin_percent)' "$target"
echo "Applied BBRv3 max profile to $target"
