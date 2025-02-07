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

# Function to adjust chapter metadata with offsets
adjust_chapters_with_offset() {
    input_file=$1
    previous_end=$2
    chapter_metadata_file="${input_file%.m4a}_chapter_metadata.txt"
    adjusted_metadata_file="${input_file%.m4a}_adjusted_chapters.txt"

    # Adjust chapter START and END values based on previous_end
    awk -v previous_end="$previous_end" '
        BEGIN { OFS="\n"; start_offset = previous_end; inside_chapter = 0 }
        /\[CHAPTER\]/ {
            if (inside_chapter) {
                print ""
            }
            inside_chapter = 1
        }
        inside_chapter && $0 ~ /START/ { 
            split($0, arr, "=")
            start_offset += arr[2]
            print "START=" start_offset
        }
        inside_chapter && $0 ~ /END/ { 
            split($0, arr, "=")
            end_offset = arr[2] + start_offset
            print "END=" end_offset
        }
        inside_chapter && $0 !~ /START/ && $0 !~ /END/ { print $0 }
    ' "$chapter_metadata_file" | sed '/^$/d' > "$adjusted_metadata_file"

    echo "Adjusted chapter metadata has been saved to $adjusted_metadata_file"
}

clean_up_metadata_files() {
  for file in "$@"; do
    general_metadata_file="${file%.m4a}_general_metadata.txt"
    adjusted_metadata_file="${file%.m4a}_adjusted_chapters.txt"
    chapter_metadata_file="${file%.m4a}_chapter_metadata.txt"

    if [ -f "$general_metadata_file" ]; then
      rm "$general_metadata_file"
    fi

    if [ -f "$adjusted_metadata_file" ]; then
      rm "$adjusted_metadata_file"
    fi

    if [ -f "$chapter_metadata_file" ]; then
      rm "$chapter_metadata_file"
    fi
  done
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
last_end=0  # Initially no previous chapter's end

for m4a_file in "$@"; do
    if [[ "$m4a_file" == *.m4a ]]; then
        # Extract metadata for the current m4a file
        extract_metadata "$m4a_file"

        # If this is the first file, append its general metadata
        if $first_file; then
            first_file=false
            # Append the general metadata of the first file (without adding an extra [CHAPTER])
            cat "${m4a_file%.m4a}_general_metadata.txt" >> "$combined_metadata_file"
        fi

        # Adjust chapter metadata for subsequent files, offsetting by the previous file's end
        adjust_chapters_with_offset "$m4a_file" "$last_end"

        # Append the adjusted chapter metadata of the current file to the combined file
        cat "${m4a_file%.m4a}_adjusted_chapters.txt" >> "$combined_metadata_file"

        # Update the last_end to the end of the last chapter in this file
        last_end=$(awk '/\[CHAPTER\]/ {inside_chapter=1} inside_chapter && /END/ {split($0, arr, "="); end=arr[2]} END {print end}' "${m4a_file%.m4a}_adjusted_chapters.txt")
    else
        echo "Skipping '$m4a_file' (not an .m4a file)"
    fi
done

echo "cleaning up metadata files"
clean_up_metadata_files "$@"

echo "Combined metadata has been saved to $combined_metadata_file"
