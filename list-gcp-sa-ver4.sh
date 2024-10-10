#!/bin/bash

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    echo "Error: Not authenticated. Please run 'gcloud auth login' first."
    exit 1
fi

# Function to determine service account type
get_sa_type() {
    local sa="$1"
    local project_id="$2"
    
    if [[ $sa == *"@${project_id}.iam.gserviceaccount.com" ]]; then
        echo "User-Managed"
    elif [[ $sa == *"@appspot.gserviceaccount.com" || 
            $sa == *"@cloudservices.gserviceaccount.com" || 
            $sa == *"@containerregistry.iam.gserviceaccount.com" ]]; then
        echo "Default"
    else
        echo "Google-Managed"
    fi
}

# Function to export privileged service accounts to CSV
export_privileged_sa_to_csv() {
    local project_id="$1"
    local output_file="privileged_service_accounts_${project_id}.csv"
    local temp_file="temp_$output_file"
    
    echo "Exporting privileged service accounts for project: $project_id"
    echo "This may take a few moments..."

    # Create CSV header
    echo "Service Account,Type,Role,Creation Time,Last Used Time,OAuth2 Client ID,Description" > "$output_file"

    # Get all IAM policies
    policies=$(gcloud projects get-iam-policy "$project_id" --format=json)

    # Get service account details and roles
    echo "$policies" | jq -r '
        .bindings[] | 
        select(.role | ascii_downcase | contains("admin") or contains("owner") or contains("editor")) |
        .members[] | 
        select(startswith("serviceAccount:"))' | sort -u |
    while read -r full_account; do
        account="${full_account#serviceAccount:}"
        
        # Get privileged roles for this account
        roles=$(echo "$policies" | jq -r --arg acct "$full_account" '
            .bindings[] | 
            select(.members[] | contains($acct)) |
            select(.role | ascii_downcase | contains("admin") or contains("owner") or contains("editor")) |
            .role')

        # Get service account details
        if [[ $account == *"@${project_id}.iam.gserviceaccount.com" ]]; then
            sa_details=$(gcloud iam service-accounts describe "$account" --project="$project_id" --format=json 2>/dev/null)
            if [ $? -eq 0 ]; then
                creation_time=$(echo "$sa_details" | jq -r '.createTime // "N/A"')
                oauth2_client_id=$(echo "$sa_details" | jq -r '.oauth2ClientId // "N/A"')
                description=$(echo "$sa_details" | jq -r '.description // "N/A"' | sed 's/,/ /g')
            else
                creation_time="N/A"
                oauth2_client_id="N/A"
                description="N/A"
            fi
        else
            creation_time="N/A"
            oauth2_client_id="N/A"
            description="N/A"
        fi

        # Try to get last used time
        last_used=$(gcloud iam service-accounts get-iam-policy "$account" --project="$project_id" --format="value(lastUsedTime)" 2>/dev/null || echo "N/A")

        # Get service account type
        sa_type=$(get_sa_type "$account" "$project_id")

        # Write each role on a separate line
        echo "$roles" | while read -r role; do
            if [ ! -z "$role" ]; then
                echo "${account},${sa_type},${role},${creation_time},${last_used},${oauth2_client_id},\"${description}\"" >> "$temp_file"
            fi
        done
    done

    # Sort and append temp file to final file
    if [ -f "$temp_file" ]; then
        sort "$temp_file" >> "$output_file"
        rm "$temp_file"
    fi

    echo "Export completed successfully!"
    echo "Results have been saved to: $output_file"
    echo "Total privileged service accounts found: $(( $(wc -l < "$output_file") - 1 ))"
}

# Get current project ID
PROJECT_ID=$(gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    echo "Error: No project selected. Please set a project using 'gcloud config set project PROJECT_ID'"
    exit 1
fi

# Execute the function
export_privileged_sa_to_csv "$PROJECT_ID"
