#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

USERNAME=${1:-awskrug}
REPONAME=${2:-cli-group}
GITHUB_TOKEN=${3:-$GITHUB_TOKEN}
MEETUP_TOKEN=${4:-$MEETUP_TOKEN}
SMS_API_URL=${5:-$SMS_API_URL}

CHANGED=
ANSWER=

MEETUP_ID="awskrug"

MEETUP_PREFIX="AWSKRUG CLI"

EVENT_ID=
EVENT_NAME=
EVENT_DATE=

mkdir -p ${SHELL_DIR}/target

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

make_paid() {
    if [ -z ${SMS_API_URL} ]; then
        return
    fi

    PAID=$(mktemp /tmp/meetup-paid-XXXXXX)

    # 카카오뱅크
    PHONE="15993333"

    # get sms paid
    curl -sL -X GET -G ${SMS_API_URL} -d phone_number=${PHONE} -d checked=false \
        | jq '.[] | "\(.id) \(.rows[0]) \(.rows[1]) \(.rows[2]) \(.rows[3]) \(.rows[4]) \(.rows[5])"' \
        > ${PAID}

    SMS_CNT=$(cat ${PAID} | wc -l)

    _result "문자 : ${SMS_CNT}"

    # output
    PAYLOG=${SHELL_DIR}/paid/${EVENT_DATE}.log

    while read VAR; do
        ARR=($(echo $VAR | cut -d'"' -f2))

        SMS_ID="${ARR[0]}"

        if [ "${ARR[6]}" == "입금" ] && [ "${ARR[7]}" == "5,000원" ]; then
            _result "${ARR[0]} - ${ARR[2]} - ${ARR[4]} ${ARR[5]} - ${ARR[6]} - ${ARR[7]} - ${ARR[8]}"

            echo "0 | 5000 | ${ARR[4]} ${ARR[5]} | ${ARR[8]}" >> ${PAYLOG}
        fi

        # put checked=true
        JSON="{\"checked\":true,\"phone_number\":\"${PHONE}\"}"
        curl -H 'Content-Type: application/json' -X PUT ${SMS_API_URL}/${SMS_ID} -d "${JSON}"
    done < ${PAID}
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
    OUTPUT=${SHELL_DIR}/rsvps/${EVENT_DATE}.md
    PAYLOG=${SHELL_DIR}/paid/${EVENT_DATE}.log

    touch ${PAYLOG}

    RSV_CNT=$(cat ${RSVPS} | wc -l)
    PAY_CNT=$(cat ${PAYLOG} | wc -l)

    _result "신청 : ${RSV_CNT}"
    _result "지불 : ${PAY_CNT}"

    printf "${PAY_CNT} / ${RSV_CNT}" > ${SHELL_DIR}/target/MESSAGE

    # title
    echo "# ${EVENT_NAME}" > ${OUTPUT}
    echo "" >> ${OUTPUT}
    echo "* 신청 : ${RSV_CNT}" >> ${OUTPUT}
    echo "* 지불 : ${PAY_CNT}" >> ${OUTPUT}
    echo "" >> ${OUTPUT}

    # table
    echo "ID | Paid | Name | Photo | Answer" >> ${OUTPUT}
    echo "-- | ---- | ---- | ----- | ------" >> ${OUTPUT}

    while read VAR; do
        echo "${VAR}" | cut -d'"' -f2 | xargs >> ${OUTPUT}
    done < ${RSVPS}

    # host
    sed -i "s/| true /| :sunglasses: /" ${OUTPUT}
    sed -i "s/| false /| /" ${OUTPUT}

    # paid
    if [ -f ${PAYLOG} ]; then
        while read VAR; do
            ARR=(${VAR})

            if [ "x${ARR[0]}" != "x0" ]; then
                # sed -i "s/${ARR[0]} | [a-z]* / ${ARR[0]} | :smile: /" ${OUTPUT}
                sed -i "s/${ARR[0]} | /${ARR[0]} | :smile: /" ${OUTPUT}
            fi
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

    _result "지불 : ${PAID}"
    _result "지출 : ${COST}"
    _result "잔액 : ${LEFT}"

    echo "" >> ${OUTPUT}
    echo "## summary" >> ${OUTPUT}
    echo "" >> ${OUTPUT}

    echo "Type | Amount" >> ${OUTPUT}
    echo "---- | ------" >> ${OUTPUT}
    echo "지불 | ${PAID}" >> ${OUTPUT}
    echo "지출 | ${COST}" >> ${OUTPUT}
    echo "잔액 | ${LEFT}" >> ${OUTPUT}
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

    echo "Date | Amount" >> ${OUTPUT}
    echo "---- | ------" >> ${OUTPUT}

    while read VAR; do
        cat ${SHELL_DIR}/${NAME}/${VAR} | awk '{print $3}' > ${TEMP}
        SUM=$(grep . ${TEMP} | paste -sd+ | bc)

        TOTAL=$(( ${TOTAL} + ${SUM} ))

        echo "$(echo ${VAR} | cut -d'.' -f1) | ${SUM}" >> ${OUTPUT}
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

# paid
make_paid

# rsvps
make_rsvps

# balance
make_balance

# git push
git_push

# done
_success "done."
