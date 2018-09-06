#!/bin/bash

SHELL_DIR=$(dirname $0)

USERNAME=${1:-awskrug}
REPONAME=${2:-cli-group}
GITHUB_TOKEN=${3}

MEETUP_ID="awskrug"

MEETUP_PREFIX="AWSKRUG CLI"

ANSWER=

_echo() {
    echo -e "$1"
}

_command() {
    _echo "$ $@" 3
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

EVENTS=$(mktemp /tmp/meetup-events-XXXXXX)

# meetup events
curl -sL https://api.meetup.com/${MEETUP_ID}/events | PREFIX="${MEETUP_PREFIX}" \
    jq ['.[] | select(.name | contains(env.PREFIX)) | {id,name,local_date}'][0] > ${EVENTS}

EVENT_ID=$(cat ${EVENTS} | grep '"id"' | cut -d'"' -f4 | xargs)
EVENT_NAME=$(cat ${EVENTS} | grep '"name"' | cut -d'"' -f4 | xargs)
EVENT_DATE=$(cat ${EVENTS} | grep '"local_date"' | cut -d'"' -f4 | xargs)

if [ -z ${EVENT_ID} ]; then
    _success "Not found event."
fi

# readme.md
OUTPUT=${SHELL_DIR}/README.md

COUNT=$(cat ${OUTPUT} | grep "\-\- meetup ${MEETUP_ID} \-\- ${EVENT_ID} \-\-" | wc -l | xargs)

if [ "x${COUNT}" == "x0" ]; then
    # meetup count
    IDX=$(grep "\-\- meetup count \-\-" ${OUTPUT} | cut -d' ' -f5)
    IDX=$(( ${IDX} + 1 ))

    _echo "제${IDX}회 ${EVENT_NAME}"

    EVENT=$(mktemp /tmp/meetup-new-event-XXXXXX)

    # new event
    echo "" > ${EVENT}
    echo "<!-- meetup ${MEETUP_ID} -- ${EVENT_ID} -->" >> ${EVENT}
    echo "" >> ${EVENT}
    echo "## [제${IDX}회 ${EVENT_NAME}](https://www.meetup.com/${MEETUP_ID}/events/${EVENT_ID}/)" >> ${EVENT}

    # replace event info
    sed -i "/\-\- history \-\-/r ${EVENT}" ${OUTPUT}

    # replace meetup count
    sed -i "s/\-\- meetup count \-\- [0-9]* \-\-/-- meetup count -- ${IDX} --/" ${OUTPUT}
fi

# rsvps
PAYLOG=${SHELL_DIR}/paid/${EVENT_DATE}.log
OUTPUT=${SHELL_DIR}/rsvps/${EVENT_DATE}.md

# meetup events rsvps
curl -sL https://api.meetup.com/${MEETUP_ID}/events/${EVENT_ID}/rsvps | \
    jq '.[] | .member as $m | [$m.id,$m.name,$m.photo.thumb_link,$m.event_context.host] | " \(.[0]) | \(.[3]) | \(.[1]) | ![\(.[1])](\(.[2]))"' > ${EVENTS}

# title
echo "# ${EVENT_NAME}" > ${OUTPUT}
echo "" >> ${OUTPUT}
echo "* 신청 : $(cat ${EVENTS} | wc -l)" >> ${OUTPUT}
echo "* 지불 : $(cat ${PAYLOG} | wc -l)" >> ${OUTPUT}
echo "" >> ${OUTPUT}

# table
echo " ID | Paid | Name | Photo" >> ${OUTPUT}
echo " -- | ---- | ---- | -----" >> ${OUTPUT}

while read VAR; do
    echo "${VAR}" | cut -d'"' -f2 >> ${OUTPUT}
done < ${EVENTS}

# host
sed -i "s/| true /| :sunglasses: /g" ${OUTPUT}
sed -i "s/| false /| /g" ${OUTPUT}

if [ -f ${PAYLOG} ]; then
    while read VAR; do
        ARR=(${VAR})
        # paid
        # sed -i "s/ ${ARR[0]} | [a-z]* / ${ARR[0]} | :smile: /" ${OUTPUT}
        sed -i "s/ ${ARR[0]} | / ${ARR[0]} | :smile: /" ${OUTPUT}
    done < ${PAYLOG}
fi

# not paid yet
# sed -i "s/| false |/| :ghost: |/g" ${OUTPUT}

# git push
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
