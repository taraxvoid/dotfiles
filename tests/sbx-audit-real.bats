# sbx --audit with the real bwrap and a real systemd user scope: the limits must
# bite. Skipped where bwrap or delegated cgroup controllers are unavailable (macOS,
# CI containers); meant to be run in the disposable Linux VM.

setup() {
  command -v bwrap >/dev/null || skip "bubblewrap not installed"
  bwrap --ro-bind / / true 2>/dev/null || skip "bubblewrap blocked here"
  command -v systemd-run >/dev/null || skip "systemd-run not installed"
  systemd-run --user --scope --quiet -p MemoryMax=64M -p TasksMax=16 true 2>/dev/null ||
    skip "no systemd user scope here"
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
  HOME=$(cd "$HOME" && pwd -P)
  export SBX_BACKEND=bwrap
  sbx=$BATS_TEST_DIRNAME/../.local/bin/sbx
  tree=$BATS_TEST_TMPDIR/tree
  mkdir -p "$tree"
  echo seed >"$tree/seed"
  tree=$(cd "$tree" && pwd -P)
  cd "$BATS_TEST_TMPDIR"
}

@test "the tree is copied to /work and the original is untouched" {
  run "$sbx" --audit "$tree" sh -c 'cat seed && echo changed >seed && touch new && pwd'
  [ "$status" -eq 0 ]
  [[ "$output" == *seed* ]]
  [[ "$output" == */work ]]
  [ "$(cat "$tree/seed")" = seed ]
  [ ! -e "$tree/new" ]
}

@test "only /work is writable" {
  run "$sbx" --audit "$tree" sh -c 'touch /usr/x'
  [ "$status" -ne 0 ]
  run "$sbx" --audit "$tree" sh -c 'touch /run/sbx-tree/x'
  [ "$status" -ne 0 ]
}

@test "HOME is fresh on every call" {
  "$sbx" --audit "$tree" sh -c 'touch "$HOME/planted"'
  run "$sbx" --audit "$tree" sh -c 'test -e "$HOME/planted"'
  [ "$status" -ne 0 ]
}

@test "there is no network" {
  run "$sbx" --audit "$tree" curl -sS -m 5 -o /dev/null https://registry.npmjs.org/
  [ "$status" -ne 0 ]
}

@test "--audit-prepare writes persist in the tree and show up in later copies" {
  run "$sbx" --audit-prepare "$tree" sh -c 'touch built'
  [ "$status" -eq 0 ]
  [ -e "$tree/built" ]
  run "$sbx" --audit "$tree" sh -c 'test -e built'
  [ "$status" -eq 0 ]
}

@test "--audit-prepare cannot write the tree's .git" {
  git init -q "$tree"
  run "$sbx" --audit-prepare "$tree" sh -c 'echo "[core] fsmonitor = evil" >>.git/config'
  [ "$status" -ne 0 ]
  ! grep -q evil "$tree/.git/config"
  run "$sbx" --audit-prepare "$tree" sh -c 'touch built'
  [ "$status" -eq 0 ]
}

@test "the /work tmpfs size caps disk" {
  SBX_AUDIT_WORK_MB=8 run "$sbx" --audit "$tree" sh -c 'dd if=/dev/zero of=big bs=1M count=64'
  [ "$status" -ne 0 ]
}

@test "ulimit -f caps a single file" {
  SBX_AUDIT_FSIZE_MB=1 run "$sbx" --audit "$tree" sh -c 'dd if=/dev/zero of=big bs=1M count=8'
  [ "$status" -ne 0 ]
}

@test "the memory cap kills a runaway allocation" {
  # killed by the memory cap, not by the 300 s runtime cap. Touch 1 GiB for real:
  # `tail /dev/zero` is not a reliable allocator (uutils tail on Ubuntu 26.04 never
  # grew and ran into the runtime cap instead).
  command -v python3 >/dev/null || skip "python3 not installed"
  start=$SECONDS
  SBX_AUDIT_MEM=64M run "$sbx" --audit "$tree" python3 -c 'b"x" * (1 << 30)'
  [ "$status" -ne 0 ]
  [ $((SECONDS - start)) -lt 60 ]
}

@test "the task cap stops a fork flood" {
  SBX_AUDIT_TASKS=20 run "$sbx" --audit "$tree" sh -c 'for i in $(seq 100); do sleep 5 & done; wait'
  [[ "$output" == *[Ff]ork* || "$output" == *"Resource temporarily"* ]]
}

@test "the runtime cap kills a long runner" {
  start=$SECONDS
  SBX_AUDIT_TIME=2 run "$sbx" --audit "$tree" sh -c 'echo started; sleep 60'
  [ "$status" -ne 0 ]
  # it ran, and was cut off by the 2 s cap rather than failing to start or finishing
  [[ "$output" == *started* ]]
  [ $((SECONDS - start)) -ge 1 ]
  [ $((SECONDS - start)) -lt 20 ]
}
