#!/bin/bash

usage() {
    #figlet slack
cat <<EOF
================================================================================
      _            _
  ___| | __ _  ___| | __
 / __| |/ _' |/ __| |/ /
 \__ \ | (_| | (__|   <
 |___/_|\__,_|\___|_|\_\\
================================================================================
 Usage: slack.sh [args] {message}

 Basic Arguments:
   webhook_url|url  Send your JSON payloads to this URL.
   channel          Channel, private group, or IM channel to send message to.
   username         Set your bot's user name.
   emoji            Emoji to use as the icon for this message.

 Attachments Arguments:
   color            Like traffic signals. [good, warning, danger, or hex code (eg. #439FE0)].
   author           Small text used to display the author's name..
   title            The title is displayed as larger, bold text near the top of a message attachment.
   image            A valid URL to an image file that will be displayed inside a message attachment.
   footer           Add some brief text to help contextualize and identify an attachment.
================================================================================
EOF
    exit 1
}

for v in "$@"; do
    case ${v} in
    -d|--debug|--debug=*)
        debug="Y"
        shift
        ;;
    -u=*|--url=*|--webhook_url=*)
        webhook_url="${v#*=}"
        shift
        ;;
    --token=*)
        token="${v#*=}"
        shift
        ;;
    --channel=*)
        channel="${v#*=}"
        shift
        ;;
    --emoji=*|--icon_emoji=*)
        icon_emoji="${v#*=}"
        shift
        ;;
    --username=*)
        username="${v#*=}"
        shift
        ;;
    --color=*)
        color="${v#*=}"
        shift
        ;;
    --author=*|--author_name=*)
        author_name="${v#*=}"
        shift
        ;;
    --author_link=*)
        author_link="${v#*=}"
        shift
        ;;
    --author_icon=*)
        author_icon="${v#*=}"
        shift
        ;;
    --title=*)
        title="${v#*=}"
        shift
        ;;
    --title_link=*)
        title_link="${v#*=}"
        shift
        ;;
    --image=*|--image_url=*)
        image_url="${v#*=}"
        shift
        ;;
    --thumb=*|--thumb_url=*)
        thumb_url="${v#*=}"
        shift
        ;;
    --footer=*)
        footer="${v#*=}"
        shift
        ;;
    --footer_icon=*)
        footer_icon="${v#*=}"
        shift
        ;;
    *)
        text="$*"
        break
        ;;
    esac
done

if [ "${token}" != "" ]; then
    webhook_url="https://hooks.slack.com/services/${token}"
fi

if [ "${webhook_url}" == "" ]; then
    usage
fi
if [ "${text}" == "" ]; then
    usage
fi

message=$(echo "${text}" | sed 's/"/\"/g' | sed "s/'/\'/g" | sed "s/%/%25/g")

json="{"
    if [ "${channel}" != "" ]; then
        json="$json\"channel\":\"${channel}\","
    fi
    if [ "${icon_emoji}" != "" ]; then
        json="$json\"icon_emoji\":\"${icon_emoji}\","
    fi
    if [ "${username}" != "" ]; then
        json="$json\"username\":\"${username}\","
    fi
    json="$json\"attachments\":[{"
        if [ "${color}" != "" ]; then
            json="$json\"color\":\"${color}\","
        fi
        if [ "${author_name}" != "" ]; then
            json="$json\"author_name\":\"${author_name}\","
        fi
        if [ "${author_link}" != "" ]; then
            json="$json\"author_link\":\"${author_link}\","
        fi
        if [ "${author_icon}" != "" ]; then
            json="$json\"author_icon\":\"${author_icon}\","
        fi
        if [ "${title}" != "" ]; then
            json="$json\"title\":\"${title}\","
        fi
        if [ "${title_link}" != "" ]; then
            json="$json\"title_link\":\"${title_link}\","
        fi
        if [ "${image_url}" != "" ]; then
            json="$json\"image_url\":\"${image_url}\","
        fi
        if [ "${thumb_url}" != "" ]; then
            json="$json\"thumb_url\":\"${thumb_url}\","
        fi
        if [ "${footer}" != "" ]; then
            json="$json\"footer\":\"${footer}\","
        fi
        if [ "${footer_icon}" != "" ]; then
            json="$json\"footer_icon\":\"${footer_icon}\","
        fi
        json="$json\"text\":\"${message}\""
    json="$json}]"
json="$json}"

if [ "${debug}" == "" ]; then
    curl -s -d "payload=${json}" "${webhook_url}"
else
    command -v jq > /dev/null || JQ="N"
    echo "url=${webhook_url}"
    if [ -z ${JQ} ]; then
        echo "${json}" | jq -C '.'
    else
        echo "${json}"
    fi
fi
