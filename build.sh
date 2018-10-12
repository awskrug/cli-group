#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

USERNAME=${CIRCLE_PROJECT_USERNAME:-awskrug}
REPONAME=${CIRCLE_PROJECT_REPONAME:-cli-group}

CHANGED=
ANSWER=

MEETUP_ID="awskrug"

MEETUP_PREFIX="AWSKRUG CLI"

EVENT_ID=
EVENT_NAME=
EVENT_DATE=

GIT_USERNAME="bot"
GIT_USEREMAIL="bot@nalbam.com"

mkdir -p ${SHELL_DIR}/target

################################################################################

# command -v tput > /dev/null || TPUT=false
TPUT=false

_echo() {
    if [ -z ${TPUT} ] && [ ! -z $2 ]; then
        echo -e "$(tput setaf $2)$1$(tput sgr0)"
    else
        echo -e "$1"
    fi
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
    EVENTS=$(mktemp /tmp/meetup-events-XXXXXX)

    curl -sL https://api.meetup.com/${MEETUP_ID}/events | PREFIX="${MEETUP_PREFIX}" \
        jq ['.[] | select(.name | contains(env.PREFIX)) | {id,name,local_date}'][0] > ${EVENTS}

    EVENT_ID=$(cat ${EVENTS} | grep '"id"' | cut -d'"' -f4 | xargs)
    EVENT_NAME=$(cat ${EVENTS} | grep '"name"' | cut -d'"' -f4 | xargs)
    EVENT_DATE=$(cat ${EVENTS} | grep '"local_date"' | cut -d'"' -f4 | xargs)

    if [ -z ${EVENT_ID} ]; then
        _success "Not found event."
    fi

    _result "${EVENT_NAME}"
    _result "${EVENT_ID}"
}

make_readme() {
    README=${SHELL_DIR}/README.md

    COUNT=$(cat ${README} | grep "\-\- meetup ${MEETUP_ID} \-\- ${EVENT_ID} \-\-" | wc -l | xargs)

    if [ "x${COUNT}" != "x0" ]; then
        return
    fi

    # meetup count
    IDX=$(grep "\-\- meetup count \-\-" ${README} | cut -d' ' -f5)
    IDX=$(( ${IDX} + 1 ))

    _echo "제${IDX}회 ${EVENT_NAME}"

    EVENT=$(mktemp /tmp/meetup-new-event-XXXXXX)

    # new event
    echo "" > ${EVENT}
    echo "<!-- meetup ${MEETUP_ID} -- ${EVENT_ID} -->" >> ${EVENT}
    echo "" >> ${EVENT}
    echo "## [제${IDX}회 ${EVENT_NAME}](https://www.meetup.com/${MEETUP_ID}/events/${EVENT_ID}/)" >> ${EVENT}

    # replace event info
    sed -i "/\-\- history \-\-/r ${EVENT}" ${README}

    # replace meetup count
    sed -i "s/\-\- meetup count \-\- [0-9]* \-\-/-- meetup count -- ${IDX} --/" ${README}
}

make_paid() {
    if [ -z ${SMS_API_URL} ]; then
        return
    fi

    PAID=$(mktemp /tmp/meetup-paid-XXXXXX)

    # 카카오뱅크
    PHONE="15993333"

    # get sms paid
    curl -sL -X GET -G ${SMS_API_URL} -d phone_number=${PHONE} -d checked=false \
        | jq '.[] | "\(.id) \(.message)"' | sed -e 's/\\n/ /g' \
        > ${PAID}

    SMS_CNT=$(cat ${PAID} | wc -l | xargs)

    _result "문자 : ${SMS_CNT}"

    # output
    RSVLOG=${SHELL_DIR}/rsvps/${EVENT_DATE}.md
    PAYLOG=${SHELL_DIR}/paid/${EVENT_DATE}.log

    while read VAR; do
        ARR=($(echo $VAR | cut -d'"' -f2))

        SMS_ID="${ARR[0]}"

        # add paid
        if [ "${ARR[6]}" == "입금" ] && [ "${ARR[7]}" == "5,000원" ]; then
            _result "${ARR[0]} - ${ARR[4]} ${ARR[5]} - ${ARR[8]}"

            MEM_ID="$(cat ${RSVLOG} | grep ${ARR[8]} | head -1 | cut -d' ' -f1 | xargs)"

            if [ "${MEM_ID}" == "" ]; then
                MEM_ID="0"
            else
                _result "${MEM_ID} - ${ARR[4]} ${ARR[5]} - ${ARR[8]}"
            fi

            echo "${MEM_ID} | 5000 | ${ARR[4]} ${ARR[5]} | ${ARR[8]} | ${SMS_ID}" >> ${PAYLOG}
        fi

        # put checked=true
        JSON="{\"checked\":true,\"phone_number\":\"${PHONE}\"}"
        curl -H 'Content-Type: application/json' -X PUT ${SMS_API_URL}/${SMS_ID} -d "${JSON}"
    done < ${PAID}
}

check_paid() {
    # output
    RSVLOG=${SHELL_DIR}/rsvps/${EVENT_DATE}.md
    PAYLOG=${SHELL_DIR}/paid/${EVENT_DATE}.log

    while read VAR; do
        MEM_ID="$(echo ${VAR} | cut -d'|' -f1 | xargs)"
        if [ "x${MEM_ID}" != "x0" ]; then
            continue
        fi

        MEM_NM="$(echo ${VAR} | cut -d'|' -f4 | xargs)"
        if [ "${MEM_NM}" == "" ]; then
            continue
        fi

        MEM_ID="$(cat ${RSVLOG} | grep ${MEM_NM} | head -1 | cut -d' ' -f1 | xargs)"
        if [ "${MEM_ID}" == "" ]; then
            continue
        fi

        SMS_ID="$(echo ${VAR} | cut -d'|' -f5 | xargs)"
        if [ "${SMS_ID}" == "" ]; then
            continue
        fi

        _result "${MEM_ID} - ${VAR}"

        NUM=$(cat ${PAYLOG} | grep -n "| ${SMS_ID}" | cut -d':' -f1)
        if [ "${NUM}" == "" ]; then
            continue
        fi

        # replace RSVLOG
        REPLACED="${MEM_ID} | ${VAR:4}"
        REPLACED="$(echo "${REPLACED}" | sed 's/\//\\\//')"

        _result "${REPLACED}"

        sed -i "${NUM}s/.*/${REPLACED}/" ${PAYLOG}
    done < ${PAYLOG}
}

make_rsvps() {
    RSVPS=$(mktemp /tmp/meetup-rsvps-XXXXXX)

    # meetup events rsvps
    curl -sL -X GET -G https://api.meetup.com/${MEETUP_ID}/events/${EVENT_ID}/rsvps \
        -d sign=true \
        -d key=${MEETUP_TOKEN} \
        -d fields=answers \
        | jq '.[] | " \(.member.id) | \(.member.event_context.host) | \(.member.name) | ![\(.member.name)](\(.member.photo.thumb_link)) || \(.answers[0].answer) "' \
        > ${RSVPS}

    # answers
    for i in {1..5}; do
        sed -i -E 's/(.*) \|\| (.*)[\/|@|,](.*) /\1 \|\| \2 /' ${RSVPS}
    done
    sed -i 's/ || / | /' ${RSVPS}

    # output
    RSVLOG=${SHELL_DIR}/rsvps/${EVENT_DATE}.md
    PAYLOG=${SHELL_DIR}/paid/${EVENT_DATE}.log

    touch ${PAYLOG}

    RSV_CNT=$(cat ${RSVPS} | wc -l | xargs)
    PAY_CNT=$(cat ${PAYLOG} | wc -l | xargs)

    _result "신청 : ${RSV_CNT}"
    _result "지불 : ${PAY_CNT}"

    # for slack
    printf "${PAY_CNT} / ${RSV_CNT}" > ${SHELL_DIR}/target/VERSION

    # title
    echo "# ${EVENT_NAME}" > ${RSVLOG}
    echo "" >> ${RSVLOG}
    echo "* 신청 : ${RSV_CNT}" >> ${RSVLOG}
    echo "* 지불 : ${PAY_CNT}" >> ${RSVLOG}
    echo "" >> ${RSVLOG}

    # table
    echo "ID | Paid | Name | Photo | Answer" >> ${RSVLOG}
    echo "-- | ---- | ---- | ----- | ------" >> ${RSVLOG}

    while read VAR; do
        echo "${VAR}" | cut -d'"' -f2 | xargs >> ${RSVLOG}
    done < ${RSVPS}

    # host
    sed -i "s/| true /| :sunglasses: /" ${RSVLOG}
    sed -i "s/| false /| /" ${RSVLOG}

    # paid
    if [ -f ${PAYLOG} ]; then
        while read VAR; do
            ARR=(${VAR})

            if [ "x${ARR[0]}" != "x0" ]; then
                # sed -i "s/${ARR[0]} | [a-z]* / ${ARR[0]} | :smile: /" ${RSVLOG}
                sed -i "s/${ARR[0]} | /${ARR[0]} | :smile: /" ${RSVLOG}
            fi
        done < ${PAYLOG}
    fi

    # not paid yet
    # sed -i "s/| false |/| :ghost: |/g" ${RSVLOG}
}

make_balance() {
    BALANCE=${SHELL_DIR}/balance/balance.md

    echo "# balance" > ${BALANCE}

    PAID=$(make_sum paid)
    COST=$(make_sum cost)
    LEFT=$(( ${PAID} - ${COST} ))

    _result "지불 : ${PAID}"
    _result "지출 : ${COST}"
    _result "잔액 : ${LEFT}"

    echo "" >> ${BALANCE}
    echo "## summary" >> ${BALANCE}
    echo "" >> ${BALANCE}

    echo "Type | Amount" >> ${BALANCE}
    echo "---- | ------" >> ${BALANCE}
    echo "지불 | ${PAID}" >> ${BALANCE}
    echo "지출 | ${COST}" >> ${BALANCE}
    echo "잔액 | ${LEFT}" >> ${BALANCE}
}

make_sum() {
    NAME=$1

    LIST=$(mktemp /tmp/meetup-${NAME}-list-XXXXXX)
    TEMP=$(mktemp /tmp/meetup-${NAME}-temp-XXXXXX)

    TOTAL=0

    ls ${SHELL_DIR}/${NAME}/ | sort > ${LIST}

    echo "" >> ${BALANCE}
    echo "## ${NAME}" >> ${BALANCE}
    echo "" >> ${BALANCE}

    echo "Date | Amount" >> ${BALANCE}
    echo "---- | ------" >> ${BALANCE}

    while read VAR; do
        cat ${SHELL_DIR}/${NAME}/${VAR} | awk '{print $3}' > ${TEMP}
        SUM=$(grep . ${TEMP} | paste -sd+ | bc)

        TOTAL=$(( ${TOTAL} + ${SUM} ))

        echo "$(echo ${VAR} | cut -d'.' -f1) | ${SUM}" >> ${BALANCE}
    done < ${LIST}

    echo ${TOTAL}
}

git_push() {
    if [ -z ${GITHUB_TOKEN} ]; then
        return
    fi

    DATE=$(date +%Y%m%d-%H%M)

    git config --global user.name "${GIT_USERNAME}"
    git config --global user.email "${GIT_USEREMAIL}"

    git add --all
    git commit -m "${DATE}" > /dev/null 2>&1 || export CHANGED=true

    if [ -z ${CHANGED} ]; then
        _command "git push github.com/${USERNAME}/${REPONAME}"
        git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git master

        if [ ! -z ${SLACK_TOKEN} ]; then
            VERSION="$(cat ${SHELL_DIR}/target/VERSION | xargs)"
            ${SHELL_DIR}/slack.sh --token="${SLACK_TOKEN}" --channel="cli-group" \
                --emoji=":construction_worker:" --username="${MEETUP_ID}" \
                --title="meetup updated" "\`${VERSION}\`"
        fi
    fi
}

################################################################################

# events
check_events

# readme
make_readme

# paid
make_paid

# check
check_paid

# rsvps
make_rsvps

# balance
make_balance

# git push
git_push

# done
_success "done."
