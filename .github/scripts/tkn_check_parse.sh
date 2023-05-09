#!/bin/bash

REGISTRY="foo.bar/foo:bar"

main() { 
  TMPFILE=$(mktemp)
  for file in ${CHANGED_FILES}; do
      echo -en "Checking file ${file}..."
      tkn bundle push  ${REGISTRY} ${file} >/dev/null 2> ${TMPFILE} || true
      if ERROR=`grep -o "^Error.*failed to parse.*" ${TMPFILE}`; then
          echo  ${ERROR} && exit 1
      else
          echo "Ok"
      fi
  done
  rm -f $TMPFILE
}

main
