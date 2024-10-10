#!/bin/bash

# Check if project ID is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <project-id>"
    exit 1
fi

PROJECT_ID="$1"
CURRENT_DATE=$(date +"%Y%m%d")
OUTPUT_FILE="${PROJECT_ID}_vm_public_ips_${CURRENT_DATE}.csv"

# Verify gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed"
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="get(account)" &> /dev/null; then
    echo "Error: Not authenticated with gcloud. Please run 'gcloud auth login'"
    exit 1
fi

echo "Listing VMs with public IPs in project: $PROJECT_ID"
echo "Exporting data to: $OUTPUT_FILE"
echo "------------------------------------------------"

# Create CSV header
echo "Name,Public IP,Zone,Machine Type,Status,Internal IP" > "$OUTPUT_FILE"

# List all instances with their network interfaces and export to CSV
gcloud compute instances list \
    --project "$PROJECT_ID" \
    --format="csv[no-heading](
        name,
        networkInterfaces[].accessConfigs[0].natIP.notnull().list():label=PUBLIC_IP,
        zone.basename(),
        machineType.basename(),
        status,
        networkInterfaces[].networkIP.notnull().list():label=INTERNAL_IP
    )" \
    --filter="networkInterfaces[].accessConfigs[0].natIP:*" >> "$OUTPUT_FILE"

if [ $? -ne 0 ]; then
    echo "Error: Failed to list instances. Please check your project ID and permissions."
    rm "$OUTPUT_FILE"  # Clean up the CSV file if there's an error
    exit 1
fi

# Also display the table in terminal for convenience
echo "Displaying results in terminal:"
echo "------------------------------------------------"
gcloud compute instances list \
    --project "$PROJECT_ID" \
    --format="table(
        name,
        networkInterfaces[].accessConfigs[0].natIP.notnull().list():label=PUBLIC_IP,
        zone.basename(),
        machineType.basename(),
        status,
        networkInterfaces[].networkIP.notnull().list():label=INTERNAL_IP
    )" \
    --filter="networkInterfaces[].accessConfigs[0].natIP:*"

echo "------------------------------------------------"
echo "Data has been exported to: $OUTPUT_FILE"

# Optional: Display first few lines of the CSV
echo "First few lines of the CSV file:"
head -n 5 "$OUTPUT_FILE"
