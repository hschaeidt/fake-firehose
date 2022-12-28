url=$1 #A proper URL is all that should be sent to this script
host=$2
errors=0

if [[ "$url" == "" ]]
then
    echo "[WARN] Empty url, skipping" # Exit if an empty URL was sent
    exit 2
fi

# Check to see if domain name resolves. If not, exist
if [[ ! `dig $host +short` ]]
then
    echo "[WARN] DNS Lookup failed for $host, skipping"
fi

echo "[INFO] Archive is $archive"

while true # Loop endlessly
do

    today=`date +"%Y%m%d"`

    # Population size
    n=$(curl -X "GET" "https://$host/api/v2/instance" --no-progress-meter | jq .usage.users.active_month)
    # Z-score
    z=1.96
    # Error margin
    e=0.05
    # Standard deviation
    p=0.5

    # Not sure if this formula makes sense here as we are sampling posts and not population
    # To make this formula work we would actually need an information like "posts per hour"
    # and then sampling based on this information
    sample_size=$(echo "($z^2*($p*(1-$p))/($e^2))/(1+($z*($p*(1-$p))/($e^2*$n)))" | bc -l)
    throttle=$(echo "3600 / $sample_size" | bc)


    echo "[INFO] Starting to stream $url in 5 seconds"
    echo "[INFO] Archive status is $archive"
    echo "[INFO] $host has $n users, sampling $sample_size posts per hour"
    echo "[INFO] A sample will be taken every '$throttle' seconds"

    sleep 5s;

    # Im archive mode we'll only fetch the json stream to save resources from jq and sed
    if [[ $archive != "true" ]]
    then
    #Not in archive mode
        last_line_imported=`date +"%s"`

        curl -X "GET" "$url" \
            --no-progress-meter | \
            tee -a "/data/$today.json" | \
            grep url | \
            sed 's/data://g' | \

        while read -r line
        do
            now=`date +"%s"`
            next_import=$(echo "$last_line_imported + $throttle" | bc)
            if [[ $now -gt $next_import ]] && [[ $line == *"uri"* ]] && [[ $(echo "$line" | jq .language) == *"fr"* ]]
            then
                url=`echo $line | jq .url| sed 's/\"//g'`
                uri=`echo $line | jq .uri| sed 's/\"//g'`

                echo "[INFO] Posting $url from $host"
                echo $uri >> "/data/$today.uris.txt"
                last_line_imported=$now
            else
                url=`echo $line | jq .url| sed 's/\"//g'`
                echo "[DEBUG] Skipping $url from $host"
            fi
        done
    # In archive mode
    else

        if [[ ! -d "/data/$today/" ]]
        then
            mkdir -p "/data/$today/"
        fi

        curl -X "GET" "$url" --no-progress-meter >> "/data/$today/$today.$host.json"
    fi

    # Basic exponential backoff
    ((++errors))
    sleepseconds=$((errors*errors))
    
    # Don't allow a back off for more than 5 minutes.
    # Because we expect this container to reset occasionally to kill hanging curl processes
    # a graceful exit will wait for all scripts to stop. So, it will take at least as long as $sleepseconds
    # to stop.
    if [[ $sleepseconds -gt 299 ]]
    then
        sleepseconds=300
    fi

    sleep $sleepseconds;
    
    echo "[WARN] Streaming abrubtly stopped for $host, streaming will pause for $sleepseconds seconds before retrying."

done

## Exit 0 by default
exit 0