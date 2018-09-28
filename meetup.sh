#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

USERNAME=${1:-awskrug}
REPONAME=${2:-cli-group}
GITHUB_TOKEN=${3}
SLACK_TOKEN=${4}

CHANGED=
ANSWER=

MEETUP_ID="awskrug"

MEETUP_PREFIX="AWSKRUG CLI"

EVENTS=$(mktemp /tmp/meetup-events-XXXXXX)

EVENT_ID=
EVENT_NAME=
EVENT_DATE=

################################################################################

command -v tput > /dev/null || TPUT=false

_echo() {
    echo -e "$1"
    # if [ -z ${TPUT} ] && [ ! -z $2 ]; then
    #     echo -e "$(tput setaf $2)$1$(tput sgr0)"
    # else
    #     echo -e "$1"
    # fi
}

_result() {
    _echo "# $@" 4
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

check_events() {
    curl -sL https://api.meetup.com/${MEETUP_ID}/events | PREFIX="${MEETUP_PREFIX}" \
        jq ['.[] | select(.name | contains(env.PREFIX)) | {id,name,local_date}'][0] > ${EVENTS}

    EVENT_ID=$(cat ${EVENTS} | grep '"id"' | cut -d'"' -f4 | xargs)
    EVENT_NAME=$(cat ${EVENTS} | grep '"name"' | cut -d'"' -f4 | xargs)
    EVENT_DATE=$(cat ${EVENTS} | grep '"local_date"' | cut -d'"' -f4 | xargs)

    if [ -z ${EVENT_ID} ]; then
        _success "Not found event."
    fi

    _result "${EVENT_NAME}"
}

make_readme() {
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
}

make_rsvps() {
    OUTPUT=${SHELL_DIR}/rsvps/${EVENT_DATE}.md
    PAYLOG=${SHELL_DIR}/paid/${EVENT_DATE}.log

    # meetup events rsvps
    curl -sL https://api.meetup.com/${MEETUP_ID}/events/${EVENT_ID}/rsvps | \
        jq '.[] | .member as $m | [$m.id,$m.name,$m.photo.thumb_link,$m.event_context.host] | " \(.[0]) | \(.[3]) | \(.[1]) | ![\(.[1])](\(.[2]))"' > ${EVENTS}

    touch ${PAYLOG}

    _result "신청 : $(cat ${EVENTS} | wc -l)"
    _result "지불 : $(cat ${PAYLOG} | wc -l)"

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
}

make_balance() {
    OUTPUT=${SHELL_DIR}/balance/balance.md

    echo "# balance" > ${OUTPUT}

    PAID=$(make_sum paid)
    COST=$(make_sum cost)
    LEFT=$(( ${PAID} - ${COST} ))

    _result "PAID : ${PAID}"
    _result "COST : ${COST}"
    _result "LEFT : ${LEFT}"

    echo "" >> ${OUTPUT}
    echo "## total" >> ${OUTPUT}
    echo "" >> ${OUTPUT}

    echo " Type | Amount" >> ${OUTPUT}
    echo " ---- | ------" >> ${OUTPUT}
    echo " PAID | ${PAID}" >> ${OUTPUT}
    echo " COST | ${COST}" >> ${OUTPUT}
    echo " LEFT | ${LEFT}" >> ${OUTPUT}
}

make_sum() {
    NAME=$1

    LIST=$(mktemp /tmp/meetup-${NAME}-list-XXXXXX)
    TEMP=$(mktemp /tmp/meetup-${NAME}-temp-XXXXXX)

    TOTAL=0

    ls ${SHELL_DIR}/${NAME}/ | sort > ${LIST}

    echo "" >> ${OUTPUT}
    echo "## ${NAME}" >> ${OUTPUT}
    echo "" >> ${OUTPUT}

    echo " Date | Amount" >> ${OUTPUT}
    echo " ---- | ------" >> ${OUTPUT}

    while read VAR; do
        cat ${SHELL_DIR}/${NAME}/${VAR} | awk '{print $3}' > ${TEMP}
        SUM=$(grep . ${TEMP} | paste -sd+ | bc)

        TOTAL=$(( ${TOTAL} + ${SUM} ))

        echo " ${VAR} | ${SUM}" >> ${OUTPUT}
    done < ${LIST}

    echo ${TOTAL}
}

git_push() {
    if [ ! -z ${GITHUB_TOKEN} ]; then
        DATE=$(date +%Y%m%d-%H%M)

        git config --global user.name "bot"
        git config --global user.email "bot@nalbam.com"

        git add --all
        git commit -m "${DATE}" > /dev/null 2>&1 || export CHANGED=true

        if [ -z ${CHANGED} ]; then
            _command "git push github.com/${USERNAME}/${REPONAME}"
            git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git master
        fi
    fi
}

################################################################################

# events
check_events

# readme
make_readme

# rsvps
make_rsvps

# balance
make_balance

# git push
git_push

# done
_success "done."
