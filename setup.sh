#!/bin/bash
# shellcheck disable=SC2317

set -e

setup-cpu () {
  if [[ -d /sys/devices/system/cpu/intel_pstate ]]; then
    configure-intel
  elif [[ -d /sys/devices/system/cpu/cpufreq/boost ]]; then
    configure-amd
  fi

  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/processor_state_control.html#baseline-perf
  # > AWS Graviton processors have built-in power saving modes and operate at a fixed frequency. Therefore, they do not provide the ability for the operating system to control C-states and P-states.
}

configure-amd () {
  echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost
  sudo cpupower frequency-set -g performance || echo 'ignoring'
}

configure-intel () {
  # Keep commands simple so that they can be copied and pasted from this file with ease.
  # TODO: Do we want to limit C-states in grub and rebuild the grub config?

  echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
  echo 100 | sudo tee /sys/devices/system/cpu/intel_pstate/min_perf_pct

  # hwp_dynamic_boost may not exist if disabled at boot time
  # (with `intel_pstate=no_hwp` in the kernel command line).
  if [[ -r /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost ]]; then
    echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost
  fi

  echo performance | sudo tee /sys/devices/system/cpu/cpu"$((`nproc` - 1))"/cpufreq/energy_performance_preference /sys/devices/system/cpu/cpu"$((`nproc` - 1))"/cpufreq/scaling_governor
}

# The linux-tools-common package (a dep of linux-tools-`uname -r`) brings in `perf`.
setup-packages () {
  sudo apt-get install -y \
    autoconf \
    bison \
    build-essential \
    cargo \
    libffi-dev \
    libgdbm-dev \
    libgmp-dev \
    libncurses5-dev \
    libreadline6-dev \
    libsqlite3-dev \
    libssl-dev \
    libyaml-dev \
    ruby \
    rustc \
    sqlite3 \
    zlib1g-dev \
    $(if [[ -r /etc/ec2_version ]]; then echo linux-tools-aws linux-tools-"`uname -r`"; fi) \
  && true
}

setup-repos () {
  local dir=${REPOS_DIR:-$HOME/ym}
  mkdir -p "$dir"
  cd "$dir"

  # Setup one clone of ruby/ruby for each "ruby-config" we want to build.
  [[ -d prod-yjit ]]  || git clone https://github.com/ruby/ruby prod-yjit
  [[ -d prev-yjit ]]  || git clone --no-hardlinks prod-yjit prev-yjit
  [[ -d stats-yjit ]] || git clone --no-hardlinks prod-yjit stats-yjit

  # In case this script isn't being run from the repo.
  [[ -d yjit-metrics ]] || git clone https://github.com/Shopify/yjit-metrics

  # Clone raw-benchmark-data for pushing results.
  [[ -d raw-benchmark-data ]] || git clone https://github.com/yjit-raw/benchmark-data raw-benchmark-data
}

setup-ruby-build () {
  local dir=${RUBY_BUILD:-$HOME/src/ruby-build}
  mkdir -p "${dir%/*}"
  if ! [[ -x "$dir/bin/ruby-build" ]]; then
    git clone https://github.com/rbenv/ruby-build "$dir"
  else
    (cd "$dir" && git pull)
  fi
  PATH=$dir/bin:$PATH
}

setup-ruby () {
  local version=3.3.4
  local prefix=/usr/local/ruby
  local exe="$prefix/bin/ruby"

  if ! [[ -x "$exe" ]] || ! "$exe" -e 'exit 1 unless RUBY_VERSION == ARGV[0]' "$version"; then
    local user=`id -nu`

    # Remove any old version.
    sudo rm -rf "$prefix"
    # Allow user-level install.
    sudo mkdir -p "$prefix"
    sudo chown "$user" "$prefix"

    setup-ruby-build
    ruby-build "$version" "$prefix"
  fi

  # Put into PATH without any fuss.
  for i in ruby gem bundle; do
    sudo ln -sf "$prefix/bin/$i" /usr/local/bin/$i
  done
}

setup-all () {
  setup-cpu
  setup-packages
  setup-ruby
  setup-repos
}

if [[ $(id -u) = 0 ]]; then
  echo "Don't run this as root, run it as a user that can sudo" >&2
  exit 1
fi

usage=false
while [[ $# -gt 0 ]]; do
  cmd="setup-$1"
  shift
  if type -t "$cmd" >/dev/null; then
    set -x
    "$cmd"
    set +x
  else
    usage=true
  fi
done

if $usage; then
  cat <<USAGE >&2
  Usage: $0 action...
  Where actions are: cpu, packages, ruby, repos, or all
USAGE
  exit 1
fi
