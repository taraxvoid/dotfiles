# sbx --audit / --audit-prepare against fake bwrap and systemd-run that record their
# arguments (one per line), so this runs anywhere, macOS included. The real-bwrap
# counterpart is sbx-audit-real.bats.

setup() {
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
  HOME=$(cd "$HOME" && pwd -P)
  export FAKE_LOG=$BATS_TEST_TMPDIR/log
  mkdir -p "$FAKE_LOG"
  export PATH=$BATS_TEST_DIRNAME/fake-sbx:$PATH
  export SBX_BACKEND=bwrap
  sbx=$BATS_TEST_DIRNAME/../.local/bin/sbx
  tree=$BATS_TEST_TMPDIR/tree
  mkdir -p "$tree"
  tree=$(cd "$tree" && pwd -P)
  # audit mode is not tied to the untrusted trees: it runs on a prepared tree
  cd "$BATS_TEST_TMPDIR"
}

# has_seq <file> <arg>...: the args appear as consecutive lines of the record
has_seq() {
  local f=$1 i j ok n
  shift
  n=$#
  local -a want=("$@") lines=()
  local line
  # no mapfile: macOS ships bash 3.2
  while IFS= read -r line; do lines+=("$line"); done <"$f"
  for ((i = 0; i + n <= ${#lines[@]}; i++)); do
    ok=1
    for ((j = 0; j < n; j++)); do
      if [ "${lines[i + j]}" != "${want[j]}" ]; then ok=0; break; fi
    done
    if [ "$ok" = 1 ]; then return 0; fi
  done
  return 1
}

@test "--audit runs the command in a transient scope with default limits" {
  run "$sbx" --audit "$tree" echo hi
  [ "$status" -eq 0 ]
  has_seq "$FAKE_LOG/systemd-run" --user --scope
  rg -qxF -- 'MemoryMax=2G' "$FAKE_LOG/systemd-run"
  rg -qxF -- 'TasksMax=256' "$FAKE_LOG/systemd-run"
  rg -qxF -- 'CPUQuota=100%' "$FAKE_LOG/systemd-run"
  rg -qxF -- 'RuntimeMaxSec=300' "$FAKE_LOG/systemd-run"
  # swap would let a PoC dodge MemoryMax
  rg -qxF -- 'MemorySwapMax=0' "$FAKE_LOG/systemd-run"
}

@test "each limit is overridable by an env var" {
  SBX_AUDIT_MEM=512M SBX_AUDIT_TASKS=32 SBX_AUDIT_CPU=50% SBX_AUDIT_TIME=20 \
    run "$sbx" --audit "$tree" true
  [ "$status" -eq 0 ]
  rg -qxF -- 'MemoryMax=512M' "$FAKE_LOG/systemd-run"
  rg -qxF -- 'TasksMax=32' "$FAKE_LOG/systemd-run"
  rg -qxF -- 'CPUQuota=50%' "$FAKE_LOG/systemd-run"
  rg -qxF -- 'RuntimeMaxSec=20' "$FAKE_LOG/systemd-run"
}

@test "ulimit -f is applied before bwrap, default 1 GiB and overridable" {
  run "$sbx" --audit "$tree" true
  has_seq "$FAKE_LOG/systemd-run" sbx-limits 1048576 bwrap
  rm -f "$FAKE_LOG/systemd-run"
  SBX_AUDIT_FSIZE_MB=10 run "$sbx" --audit "$tree" true
  has_seq "$FAKE_LOG/systemd-run" sbx-limits 10240 bwrap
}

@test "there is no network, with or without --offline" {
  run "$sbx" --audit "$tree" true
  [ "$status" -eq 0 ]
  has_seq "$FAKE_LOG/bwrap" --unshare-all
  ! rg -qxF -- '--share-net' "$FAKE_LOG/bwrap"
}

@test "HOME is a fresh tmpfs, never a persistent bind" {
  run "$sbx" --audit "$tree" true
  has_seq "$FAKE_LOG/bwrap" --size 268435456 --tmpfs "$HOME"
  ! rg -qF -- '/.local/share/sbx/home' "$FAKE_LOG/bwrap"
}

@test "the toolchain (mise dir) is read-only" {
  run "$sbx" --audit "$tree" true
  has_seq "$FAKE_LOG/bwrap" --ro-bind "$HOME/.local/share/sbx/mise" "$HOME/.local/share/mise"
  ! has_seq "$FAKE_LOG/bwrap" --bind "$HOME/.local/share/sbx/mise" "$HOME/.local/share/mise"
}

@test "--audit copies TREE (read-only bind) into a size-limited tmpfs at /work" {
  run "$sbx" --audit "$tree" echo hi
  has_seq "$FAKE_LOG/bwrap" --ro-bind "$tree" /run/sbx-tree
  has_seq "$FAKE_LOG/bwrap" --size 1073741824 --tmpfs /work
  has_seq "$FAKE_LOG/bwrap" --chdir /work
  # the tree itself is never bound writable
  ! has_seq "$FAKE_LOG/bwrap" --bind "$tree" /work
  rg -qxF -- 'cp -a /run/sbx-tree/. /work/ && cd /work && exec "$@"' "$FAKE_LOG/bwrap"
  rg -qxF -- 'echo' "$FAKE_LOG/bwrap"
}

@test "the /work size is overridable" {
  SBX_AUDIT_WORK_MB=64 run "$sbx" --audit "$tree" true
  has_seq "$FAKE_LOG/bwrap" --size 67108864 --tmpfs /work
}

@test "--audit-prepare binds TREE itself writable at /work" {
  run "$sbx" --audit-prepare "$tree" make
  [ "$status" -eq 0 ]
  has_seq "$FAKE_LOG/bwrap" --bind "$tree" /work
  has_seq "$FAKE_LOG/bwrap" --chdir /work
  ! rg -qxF -- '/run/sbx-tree' "$FAKE_LOG/bwrap"
  ! rg -qxF -- '--share-net' "$FAKE_LOG/bwrap"
  rg -qxF -- 'MemoryMax=2G' "$FAKE_LOG/systemd-run"
}

@test "the environment is cleared" {
  run "$sbx" --audit "$tree" true
  has_seq "$FAKE_LOG/bwrap" --clearenv
  has_seq "$FAKE_LOG/bwrap" --setenv SBX 1
}

@test "refuses on the srt backend" {
  SBX_BACKEND=srt run "$sbx" --audit "$tree" true
  [ "$status" -ne 0 ]
  [[ "$output" == *"bwrap"* ]]
  [ ! -e "$FAKE_LOG/bwrap" ]
}

@test "refuses combined with --rw-git" {
  run "$sbx" --rw-git --audit "$tree" true
  [ "$status" -ne 0 ]
  [[ "$output" == *"--rw-git"* ]]
  [ ! -e "$FAKE_LOG/bwrap" ]
}

@test "refuses when the scope limits cannot be applied" {
  FAKE_PROBE_STATUS=1 run "$sbx" --audit "$tree" true
  [ "$status" -ne 0 ]
  [[ "$output" == *"limits"* ]]
  [ ! -e "$FAKE_LOG/bwrap" ]
}

@test "refuses when systemd-run is missing" {
  if [ -x /usr/bin/systemd-run ] || [ -x /bin/systemd-run ]; then skip "real systemd-run in the base PATH"; fi
  mkdir -p "$BATS_TEST_TMPDIR/nosd"
  ln -s "$BATS_TEST_DIRNAME/fake-sbx/bwrap" "$BATS_TEST_TMPDIR/nosd/bwrap"
  PATH=$BATS_TEST_TMPDIR/nosd:/usr/bin:/bin run "$sbx" --audit "$tree" true
  [ "$status" -ne 0 ]
  [[ "$output" == *"systemd-run"* ]]
  [ ! -e "$FAKE_LOG/bwrap" ]
}

@test "refuses without a TREE or with a missing one" {
  run "$sbx" --audit
  [ "$status" -ne 0 ]
  run "$sbx" --audit "$BATS_TEST_TMPDIR/nope" true
  [ "$status" -ne 0 ]
  [ ! -e "$FAKE_LOG/bwrap" ]
}

@test "refuses --audit together with --audit-prepare" {
  run "$sbx" --audit "$tree" --audit-prepare "$tree" true
  [ "$status" -ne 0 ]
  [ ! -e "$FAKE_LOG/bwrap" ]
}
