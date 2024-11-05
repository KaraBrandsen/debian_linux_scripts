#!/bin/bash

SONARR_PORT=7878
APP_UID=$SUDO_USER
APP_GUID=users

HOST=$(hostname -I)
IP_LOCAL=$(grep -oP '^\S*' <<<"$HOST")

echo "-----------------------------Installing Sonarr-----------------------------"
set -euo pipefail

app="sonarr"
app_port=$SONARR_PORT
app_umask="0002"
branch="main"
installdir="/opt"              # {Update me if needed} Install Location
bindir="${installdir}/${app^}" # Full Path to Install Location
datadir="/var/lib/$app/"       # {Update me if needed} AppData directory to use
app_bin=${app^}                # Binary Name of the app
APP_UID=$(echo "$APP_UID" | tr -d ' ')
APP_UID=${APP_UID:-$app}
APP_GUID=$(echo "$APP_GUID" | tr -d ' ')
APP_GUID=${APP_GUID:-media}

echo "This will install [${app^}] to [$bindir] and use [$datadir] for the AppData Directory"

echo "Stoppin the App if running"
if service --status-all | grep -Fq "$app"; then
    systemctl stop "$app"
    systemctl disable "$app".service
    echo "Stopped existing $app"
fi

mkdir -p "$datadir"
chown -R "$APP_UID":"$APP_GUID" "$datadir"
chmod 775 "$datadir"
echo "Directories created"

echo "Downloading and installing the App"
ARCH=$(dpkg --print-architecture)
dlbase="https://services.sonarr.tv/v1/download/$branch/latest?version=4&os=linux"
case "$ARCH" in
"amd64") DLURL="${dlbase}&arch=x64" ;;
"armhf") DLURL="${dlbase}&arch=arm" ;;
"arm64") DLURL="${dlbase}&arch=arm64" ;;
*)
    echo "Arch not supported"
    exit 1
    ;;
esac

rm -f "${app^}".*.tar.gz
wget --inet4-only --content-disposition "$DLURL"
tar -xvzf "${app^}".*.tar.gz
echo "Installation files downloaded and extracted"

echo "Removing existing installation"
rm -rf "$bindir"

echo "Installing..."
mv "${app^}" $installdir
chown "$APP_UID":"$APP_GUID" -R "$bindir"
chmod 775 "$bindir"
rm -rf "${app^}.*.tar.gz"
touch "$datadir"/update_required
chown "$APP_UID":"$APP_GUID" "$datadir"/update_required
echo "App Installed"

echo "Removing old service file"
rm -rf /etc/systemd/system/"$app".service

echo "Creating service file"
cat <<EOF | tee /etc/systemd/system/"$app".service >/dev/null
[Unit]
Description=${app^} Daemon
After=syslog.target network.target
[Service]
User=$APP_UID
Group=$APP_GUID
UMask=$app_umask
Type=simple
ExecStart=$bindir/$app_bin -nobrowser -data=$datadir
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
sleep 2

echo "Service file created. Attempting to start the app"
systemctl -q daemon-reload
systemctl enable --now -q "$app"
sleep 5

echo "Checking if the service is up and running..."
while ! systemctl is-active --quiet "$app"; do
    sleep 5
done

sed -i "s/>8989</>$app_port</" "$datadir"config.xml
systemctl restart -q $app

echo -e "${app^} installation and service start up is complete!"
echo -e "Attempting to check for a connection at http://$IP_LOCAL:$app_port..."

sleep 15

STATUS="$(systemctl is-active "$app")"
if [ "${STATUS}" = "active" ]; then
    SONARR_APIKEY=$(grep "ApiKey" "$datadir/config.xml" | cut -d '>' -f 2 | cut -d '<' -f 1)

    if grep "api_key" "/home/$APP_UID/.sabnzbd/sabnzbd.ini" ; then
        SABNZBD_APIKEY=$(grep "api_key" "/home/$APP_UID/.sabnzbd/sabnzbd.ini" | cut -d "=" -f 2 | xargs)
        
        if [ "$INSTALL_SABNZBD" == "true" ] ; then
            echo "Adding Download Client SABNZBd:"
            curl -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_APIKEY" -H "accept: application/json" -X POST "http://$IP_LOCAL:$SONARR_PORT/api/v3/downloadclient" --data '{"enable":true,"protocol":"usenet","priority":1,"removeCompletedDownloads":true,"removeFailedDownloads":true,"name":"SABnzbd","fields":[{"order":0,"name":"host","label":"Host","value":"localhost","type":"textbox","advanced":false,"privacy":"normal","isFloat":false},{"order":1,"name":"port","label":"Port","value":'"$SABNZBD_PORT"',"type":"textbox","advanced":false,"privacy":"normal","isFloat":false},{"order":2,"name":"useSsl","label":"Use SSL","helpText":"Use secure connection when connection to Sabnzbd","value":false,"type":"checkbox","advanced":false,"privacy":"normal","isFloat":false},{"order":3,"name":"urlBase","label":"URL Base","helpText":"Adds a prefix to the Sabnzbd url, such as http://[host]:[port]/[urlBase]/api","type":"textbox","advanced":true,"privacy":"normal","isFloat":false},{"order":4,"name":"apiKey","label":"API Key","value":"'"$SABNZBD_APIKEY"'","type":"textbox","advanced":false,"privacy":"apiKey","isFloat":false},{"order":5,"name":"username","label":"Username","value":"admin","type":"textbox","advanced":false,"privacy":"userName","isFloat":false},{"order":6,"name":"password","label":"Password","value":"password","type":"password","advanced":false,"privacy":"password","isFloat":false},{"order":7,"name":"tvCategory","label":"Category","helpText":"Adding a category specific to Sonarr avoids conflicts with unrelated non-Sonarr downloads. Using a category is optional, but strongly recommended.","value":"sonarr","type":"textbox","advanced":false,"privacy":"normal","isFloat":false},{"order":8,"name":"recentTvPriority","label":"Recent Priority","helpText":"Priority to use when grabbing episodes that aired within the last 14 days","value":-100,"type":"select","advanced":false,"selectOptions":[{"value":-100,"name":"Default","order":-100},{"value":-2,"name":"Paused","order":-2},{"value":-1,"name":"Low","order":-1},{"value":0,"name":"Normal","order":0},{"value":1,"name":"High","order":1},{"value":2,"name":"Force","order":2}],"privacy":"normal","isFloat":false},{"order":9,"name":"olderTvPriority","label":"Older Priority","helpText":"Priority to use when grabbing episodes that aired over 14 days ago","value":-100,"type":"select","advanced":false,"selectOptions":[{"value":-100,"name":"Default","order":-100},{"value":-2,"name":"Paused","order":-2},{"value":-1,"name":"Low","order":-1},{"value":0,"name":"Normal","order":0},{"value":1,"name":"High","order":1},{"value":2,"name":"Force","order":2}],"privacy":"normal","isFloat":false}],"implementationName":"SABnzbd","implementation":"Sabnzbd","configContract":"SabnzbdSettings","infoLink":"https://wiki.servarr.com/sonarr/supported#sabnzbd","tags":[]}'
        fi
    fi

    if [ "$INSTALL_DELUGE" == "true" ] ; then
        echo "Adding Download Client Deluge:"
        curl -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_APIKEY" -H "accept: application/json" -X POST "http://$IP_LOCAL:$SONARR_PORT/api/v3/downloadclient" --data '{ "enable": true, "protocol": "torrent", "priority": 1, "removeCompletedDownloads": true, "removeFailedDownloads": true, "name": "Deluge", "fields": [ { "order": 0, "name": "host", "label": "Host", "value": "localhost", "type": "textbox", "advanced": false, "privacy": "normal", "isFloat": false }, { "order": 1, "name": "port", "label": "Port", "value": '"$DELUGE_PORT"', "type": "textbox", "advanced": false, "privacy": "normal", "isFloat": false }, { "order": 2, "name": "useSsl", "label": "Use SSL", "helpText": "Use secure connection when connection to Deluge", "value": false, "type": "checkbox", "advanced": false, "privacy": "normal", "isFloat": false }, { "order": 3, "name": "urlBase", "label": "URL Base", "helpText": "Adds a prefix to the deluge json url, see http://[host]:[port]/[urlBase]/json", "type": "textbox", "advanced": true, "privacy": "normal", "isFloat": false }, { "order": 4, "name": "password", "label": "Password", "value": "'"$DELUGE_PASSWORD"'", "type": "password", "advanced": false, "privacy": "password", "isFloat": false }, { "order": 5, "name": "tvCategory", "label": "Category", "helpText": "Adding a category specific to Sonarr avoids conflicts with unrelated non-Sonarr downloads. Using a category is optional, but strongly recommended.", "value": "sonarr", "type": "textbox", "advanced": false, "privacy": "normal", "isFloat": false }, { "order": 6, "name": "tvImportedCategory", "label": "Post-Import Category", "helpText": "Category for Sonarr to set after it has imported the download. Sonarr will not remove torrents in that category even if seeding finished. Leave blank to keep same category.", "type": "textbox", "advanced": true, "privacy": "normal", "isFloat": false }, { "order": 7, "name": "recentTvPriority", "label": "Recent Priority", "helpText": "Priority to use when grabbing episodes that aired within the last 14 days", "value": 0, "type": "select", "advanced": false, "selectOptions": [ { "value": 0, "name": "Last", "order": 0 }, { "value": 1, "name": "First", "order": 1 } ], "privacy": "normal", "isFloat": false }, { "order": 8, "name": "olderTvPriority", "label": "Older Priority", "helpText": "Priority to use when grabbing episodes that aired over 14 days ago", "value": 0, "type": "select", "advanced": false, "selectOptions": [ { "value": 0, "name": "Last", "order": 0 }, { "value": 1, "name": "First", "order": 1 } ], "privacy": "normal", "isFloat": false }, { "order": 9, "name": "addPaused", "label": "Add Paused", "value": false, "type": "checkbox", "advanced": false, "privacy": "normal", "isFloat": false }, { "order": 10, "name": "downloadDirectory", "label": "Download Directory", "helpText": "Optional location to put downloads in, leave blank to use the default Deluge location", "type": "textbox", "advanced": true, "privacy": "normal", "isFloat": false }, { "order": 11, "name": "completedDirectory", "label": "Move When Completed Directory", "helpText": "Optional location to move completed downloads to, leave blank to use the default Deluge location", "type": "textbox", "advanced": true, "privacy": "normal", "isFloat": false } ], "implementationName": "Deluge", "implementation": "Deluge", "configContract": "DelugeSettings", "infoLink": "https://wiki.servarr.com/sonarr/supported#deluge", "tags": []}'
    fi

    echo "Adding Indexers:"
    NUM_INDEXERS=$(echo "$INDEXERS" | jq length)

    for ((i = 0; i < NUM_INDEXERS; i++)) ; do
        INDEXER_NAME=$(echo $INDEXERS | jq ".[$i].INDEXER_NAME")
        INDEXER_URL=$(echo $INDEXERS | jq ".[$i].INDEXER_URL")		                
        INDEXER_API_PATH=$(echo $INDEXERS | jq ".[$i].INDEXER_API_PATH")							
        INDEXER_APIKEY=$(echo $INDEXERS | jq ".[$i].INDEXER_APIKEY")
        
        curl -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_APIKEY" -H "accept: application/json" -X POST "http://$IP_LOCAL:$SONARR_PORT/api/v3/indexer" --data '{"enableRss":true,"enableAutomaticSearch":true,"enableInteractiveSearch":true,"supportsRss":true,"supportsSearch":true,"protocol":"usenet","priority":25,"seasonSearchMaximumSingleEpisodeAge":0,"downloadClientId":0,"name":'$INDEXER_NAME',"fields":[{"order":0,"name":"baseUrl","label":"URL","value":'$INDEXER_URL',"type":"textbox","advanced":false,"privacy":"normal","isFloat":false},{"order":1,"name":"apiPath","label":"API Path","helpText":"Path to the api, usually /api","value":'$INDEXER_API_PATH',"type":"textbox","advanced":true,"privacy":"normal","isFloat":false},{"order":2,"name":"apiKey","label":"API Key","value":'$INDEXER_APIKEY',"type":"textbox","advanced":false,"privacy":"apiKey","isFloat":false},{"order":3,"name":"categories","label":"Categories","helpText":"Drop down list, leave blank to disable standard/daily shows","value":[5030,5040,5050,5070],"type":"select","advanced":false,"selectOptionsProviderAction":"newznabCategories","privacy":"normal","isFloat":false},{"order":4,"name":"animeCategories","label":"Anime Categories","helpText":"Drop down list, leave blank to disable anime","value":[5030,5040,5070],"type":"select","advanced":false,"selectOptionsProviderAction":"newznabCategories","privacy":"normal","isFloat":false},{"order":5,"name":"animeStandardFormatSearch","label":"Anime Standard Format Search","helpText":"Also search for anime using the standard numbering","value":false,"type":"checkbox","advanced":false,"privacy":"normal","isFloat":false},{"order":6,"name":"additionalParameters","label":"Additional Parameters","helpText":"Please note if you change the category you will have to add required/restricted rules about the subgroups to avoid foreign language releases.","type":"textbox","advanced":true,"privacy":"normal","isFloat":false},{"order":7,"name":"multiLanguages","label":"Multi Languages","helpText":"What languages are normally in a multi release on this indexer?","value":[],"type":"select","advanced":true,"selectOptions":[{"value":-2,"name":"Original","order":0},{"value":26,"name":"Arabic","order":0},{"value":41,"name":"Bosnian","order":0},{"value":28,"name":"Bulgarian","order":0},{"value":38,"name":"Catalan","order":0},{"value":10,"name":"Chinese","order":0},{"value":39,"name":"Croatian","order":0},{"value":25,"name":"Czech","order":0},{"value":6,"name":"Danish","order":0},{"value":7,"name":"Dutch","order":0},{"value":1,"name":"English","order":0},{"value":42,"name":"Estonian","order":0},{"value":16,"name":"Finnish","order":0},{"value":19,"name":"Flemish","order":0},{"value":2,"name":"French","order":0},{"value":4,"name":"German","order":0},{"value":20,"name":"Greek","order":0},{"value":23,"name":"Hebrew","order":0},{"value":27,"name":"Hindi","order":0},{"value":22,"name":"Hungarian","order":0},{"value":9,"name":"Icelandic","order":0},{"value":44,"name":"Indonesian","order":0},{"value":5,"name":"Italian","order":0},{"value":8,"name":"Japanese","order":0},{"value":21,"name":"Korean","order":0},{"value":36,"name":"Latvian","order":0},{"value":24,"name":"Lithuanian","order":0},{"value":45,"name":"Macedonian","order":0},{"value":29,"name":"Malayalam","order":0},{"value":15,"name":"Norwegian","order":0},{"value":37,"name":"Persian","order":0},{"value":12,"name":"Polish","order":0},{"value":18,"name":"Portuguese","order":0},{"value":33,"name":"Portuguese (Brazil)","order":0},{"value":35,"name":"Romanian","order":0},{"value":11,"name":"Russian","order":0},{"value":40,"name":"Serbian","order":0},{"value":31,"name":"Slovak","order":0},{"value":46,"name":"Slovenian","order":0},{"value":3,"name":"Spanish","order":0},{"value":34,"name":"Spanish (Latino)","order":0},{"value":14,"name":"Swedish","order":0},{"value":43,"name":"Tamil","order":0},{"value":32,"name":"Thai","order":0},{"value":17,"name":"Turkish","order":0},{"value":30,"name":"Ukrainian","order":0},{"value":13,"name":"Vietnamese","order":0}],"privacy":"normal","isFloat":false}],"implementationName":"Newznab","implementation":"Newznab","configContract":"NewznabSettings","infoLink":"https://wiki.servarr.com/sonarr/supported#newznab","tags":[]}'
    done

    echo "Adding Root Folders:"
    for FOLDER in ${SONARR_ROOT_FOLDER[@]}; do
        mkdir -p $FOLDER
        chown -R "$APP_UID":"$APP_GUID" $FOLDER
        chmod 775 "$FOLDER"
        
        curl -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_APIKEY" -H "accept: application/json" -X POST "http://$IP_LOCAL:$SONARR_PORT/api/v3/rootfolder" --data '{"path":"'"$FOLDER"'","accessible":true,"freeSpace":0,"unmappedFolders":[]}'
    done
    
    echo "Setting more sensible quality values"
    QUALITIES=$(curl -s -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_APIKEY" -H "accept: application/json" -X GET "http://$IP_LOCAL:$SONARR_PORT/api/v3/qualitydefinition")

    QUALITY_MAP='{"Unknown":{"minSize":1,"maxSize":50,"preferredSize":20},"SDTV":{"minSize":2,"maxSize":50,"preferredSize":20},"WEBRip-480p":{"minSize":2,"maxSize":50,"preferredSize":20},"WEBDL-480p":{"minSize":2,"maxSize":50,"preferredSize":20},"DVD":{"minSize":2,"maxSize":50,"preferredSize":20},"Bluray-480p":{"minSize":2,"maxSize":50,"preferredSize":20},"HDTV-720p":{"minSize":3,"maxSize":50,"preferredSize":20},"HDTV-1080p":{"minSize":4,"maxSize":50,"preferredSize":20},"Raw-HD":{"minSize":4,"maxSize":50,"preferredSize":20},"WEBRip-720p":{"minSize":3,"maxSize":50,"preferredSize":20},"WEBDL-720p":{"minSize":3,"maxSize":50,"preferredSize":20},"Bluray-720p":{"minSize":4,"maxSize":50,"preferredSize":20},"WEBRip-1080p":{"minSize":4,"maxSize":50,"preferredSize":20},"WEBDL-1080p":{"minSize":4,"maxSize":50,"preferredSize":20},"Bluray-1080p":{"minSize":4,"maxSize":50,"preferredSize":20},"Bluray-1080p Remux":{"minSize":0,"maxSize":50,"preferredSize":20},"HDTV-2160p":{"minSize":35,"maxSize":50,"preferredSize":35},"WEBRip-2160p":{"minSize":35,"maxSize":50,"preferredSize":35},"WEBDL-2160p":{"minSize":35,"maxSize":50,"preferredSize":35},"Bluray-2160p":{"minSize":35,"maxSize":50,"preferredSize":35},"Bluray-2160p Remux":{"minSize":35,"maxSize":50,"preferredSize":35}}'
    NUM_QUALITIES=$(echo "$QUALITIES" | jq length)

    for ((i = 0; i < NUM_QUALITIES; i++)) ; do

        QUALITY_NAME=$(echo $QUALITIES | jq ".[$i].title" ) 
        QUALITY=$(echo $QUALITIES | jq ".[$i]" ) 

        MINSIZE=$(echo $QUALITY_MAP | jq ".$QUALITY_NAME.minSize")  
        MAXSIZE=$(echo $QUALITY_MAP | jq ".$QUALITY_NAME.maxSize")  
        PREFSIZE=$(echo $QUALITY_MAP | jq ".$QUALITY_NAME.preferredSize")

        if [ "$MINSIZE" != "null" ] ; then
            QUALITY=$(echo $QUALITY | jq ".minSize=$MINSIZE | .maxSize=$MAXSIZE | .preferredSize=$PREFSIZE")
        fi

        curl -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_APIKEY" -H "accept: application/json" -X PUT "http://$IP_LOCAL:$SONARR_PORT/api/v3/qualitydefinition" --data "${QUALITY}"
    done

    echo "Setting Permissions"
    curl -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_APIKEY" -H "accept: application/json" -X PUT "http://$IP_LOCAL:$SONARR_PORT/api/v3/config/mediamanagement"  --data '{"autoUnmonitorPreviouslyDownloadedEpisodes":false,"recycleBin":"","recycleBinCleanupDays":7,"downloadPropersAndRepacks":"preferAndUpgrade","createEmptySeriesFolders":false,"deleteEmptyFolders":true,"fileDate":"none","rescanAfterRefresh":"always","setPermissionsLinux":true,"chmodFolder":"755","chownGroup":"'"$APP_GUID"'","episodeTitleRequired":"always","skipFreeSpaceCheckWhenImporting":false,"minimumFreeSpaceWhenImporting":100,"copyUsingHardlinks":true,"useScriptImport":false,"scriptImportPath":"","importExtraFiles":true,"extraFileExtensions":"srt","enableMediaInfo":true,"id":1}'

    echo "Setting Naming Conventions"
    curl -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_APIKEY" -H "accept: application/json" -X PUT "http://$IP_LOCAL:$SONARR_PORT/api/v3/config/naming"  --data '{"renameEpisodes":true,"replaceIllegalCharacters":true,"colonReplacementFormat":4,"customColonReplacementFormat":"","multiEpisodeStyle":5,"standardEpisodeFormat":"{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}","dailyEpisodeFormat":"{Series Title} - {Air-Date} - {Episode Title} {Quality Full}","animeEpisodeFormat":"{Series Title} - {absolute:000} - {Episode Title} {Quality Full}","seriesFolderFormat":"{Series Title}","seasonFolderFormat":"Season {season}","specialsFolderFormat":"Specials","id":1}'

    SONARR_URL="http://$IP_LOCAL:$app_port"
    echo "Browse to $SONARR_URL for the ${app^} GUI"
else
    echo "${app^} failed to start"
fi

echo "Installled Sonarr"