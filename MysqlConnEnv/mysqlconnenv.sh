#!/usr/bin/env bash

# Script to connect to MySQL using environment variables from a file or .env
# If a file is passed as argument, it will be used. Otherwise, it will read .env in current directory.
# For each required DB variable, if not found in the file, it will prompt the user for the value.
# Finally, it will execute the mysql connection command.

# Determine the source file to read from
if [ $# -ge 1 ] && [ -f "$1" ]; then
    ENV_FILE="$1"
    echo "Using provided file: $ENV_FILE"
elif [ -f ".env" ]; then
    ENV_FILE=".env"
    echo "Using .env file in current directory"
else
    echo "Error: No file provided and '.env' not found in current directory."
    echo "Usage: $0 [path/to/env/file]"
    exit 1
fi

# Function to get a value for a given key
# 1. Greps the env file for the key
# 2. If found with a non-empty value, extracts and cleans it (removes comments, quotes, spaces)
# 3. If not found or empty, prompts the user for input
get_db_value() {
    local key="$1"
    local value=""
    local line=""
    
    # Search for the key in the env file (ignore comments starting with #)
    # Look for lines like KEY=value, allowing for spaces around =
    line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$ENV_FILE" | grep -v "^[[:space:]]*#" | tail -n 1)
    
    if [ -n "$line" ]; then
        # Extract everything after the first =
        value=$(echo "$line" | cut -d'=' -f2-)
        
        # Remove inline comments (anything after # that's not inside quotes - simple approach)
        # This handles basic cases
        value=$(echo "$value" | sed -E 's/[[:space:]]+#.*$//')
        
        # Trim whitespace
        value=$(echo "$value" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        
        # Remove surrounding single or double quotes
        value=$(echo "$value" | sed -E "s/^['\"]|['\"]$//g")
        
        # Check if value is non-empty
        if [ -n "$value" ]; then
            echo "$value"
            return 0
        fi
    fi
    
    # If not found or empty, prompt the user
    read -rp "Enter value for ${key}: " value
    echo "$value"
    return 0
}

# Retrieve all required database credentials
echo "Retrieving database configuration..."
DB_HOST=$(get_db_value "DB_HOST")
DB_PORT=$(get_db_value "DB_PORT")
DB_DATABASE=$(get_db_value "DB_DATABASE")
DB_USERNAME=$(get_db_value "DB_USERNAME")
DB_PASSWORD=$(get_db_value "DB_PASSWORD")

echo ""
echo "Configuration retrieved. Connecting to MySQL..."
echo "Host: $DB_HOST | Port: $DB_PORT | Database: $DB_DATABASE | User: $DB_USERNAME"
echo ""

# Run the MySQL connection command
mysql -h "$DB_HOST" -u"$DB_USERNAME" -p"$DB_PASSWORD" -P "$DB_PORT" "$DB_DATABASE"
