#!/bin/bash

# Cron this script to run periodically.  Recommended to run this every 4 hours to 1 day.
# Need to have python packages xq, jq, and yq.
pip install xq jq yq

arrRoot="/mnt/user/appdata/..." #Replace with whatever your root is for appdata for your instance.
ipaddress="192.168.1.x" #insert your local docker sonarr IP address

if [ -z "$arrUrl" ] || [ -z "$arrApiKey" ]; then
  arrUrlBase="$(cat ${arrRoot}/config.xml | xq | jq -r .Config.UrlBase)"
  if [ "$arrUrlBase" == "null" ]; then
    arrUrlBase=""
  else
    arrUrlBase="/$(echo "$arrUrlBase" | sed "s/\///g")"
  fi
  arrApiKey="$(cat ${arrRoot}/config.xml | xq | jq -r .Config.ApiKey)"
  arrPort="$(cat ${arrRoot}/config.xml | xq | jq -r .Config.Port)"
  arrUrl="http://${ipaddress}:${arrPort}${arrUrlBase}"
fi

# auto-clean up log file to reduce space usage
if [ -f "${arrRoot}/logs/QueueCleaner.txt" ]; then
	find ${arrRoot}/logs -type f -name "QueueCleaner.txt" -size +1024k -delete
fi

exec &>> "${arrRoot}/logs/QueueCleaner.txt"
chmod 666 "${arrRoot}/logs/QueueCleaner.txt"

log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: QueueCleaner :: "$1
}

arrQueueData="$(curl -s "$arrUrl/api/v3/queue?page=1&pagesize=1000000000&sortDirection=descending&sortKey=progress&includeUnknownSeriesItems=true&apikey=${arrApiKey}" | jq -r .records[])"
arrQueueIds=$(echo "$arrQueueData" | jq -r 'select(.status=="completed") | select(.trackedDownloadStatus=="warning") | .id')
arrQueueIdsCount=$(echo "$arrQueueData" | jq -r 'select(.status=="completed") | select(.trackedDownloadStatus=="warning") | .id' | wc -l)
if [ $arrQueueIdsCount -eq 0 ]; then
  log "No items in queue to clean up..."
else
  for queueId in $(echo $arrQueueIds); do
    arrQueueItemData="$(echo "$arrQueueData" | jq -r "select(.id==$queueId)")"
    arrQueueItemTitle="$(echo "$arrQueueItemData" | jq -r .title)"
    log "Removing Failed Queue Item ID: $queueId ($arrQueueItemTitle) from Sonarr..."
    curl -sX DELETE "$arrUrl/api/v3/queue/$queueId?removeFromClient=false&blocklist=true&apikey=${arrApiKey}"
  done
fi

arrQueueData="$(curl -s "$arrUrl/api/v3/queue?page=1&pagesize=1000000000&sortDirection=descending&sortKey=progress&includeUnknownSeriesItems=true&apikey=${arrApiKey}" | jq -r .records[])"
arrQueueIds=$(echo "$arrQueueData" | jq -r 'select(.status=="failed") | select(.trackedDownloadStatus=="warning") | .id')
arrQueueIdsCount=$(echo "$arrQueueData" | jq -r 'select(.status=="failed") | select(.trackedDownloadStatus=="warning") | .id' | wc -l)
if [ $arrQueueIdsCount -eq 0 ]; then
  log "No items in queue to clean up..."
else

  for queueId in $(echo $arrQueueIds); do
    arrQueueItemData="$(echo "$arrQueueData" | jq -r "select(.id==$queueId)")"
    arrQueueItemTitle="$(echo "$arrQueueItemData" | jq -r .title)"
    log "Removing Failed Queue Item ID: $queueId ($arrQueueItemTitle) from Sonarr..."
    curl -sX DELETE "$arrUrl/api/v3/queue/$queueId?removeFromClient=false&blocklist=true&apikey=${arrApiKey}"
  done
fi

exit
