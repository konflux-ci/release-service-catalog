#!/bin/bash

TMPFILE=/tmp/$$.tpm
echo -en `cat xpto.json` > ${TMPFILE}


UNESCAPED=$(grep -Po  "(?<=<sanitize>)(.*)+(?=<\/sanitize>)" ${TMPFILE})
SANITIZED="$(printf "'%q'" ${UNESCAPED} | jq -cRs| sed 's|\\|\\\\|g')"

sed -Ei 's|"<sanitize>(.*)<\/sanitize>"|'${SANITIZED}'|g' ${TMPFILE} 

#rm -f ${TMPFILE}
