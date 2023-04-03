#!/bin/bash

# read the input JSON string
input_json="$1"

# extract the nested JSON array
nested_json=$(echo "$input_json" | sed -n 's/.*<sanitize>\(.*\)<\/sanitize>.*/\1/p')

# escape special characters in the nested JSON array
escaped_nested_json=$(echo "$nested_json" | awk -v RS='([[])[^][{}]*([]])' '{gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0); gsub(/</,"\\u003c",$0); gsub(/>/,"\\u003e",$0); print $0 RT }')

# replace the nested JSON array with the escaped version in the input JSON string
escaped_json=$(echo "$input_json" | sed -e "s#<sanitize>$nested_json</sanitize>#<sanitize>$escaped_nested_json</sanitize>#g")

# print the escaped JSON string to the console
echo "$escaped_json"
