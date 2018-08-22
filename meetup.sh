#!/bin/bash

SHELL_DIR=$(dirname $0)

USERNAME=${1:-awskrug}
REPONAME=${2:-cli-group}
GITHUB_TOKEN=${3}

MEETUP_ID="awskrug"

ANSWER=

_echo() {
    echo -e "$1"
}

_success() {
    _echo "+ $@" 2
    exit 0
}

_error() {
    _echo "- $@" 1
    exit 1
}

################################################################################

TMP_EVENT="/tmp/meetup_events"

curl -sL https://api.meetup.com/${MEETUP_ID}/events | \
    jq ['.[] | select(.name | contains("AWSKRUG CLI")) | {id,name,local_date}'][0] > ${TMP_EVENT}

EVENT_ID=$(cat ${TMP_EVENT} | grep '"id"' | cut -d'"' -f4 | xargs)
EVENT_NAME=$(cat ${TMP_EVENT} | grep '"name"' | cut -d'"' -f4 | xargs)
EVENT_DATE=$(cat ${TMP_EVENT} | grep '"local_date"' | cut -d'"' -f4 | xargs)

if [ -z ${EVENT_ID} ]; then
    _error "Not found event."
fi

# readme.md
OUTPUT=${SHELL_DIR}/README.md

COUNT=$(cat ${OUTPUT} | grep "\-\- meetup ${MEETUP_ID} \-\- ${EVENT_ID} \-\-" | wc -l | xargs)

if [ "x${COUNT}" == "x0" ]; then
    # meetup count
    IDX=$(grep "\-\- meetup count \-\-" ${OUTPUT} | cut -d' ' -f5)
    IDX=$(( ${IDX} + 1 ))

    _echo "제${IDX}회 ${EVENT_NAME}"

    echo "" > ${TMP_EVENT}
    echo "<!-- meetup ${MEETUP_ID} -- ${EVENT_ID} -->" >> ${TMP_EVENT}
    echo "" >> ${TMP_EVENT}
    echo "## [제${IDX}회 ${EVENT_NAME}](https://www.meetup.com/${MEETUP_ID}/events/${EVENT_ID}/)" >> ${TMP_EVENT}

    # replace event info
    sed -i "/\-\- history \-\-/r ${TMP_EVENT}" ${OUTPUT}

    # replace meetup count
    sed -i "s/\-\- meetup count \-\- [0-9]* \-\-/-- meetup count -- ${IDX} --/" ${OUTPUT}
fi

# rsvps
PAYLOG=${SHELL_DIR}/paid/${EVENT_DATE}.log
OUTPUT=${SHELL_DIR}/rsvps/${EVENT_DATE}.md

echo "# ${EVENT_NAME}" > ${OUTPUT}
echo "" >> ${OUTPUT}

echo " ID | Paid | Name | Photo" >> ${OUTPUT}
echo " -- | ---- | ---- | -----" >> ${OUTPUT}

curl -sL https://api.meetup.com/${MEETUP_ID}/events/${EVENT_ID}/rsvps | \
    jq '.[] | . as $h | [$h.member.id,$h.member.name,$h.member.photo.thumb_link] | " \(.[0]) | | \(.[1]) | ![\(.[1])](\(.[2]))"' > ${TMP_EVENT}

while read VAR; do
    echo "${VAR}" | cut -d'"' -f2 >> ${OUTPUT}
done < ${TMP_EVENT}

if [ -f ${PAYLOG} ]; then
    while read VAR; do
        ARR=(${VAR})
        sed -i "s/ ${ARR[0]} | / ${ARR[0]} | :smile: /" ${OUTPUT}
    done < ${PAYLOG}
fi

if [ ! -z ${GITHUB_TOKEN} ]; then
    CHECK=
    DATE=$(date +%Y%m%d-%H%M)

    git config --global user.name "bot"
    git config --global user.email "bot@nalbam.com"

    git add --all
    git commit -m "${DATE}" > /dev/null 2>&1 || export CHECK=true

    if [ -z ${CHECK} ]; then
        _command "git push github.com/${USERNAME}/${REPONAME}"
        git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git master
    fi
fi

_success "done."
