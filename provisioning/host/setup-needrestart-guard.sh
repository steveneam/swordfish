#!/usr/bin/env bash
set -uo pipefail

# setup-needrestart-guard.sh - stop apt from killing every agent on the box.
#
# THE INCIDENT (2026-07-17 10:17:31 UTC, swordfish's own doing): a routine
# `apt-get install postgresql-17` on syd4 pulled a shared library (libpq5), and
# Ubuntu's needrestart - configured `$nrconf{restart} = 'a'` (AUTOMATIC) - then
# helpfully restarted every service linking it. Including code-server:
#
#   10:17:19  apt-get install -y -qq postgresql-17 postgresql-client-17
#   10:17:31  Stopping code-server.service ...
#   10:17:31  Started  code-server.service
#
# Every process in code-server's cgroup died with it. Agent sessions in
# `agent-tmux.service` survived (the 2026-07-16 fix working exactly as designed);
# the tenant agent living in a PLAIN code-server shell - a deliberate founder
# call - was killed mid-run.
#
# WHY THE EXISTING RULE DID NOT SAVE US: the standing lesson is "never restart
# code-server while agents run". Nobody restarted it. **apt did.** A rule phrased
# as an instruction to a human only binds the humans who read it; needrestart is
# not a reader. So the rule becomes config, here, where apt has to obey it.
#
# WHAT THIS DOES: tells needrestart to NEVER auto-restart the services that own
# agent lifetime. They still get flagged as needing a restart - the operator
# does it deliberately, at a moment of their choosing, when no agent is mid-run.
# This is not "ignore the update"; it is "do not choose the moment for me".
#
# Idempotent. Safe to re-run. Verifies by asserting the parsed config.

CONF=/etc/needrestart/conf.d/90-swordfish-agents.conf
changed=0

read -r -d '' BODY <<'EOF'
# Managed by swordfish: provisioning/host/setup-needrestart-guard.sh
# DO NOT hand-edit - re-run the script instead.
#
# Never let apt/needrestart auto-restart the services that own agent lifetime.
# A restart of code-server kills every process in its cgroup, including any
# agent session running in a plain terminal (2026-07-17 incident: an
# `apt install` restarted code-server and killed a tenant agent mid-run).
# These stay flagged-but-not-restarted: a human restarts them deliberately,
# when nothing is mid-flight.
$nrconf{override_rc}{qr(^code-server)} = 0;
$nrconf{override_rc}{qr(^agent-tmux)} = 0;
EOF

if ! sudo -n test -f "$CONF" || ! sudo -n cmp -s <(printf '%s\n' "$BODY") "$CONF"; then
    sudo -n install -d -m 755 /etc/needrestart/conf.d
    printf '%s\n' "$BODY" | sudo -n tee "$CONF" >/dev/null
    sudo -n chmod 644 "$CONF"
    changed=1
    echo "== installed $CONF"
else
    echo "== $CONF already current"
fi

echo
echo "== verify"
fails=0
ck() { if bash -c "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

ck "guard file present"            "sudo -n test -f $CONF"
ck "code-server override present"  "sudo -n grep -q 'override_rc.*code-server' $CONF"
ck "agent-tmux override present"   "sudo -n grep -q 'override_rc.*agent-tmux' $CONF"
# needrestart parses conf.d/*.conf as perl; a syntax error there breaks EVERY
# future apt run, so prove it parses rather than assuming
ck "needrestart still parses its config" "sudo -n needrestart -p >/dev/null 2>&1 || sudo -n needrestart -b >/dev/null 2>&1"
# the real proof: ask needrestart what it WOULD restart; code-server must not appear
ck "code-server not in needrestart's restart set" \
   "! sudo -n needrestart -b 2>/dev/null | grep -qi 'NEEDRESTART-SVC: code-server'"

echo
if [ "$fails" -eq 0 ]; then
    echo "== converged: apt can no longer auto-restart code-server ($changed change-set)"
    echo "   NOTE: this guards the DEFAULT path. Any script doing its own apt work"
    echo "   should ALSO pass NEEDRESTART_MODE=l for belt-and-braces."
    exit 0
fi
echo "== $fails assertion(s) FAILED"
exit 1
