#!/bin/bash

# find_custom_psds.sh
#
# Samuel A. Hurley
# University of Wisconsin - Madison
# 19 March 2026
#
# 0.1 - Initial version

# Function to display the help menu
show_help() {
    echo "Usage: ./find_custom_psds.sh [OPTIONS]"
    echo ""
    echo "Searches GE MRI protocol folders (starting with 'adult_other_') to identify"
    echo "custom pulse sequences defined in LxProtocol files. It also extracts the"
    echo "human-readable protocol name from the corresponding session.xml file."
    echo ""
    echo "Options:"
    echo "  -h, --help    Display this help message and exit."
    echo "  --csv         Export the results to a CSV file (custom_psds_report.csv)."
    echo "  --filter      Filter results to only show PSDs stored in research paths:"
    echo "                (/usr/g/M/, /usr/g/research, or research/)."
    echo "  --remove-dup  Remove duplicate PSDs within a protocol folder. Only the first"
    echo "                series found using the custom PSD will be displayed."
    echo "  --no-color    Disable ANSI color output in the terminal."
    echo ""
    exit 0
}

# Initialize variables and flags
export_csv=0
filter_paths=0
remove_dup=0
use_color=1
csv_file="custom_psds_report.csv"
total_custom_count=0 
total_protocol_count=0 # Initialize our new protocol counter

# Parse command-line arguments
for arg in "$@"; do
    case $arg in
        -h|--help)
            show_help
            ;;
        --csv)
            export_csv=1
            shift
            ;;
        --filter)
            filter_paths=1
            shift
            ;;
        --remove-dup)
            remove_dup=1
            shift
            ;;
        --no-color)
            use_color=0
            shift
            ;;
        *)
            # Handle unknown flags gracefully
            echo "Unknown option: $arg"
            echo "Run './find_custom_psds.sh --help' for usage instructions."
            exit 1
            ;;
    esac
done

# Define ANSI color codes
C_HEAD='\033[1;34m'  # Bold Blue
C_LABEL='\033[1;33m' # Bold Yellow
C_FOLD='\033[1;32m'  # Bold Green
C_PROT='\033[1;36m'  # Bold Cyan
C_SER='\033[0;37m'   # White
C_PSD='\033[1;35m'   # Bold Purple
C_RES='\033[0m'      # Reset to default

# Disable colors if the flag was passed
if [ $use_color -eq 0 ]; then
    C_HEAD=''; C_LABEL=''; C_FOLD=''; C_PROT=''; C_SER=''; C_PSD=''; C_RES=''
fi

# Initialize CSV file with headers if the flag is set
if [ $export_csv -eq 1 ]; then
    echo "Folder,Protocol_Name,Series,PSD_Name" > "$csv_file"
    echo -e "${C_HEAD}CSV export enabled. Writing to $csv_file...${C_RES}"
fi

# Enable nullglob so if no folders exist, it doesn't fail
shopt -s nullglob

echo -e "${C_HEAD}Searching for GE protocols with custom pulse sequences...${C_RES}"
if [ $filter_paths -eq 1 ]; then
    echo -e "${C_HEAD}Filtering active: Only showing paths with /usr/g/M/, /usr/g/research, or research/${C_RES}"
fi
if [ $remove_dup -eq 1 ]; then
    echo -e "${C_HEAD}Deduplication active: Hiding duplicate PSDs within the same protocol.${C_RES}"
fi
echo "========================================================="

# Loop through all top-level directories starting with adult_other_
for protocol_dir in adult_other_*/; do
    protocol_dir="${protocol_dir%/}"
    
    # 1. Extract the Protocol Name from session.xml
    session_file="$protocol_dir/session.xml"
    protocol_name="[Name not found]"
    
    if [ -f "$session_file" ]; then
        extracted_name=$(sed -n 's/.*<session[^>]* name="\([^"]*\)".*/\1/p' "$session_file")
        if [ -n "$extracted_name" ]; then
            protocol_name="$extracted_name"
        fi
    fi

    # 2. Search for custom PSDs
    custom_seqs=()
    seen_psds=() 
    
    for lx_file in "$protocol_dir"/*/LxProtocol; do
        psd_line=$(grep -E '^[[:space:]]*set[[:space:]]+PSDNAME' "$lx_file" 2>/dev/null)
        
        if [ -n "$psd_line" ]; then
            psd_name=$(echo "$psd_line" | sed -n 's/.*"\(.*\)".*/\1/p')
            
            # Apply path filtering
            if [ $filter_paths -eq 1 ]; then
                if [[ ! "$psd_name" =~ (/usr/g/M/|/usr/g/research|research/) ]]; then
                    continue 
                fi
            fi

            # Apply deduplication filtering
            if [ $remove_dup -eq 1 ]; then
                is_duplicate=0
                for seen in "${seen_psds[@]}"; do
                    if [ "$seen" == "$psd_name" ]; then
                        is_duplicate=1
                        break
                    fi
                done
                
                if [ $is_duplicate -eq 1 ]; then
                    continue
                fi
                
                seen_psds+=("$psd_name")
            fi
            
            series_dir=$(basename "$(dirname "$lx_file")")
            custom_seqs+=("${series_dir}|${psd_name}")
        fi
    done

    # 3. Output results if any sequences were found
    if [ ${#custom_seqs[@]} -gt 0 ]; then
        ((total_custom_count += ${#custom_seqs[@]}))
        ((total_protocol_count += 1)) # Increment the protocol counter

        echo -e "${C_LABEL}Folder:         ${C_RES} ${C_FOLD}${protocol_dir}${C_RES}"
        echo -e "${C_LABEL}Protocol name:  ${C_RES} ${C_PROT}${protocol_name}${C_RES}"
        echo -e "${C_LABEL}Custom Sequences Found:${C_RES}"
        
        for seq_data in "${custom_seqs[@]}"; do
            IFS='|' read -r series psd <<< "$seq_data"
            
            echo -e "  - Series: ${C_SER}${series}${C_RES} --> PSD: \"${C_PSD}${psd}${C_RES}\""
            
            if [ $export_csv -eq 1 ]; then
                echo "\"$protocol_dir\",\"$protocol_name\",\"$series\",\"$psd\"" >> "$csv_file"
            fi
        done
        echo "---------------------------------------------------------"
    fi
done

# Revert nullglob
shopt -u nullglob

# 4. Print the final summary
echo "========================================================="
echo -e "${C_HEAD}Scan Complete!${C_RES}"
# Print both counters with proper spacing for alignment
echo -e "Total protocols with custom sequences: ${C_LABEL}${total_protocol_count}${C_RES}"
echo -e "Total custom sequences found:          ${C_LABEL}${total_custom_count}${C_RES}"

if [ $export_csv -eq 1 ]; then
    echo -e "${C_HEAD}Report saved to $csv_file${C_RES}"
fi
