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

create_intellij_project() {
    # Configuration variables with defaults
    local project_dir="${1:-$(pwd)}"
    local project_name="${2:-$(basename "$project_dir")}"
    local jdk_version="${3:-22}"
    local project_type="${4:-BASIC}"
    local idea_dir="$project_dir/.idea"

    # Create .idea directory
    if ! mkdir -p "$idea_dir"; then
        echo "Error: Failed to create IntelliJ IDEA configuration directory $idea_dir." >&2
        return 1
    fi

    # Create file types configuration
    create_filetypes_xml() {
        cat > "$idea_dir/fileTypes.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="FileTypeManager">
    <extensionMap>
      <mapping pattern="*" type="JSON" />
      <mapping ext="*" type="JSON" />
    </extensionMap>
  </component>
</project>
EOF
    }

    # Create misc configuration
    create_misc_xml() {
        cat > "$idea_dir/misc.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" languageLevel="JDK_${jdk_version}" default="true" project-jdk-type="JavaSDK">
    <output url="file://$project_dir/out" />
  </component>
  <component name="ProjectType">
    <option name="id" value="${project_type}" />
  </component>
</project>
EOF
    }

    # Create workspace configuration
    create_workspace_xml() {
        local project_id=$(uuidgen | tr -d '-')
        cat > "$idea_dir/workspace.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectId" id="${project_id}" />
  <component name="ProjectName">
    <name>${project_name}</name>
  </component>
  <component name="ProjectViewState">
    <option name="hideEmptyMiddlePackages" value="true" />
    <option name="showLibraryContents" value="true" />
  </component>
</project>
EOF
    }

    # Create all config files
    create_filetypes_xml
    create_misc_xml
    create_workspace_xml

    echo "IntelliJ IDEA project configuration created successfully in $idea_dir"
    return 0
}

qidea() {
    local date_path=$(date +%Y/%m/%d)
    local target_dir=~/Downloads/buckets/$date_path
    local bucket_name="test:queue-history-handler-service-test"

    # Project configuration
    local project_name="QueueViewer-${date_path//\//-}"
    local jdk_version=22
    local project_type="BASIC"

    # Create target directory
    if ! mkdir -p "$target_dir"; then
        echo "Error: Failed to create target directory $target_dir." >&2
        return 1
    fi

    # Sync the S3 bucket directory
    if ! rclone sync "$bucket_name/$date_path/" "$target_dir" --progress --ignore-existing; then
        echo "Error: Failed to sync S3 bucket." >&2
        return 1
    fi

    # Create IntelliJ IDEA project configuration
    if ! create_intellij_project "$target_dir" "$project_name" "$jdk_version" "$project_type"; then
        echo "Error: Failed to create IntelliJ IDEA project configuration." >&2
        return 1
    fi

    # Launch IntelliJ IDEA
    if ! idea "$target_dir"; then
        echo "Error: Failed to open IntelliJ IDEA." >&2
        return 1
    fi

    echo "Sync completed successfully and IntelliJ IDEA launched with directory $target_dir"
    return 0
}