#!/bin/bash
# shellcheck disable=SC2317

set -e

# This is called from the on_demand scripts as some CPU settings do not persist across reboots.
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

  echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
}

# The linux-tools-common package (a dep of linux-tools-`uname -r`) brings in `perf`.
# https://docs.ruby-lang.org/en/master/contributing/building_ruby_md.html#label-Dependencies
setup-packages () {
  # nodejs needed for some ruby gems used in ruby-bench benchmarks.
  sudo apt install -y \
    autoconf \
    bison \
    build-essential \
    gperf \
    libffi-dev \
    libgdbm-dev \
    libgmp-dev \
    libncurses5-dev \
    libreadline6-dev \
    libsqlite3-dev \
    libssl-dev \
    libyaml-dev \
    pkg-config \
    ruby \
    rustup \
    sqlite3 \
    zlib1g-dev \
    nodejs \
    $(if [[ -r /etc/ec2_version ]]; then echo linux-tools-aws linux-tools-"`uname -r`"; fi) \
  && true

  rustup default stable

  # As of 2024-09-24 Ubuntu 24 comes with gcc 13 but a ppa can upgrade it to 14.
  # Ubuntu 20 is capable of upgrading to 13.
  upgrade-gcc 14
}

upgrade-gcc () {
  local version="$1"

  if ! dpkg -s gcc-$version; then
    if sudo add-apt-repository ppa:ubuntu-toolchain-r/test -y && dpkg -S gcc-$version; then
      sudo apt install -y gcc-$version
    fi
  fi

  if ! update-alternatives --list gcc; then
    old=($(dpkg --get-selections | cut -f 1 | grep -E '^gcc-[0-9]+$' | sed 's/gcc-//'))
    for i in "${old[@]}"; do
      sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-$i 50 # --slave /usr/bin/g++ g++ /usr/bin/g++-$i
    done
    # g++-14 doesn't want to install currently.
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-$version 60 # --slave /usr/bin/g++ g++ /usr/bin/g++-$version
  fi

  gcc --version
}

setup-repos () {
  local dir=${REPOS_DIR:-$HOME/ym}
  mkdir -p "$dir"
  cd "$dir"

  # In case this script isn't being run from the repo.
  [[ -d yjit-metrics ]] || git clone https://github.com/Shopify/yjit-metrics

  # Clone raw-benchmark-data for pushing results.
  [[ -d raw-benchmark-data ]] || git clone --branch main https://github.com/yjit-raw/benchmark-data raw-benchmark-data
  # Clone github pages repo for pushing built reports.
  [[ -d ghpages-yjit-metrics ]] || git clone --branch pages https://github.com/yjit-raw/yjit-reports ghpages-yjit-metrics
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
  local version=3.4.4
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
