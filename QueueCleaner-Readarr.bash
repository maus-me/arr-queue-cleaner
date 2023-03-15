#!/bin/bash

# Cron this script to run periodically.  Recommended to run this periodically on something like a cron.
# Need to have python packages yq to run, the below pip command can be removed after install if you are running in a persistent environment.
# Script code is mostly a mirrored from https://github.com/RandomNinjaAtk/docker-readarr-extended/ with minor tweaks for PT usage.

pip install yq 

# !!! CONFIG STARTS !!!

arrRoot="/mnt/user/appdata/readarr" #Replace with whatever your root is for appdata for your instance.
ipaddress="x" #insert your local docker readarr IP address

# !!! CONFIG ENDS !!!

scriptVersion="1.0.002"

if [ -z "$arrUrl" ] || [ -z "$arrApiKey" ]; then
  arrUrlBase="$(cat ${arrRoot}/config.xml | xq | jq -r .Config.UrlBase)"
  if [ "$arrUrlBase" == "null" ]; then
    arrUrlBase=""
  else
    arrUrlBase="/$(echo "$arrUrlBase" | sed "s/\///g")"
  fi
  arrApiKey="$(cat ${arrRoot}/config.xml | xq | jq -r .Config.ApiKey)"
  arrPort="$(cat ${arrRoot}/config.xml | xq | jq -r .Config.Port)"
  arrUrl="http://localhost:${arrPort}${arrUrlBase}"
fi

# auto-clean up log file to reduce space usage
if [ -f "${arrRoot}/logs/QueueCleaner.txt" ]; then
	find ${arrRoot}/logs -type f -name "QueueCleaner.txt" -size +1024k -delete
fi

exec &> >(tee -a "${arrRoot}/logs/QueueCleaner.txt")
chmod 666 "${arrRoot}/logs/QueueCleaner.txt"

log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: QueueCleaner :: $scriptVersion :: "$1
}

CleanerProcess() {
	arrQueueData="$(curl -s "$arrUrl/api/v1/queue?page=1&pagesize=200&sortDirection=descending&sortKey=progress&includeUnknownAuthorItems=true&apikey=${arrApiKey}" | jq -r .records[])"
	arrQueueIds=$(echo "$arrQueueData" | jq -r 'select(.status=="completed") | select(.trackedDownloadStatus=="warning") | .id')
	arrQueueIdsCount=$(echo "$arrQueueData" | jq -r 'select(.status=="completed") | select(.trackedDownloadStatus=="warning") | .id' | wc -l)
	if [ $arrQueueIdsCount -eq 0 ]; then
		log "No items in queue to clean up..."
	else
		for queueId in $(echo $arrQueueIds); do
			arrQueueItemData="$(echo "$arrQueueData" | jq -r "select(.id==$queueId)")"
			arrQueueItemTitle="$(echo "$arrQueueItemData" | jq -r .title)"
			log "Removing Failed Queue Item ID: $queueId ($arrQueueItemTitle) from Readarr..."
			curl -sX DELETE "$arrUrl/api/v1/queue/$queueId?removeFromClient=false&blocklist=true&skipredownload=false&apikey=${arrApiKey}"
		done
	fi

	arrQueueData="$(curl -s "$arrUrl/api/v1/queue?page=1&pagesize=200&sortDirection=descending&sortKey=progress&includeUnknownAuthorItems=true&apikey=${arrApiKey}" | jq -r .records[])"
	arrQueueIds=$(echo "$arrQueueData" | jq -r 'select(.status=="failed") | select(.trackedDownloadStatus=="warning") | .id')
	arrQueueIdsCount=$(echo "$arrQueueData" | jq -r 'select(.status=="failed") | select(.trackedDownloadStatus=="warning") | .id' | wc -l)
	if [ $arrQueueIdsCount -eq 0 ]; then
		log "No items in queue to clean up..."
	else
		for queueId in $(echo $arrQueueIds); do
			arrQueueItemData="$(echo "$arrQueueData" | jq -r "select(.id==$queueId)")"
			arrQueueItemTitle="$(echo "$arrQueueItemData" | jq -r .title)"
			log "Removing Failed Queue Item ID: $queueId ($arrQueueItemTitle) from Readarr..."
			curl -sX DELETE "$arrUrl/api/v1/queue/$queueId?removeFromClient=false&blocklist=true&skipredownload=false&apikey=${arrApiKey}"
		done
	fi
}
CleanerProcess

exit
