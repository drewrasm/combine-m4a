#!/bin/bash

# Function to extract metadata from a given m4a file
extract_metadata() {
    input_file=$1
    general_metadata_file="${input_file%.m4a}_general_metadata.txt"
    chapter_metadata_file="${input_file%.m4a}_chapter_metadata.txt"

    # Check if input file exists
    if [[ ! -f "$input_file" ]]; then
        echo "Input file '$input_file' does not exist!"
        return 1
    fi

    # Extract the metadata from the input file and store in metadata.txt
    ffmpeg -i "$input_file" -f ffmetadata - 2>/dev/null > metadata.txt

    # Extract general metadata (everything before the first [CHAPTER])
    awk '/^;FFMETADATA1/,/\[CHAPTER\]/ { if ($0 !~ /\[CHAPTER\]/) print $0 }' metadata.txt > "$general_metadata_file"

    # Extract chapter metadata (everything between [CHAPTER] blocks, without extra spaces)
    awk 'BEGIN { inside_chapter = 0 }
         /\[CHAPTER\]/ { 
             if (inside_chapter) print ""; 
             inside_chapter = 1; 
             print $0 
         } 
         inside_chapter && $0 !~ /\[CHAPTER\]/ { print $0 }
         END { if (inside_chapter) print "" }' metadata.txt | sed '/^$/d' > "$chapter_metadata_file"

    echo "General metadata has been saved to $general_metadata_file"
    echo "Chapter metadata has been saved to $chapter_metadata_file"
}

# Check if at least one m4a file is provided as an argument
if [ "$#" -eq 0 ]; then
    echo "Please provide at least one .m4a file as an argument."
    exit 1
fi

# Initialize combined metadata file
combined_metadata_file="combined_metadata.txt"
> "$combined_metadata_file"  # Clear the file if it already exists

# Process each m4a file passed as an argument
first_file=true
for m4a_file in "$@"; do
    if [[ "$m4a_file" == *.m4a ]]; then
        # Extract metadata for the current m4a file
        extract_metadata "$m4a_file"

        # If this is the first file, append its general metadata
        if $first_file; then
            first_file=false
            # Append the general metadata of the first file
            cat "${m4a_file%.m4a}_general_metadata.txt" >> "$combined_metadata_file"
        fi

        # Append the chapter metadata of the current file
        cat "${m4a_file%.m4a}_chapter_metadata.txt" >> "$combined_metadata_file"
    else
        echo "Skipping '$m4a_file' (not an .m4a file)"
    fi
done

echo "Combined metadata has been saved to $combined_metadata_file"
