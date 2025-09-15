#!/bin/bash -e

# This runs as root when the instance boots.

# Variables inserted by Terraform.
{{vars}}

uid=1000
# It's too early for /run/user/$uid to exist.
dir=/run/yjit-init
mkdir -p "$dir"
chown $uid:$uid "$dir"
chmod 0700 "$dir"

profile="$dir/.profile"
secret_cache="$dir/secrets.json"

warn () { echo "$*" >&2; }

setup-profile () {
  local file="$(getent passwd $uid | cut -d: -f 6)"/"$1"
  local line="[[ -r $profile ]] && source $profile # generated"
  [[ -e "$file" ]] || { touch "$file" && chown $uid:$uid "$file"; }
  head -n 1 "$file" | grep -qFx "$line" && return 0
  printf "0i\n%s\n.\nw\nq\n" "$line" | ed "$file"
}

process-metadata () {
  local TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
  local name=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/tags/instance/Name)

  echo "Name: $name"
  hostname "$name" || echo 'ignoring'
  printf "export INSTANCE_NAME=%q\n" "$name" >> "$profile"
}

get-aws-secret () {
  aws secretsmanager get-secret-value --region "$region" --secret-id "$1" --query SecretString --output text
}

load-secrets () {
  get-aws-secret "$secret_name" > "$secret_cache"
}

get-secret () {
  ruby -r json -e 'puts JSON.parse(File.read(ARGV[0])).dig(*ARGV[1..])' "$secret_cache" "$@"
}

yjit-git-creds () {
  local secret_file="$dir/git-token"
  get-secret "git-token" > "$secret_file"

  local config_file="$dir/git-config"
  local repo_prefix=https://github.com/yjit-raw/

  git config --file "$config_file" "user.name" "$(get-secret git-name)"
  git config --file "$config_file" "user.email" "$(get-secret git-email)"
  git config --file "$config_file" "credential.$repo_prefix.username" "$(get-secret git-user)"
  git config --file "$config_file" "credential.$repo_prefix.helper" \
    '!_() { test "$1" = get && echo "password=$(cat '"$secret_file"')"; }; _'

  printf "export GIT_CONFIG_GLOBAL=%q\n" "$config_file" >> "$profile"
}

yjit-slack-token () {
  local secret_file="$dir/slack-token"
  get-secret slack-token > "$secret_file"
  printf "export SLACK_TOKEN_FILE=%q\n" "$secret_file" >> "$profile"
}

setup-profile .bashrc
setup-profile .zshrc
process-metadata
load-secrets
yjit-git-creds
yjit-slack-token
