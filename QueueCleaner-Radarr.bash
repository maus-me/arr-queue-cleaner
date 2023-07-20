#!/bin/bash

# Cron this script to run periodically.  Recommended to run this periodically on something like a cron.
# Need to have python packages yq to run, the below pip command can be removed after install if you are running in a persistent environment.
# Script code is mostly a mirrored from https://github.com/RandomNinjaAtk/docker-sonarr-extended/blob/main/root/scripts/QueueCleaner.bash with minor tweaks for PT usage.

pip install yq 

# !!! CONFIG STARTS !!!

arrRoot="/mnt/user/appdata/radarr" #Replace with whatever your root is for appdata for your instance.
ipaddress="192.168.1.x" #insert your local docker sonarr IP address

# !!! CONFIG ENDS !!!

scriptVersion="1.0.009"

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

log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: QueueCleaner :: $scriptVersion :: "$1
}

# auto-clean up log file to reduce space usage
if [ -f "${arrRoot}/logs/QueueCleaner.txt" ]; then
	find ${arrRoot}/logs -type f -name "QueueCleaner.txt" -size +1024k -delete
fi

touch "${arrRoot}/logs/QueueCleaner.txt"
chmod 666 "${arrRoot}/logs/QueueCleaner.txt"
exec &> >(tee -a "${arrRoot}/logs/QueueCleaner.txt")

CleanerProcess() {
    #adjustments to the pagesize can be done, tested up to 200 without issue.
    arrQueueData="$(curl -s "$arrUrl/api/v3/queue?page=1&pagesize=200&sortDirection=descending&sortKey=progress&includeUnknownMovieItems=true&apikey=${arrApiKey}" | jq -r .records[])"
    arrQueueCompletedIds=$(echo "$arrQueueData" | jq -r 'select(.status=="completed") | select(.trackedDownloadStatus=="warning") | .id')
    arrQueueIdsCompletedCount=$(echo "$arrQueueData" | jq -r 'select(.status=="completed") | select(.trackedDownloadStatus=="warning") | .id' | wc -l)
    arrQueueFailedIds=$(echo "$arrQueueData" | jq -r 'select(.status=="failed") | .id')
    arrQueueIdsFailedCount=$(echo "$arrQueueData" | jq -r 'select(.status=="failed") | .id' | wc -l)
    arrQueuedIds=$(echo "$arrQueueCompletedIds"; echo "$arrQueueFailedIds")
    arrQueueIdsCount=$(( $arrQueueIdsCompletedCount + $arrQueueIdsFailedCount ))
    if [ $arrQueueIdsCount -eq 0 ]; then
        log "No items in queue to clean up..."
    else
        for queueId in $(echo $arrQueuedIds); do
            arrQueueItemData="$(echo "$arrQueueData" | jq -r "select(.id==$queueId)")"
            arrQueueItemTitle="$(echo "$arrQueueItemData" | jq -r .title)"
            arrEpisodeId="$(echo "$arrQueueItemData" | jq -r .episodeId)"
            arrEpisodeData="$(curl -s "$arrUrl/api/v3/episode/$arrEpisodeId?apikey=${arrApiKey}")"
            arrEpisodeTitle="$(echo "$arrEpisodeData" | jq -r .title)"
            arrEpisodeSeriesId="$(echo "$arrEpisodeData" | jq -r .seriesId)"
            if [ "$arrEpisodeTitle" == "TBA" ]; then
                log "ERROR :: Episode title is \"$arrEpisodeTitle\" and prevents auto-import, refreshing series..."
                refreshSeries=$(curl -s "$arrUrl/api/v3/command" -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $arrApiKey" --data-raw "{\"name\":\"RefreshSeries\",\"seriesId\":$arrEpisodeSeriesId}")
                continue
            else
                log "Removing Failed Queue Item ID: $queueId ($arrQueueItemTitle) from Sonarr..."
                # Use removeFromClient=false unless you want H&Rs, you should be utilizing other automation specific to your applications to manage seeding requirements.
                deleteItem=$(curl -sX DELETE "$arrUrl/api/v3/queue/$queueId?removeFromClient=false&blocklist=true&apikey=${arrApiKey}")
            fi
        done
    fi
}
CleanerProcess

exit
