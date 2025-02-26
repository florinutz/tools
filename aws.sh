#!/usr/bin/zsh

function s3_queue_logs() {
  local service_name=$1
  local entity=$2
  local action=$3
  local showLatest=false
  local start_date=$(date +%Y/%m/%d)
  local end_date=$(date +%Y/%m/%d)

  while [[ $# -gt 3 ]]; do
    case "$4" in
    --service-name)
      service_name=$5
      shift 2
      ;;
    --entity)
      entity=$5
      shift 2
      ;;
    --action)
      action=$5
      shift 2
      ;;
    --show-latest)
      showLatest=true
      shift 1
      ;;
    --start-date)
      start_date=$5
      shift 2
      ;;
    --end-date)
      if [[ "$(date -d "$5" +%s)" -lt "$(date -d "$start_date" +%s)" ]]; then
        echo "Error: End date is earlier than start date."
        return 1
      fi
      end_date=$5
      shift 2
      ;;
    *)
      echo "Unknown option: $4"
      return 1
      ;;
    esac
  done

  if [[ -z "$service_name" ]]; then
    echo "Error: Service name is required."
    return 1
  fi

  current_date=$start_date
  while [[ "$(date -d "$current_date" +%s)" -le "$(date -d "$end_date" +%s)" ]]; do
    local s3_path="s3://queue-history-handler-service-test/$current_date/"
    aws s3 ls "$s3_path" | grep "$service_name" | sort -r | while read line; do
      local filename=$(echo "$line" | awk '{print $NF}')
      if [[ ! -z "$entity" ]]; then
        if [[ ! "$filename" =~ "$entity" ]]; then
          continue
        fi
      fi
      if [[ ! -z "$action" ]]; then
        if [[ ! "$filename" =~ "$action" ]]; then
          continue
        fi
      fi
      if [[ "$showLatest" == true ]]; then
        # considering the contents of these files are all json, use jq to display the contents of the file associated with this line:
        aws s3 cp "$s3_path$filename" - | jq
        return 0
      fi
      echo "$(echo "$line" | awk '{print $2}') $s3_path$filename"
    done
    current_date=$(date -d "$current_date + 1 day" +%Y/%m/%d)
  done
}

qidea() {
    local date_path=$(date +%Y/%m/%d)
    local target_dir=~/Downloads/buckets/$date_path
    local bucket_name="test:queue-history-handler-service-test"
    local tmp_dir

    # Check if any symlink exists in the target_dir and use it to determine tmp_dir
    if [[ -d "$target_dir" && $(find "$target_dir" -type l | wc -l) -gt 0 ]]; then
        tmp_dir=$(dirname "$(readlink -f "$(find "$target_dir" -type l | head -n 1)")")
    else
        tmp_dir=$(mktemp -d)
    fi

    if ! mkdir -p "$target_dir"; then
        echo "Error: Failed to create target directory $target_dir." >&2
        return 1
    fi

    if ! rclone sync "$bucket_name/$date_path/" "$tmp_dir" --progress --ignore-existing; then
        echo "Error: Failed to sync S3 bucket." >&2
        return 1
    fi

    find "$target_dir" -type l -exec rm -f {} \;

    for file in "$tmp_dir"/*; do
        if [[ -f "$file" ]]; then
            local base_name=$(basename "$file")
            ln -s "$file" "$target_dir/$base_name.json"
            touch -r "$file" "$target_dir/$base_name.json" # use the timestamp of the original file
        fi
    done

    if ! idea "$target_dir"; then
        echo "Error: Failed to open IntelliJ IDEA." >&2
        return 1
    fi

    echo "Sync completed successfully, files symlinked, and IntelliJ IDEA launched with directory $target_dir"
    return 0
}