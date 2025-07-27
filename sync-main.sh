#!/bin/bash

# Notes:
# - Remote backup dir: for normal sync-to operation
# - Check backup dir creation and contents
# - keep a maximum of $BKP_KEEP backup sync folders like mac55-bin.20230615_183951

if [ "$1" = '' ]; then 
  exit 0
fi

# Check if we do it the other way around and sync back from the server
BACKPORT=0
if [ $# -eq 2 ] && [ "$2" = '-backport' ] ; then
  BACKPORT=1
fi

# Init main variables
BIN=$(dirname $0)
NAME="$1"
CONF_DIR="sync/"
CONF_TMP="/tmp/"
CONF="$BIN/$CONF_DIR$1.conf"
BKP_KEEP=12
# echo "$CONF"

if [ ! -f "$CONF" ]; then
  exit 0
fi

# Get config file and split it up into configuration and excludes
PID=$$
USE_CONF="$CONF_TMP""$1.$PID.conf"
USE_EXCL="$CONF_TMP""$1.$PID.exclude"
# echo pid: $PID

# Define a function that removes temporary config files
cleanup () {
  # ls "$BIN/$CONF_DIR""$NAME."[0-9]*".conf"
  # rm "$BIN/$CONF_DIR""$NAME."[0-9]*".conf" 2>/dev/null
  # rm "$BIN/$CONF_DIR""$NAME."[0-9]*".exclude" 2>/dev/null
  rm "$USE_CONF" 2>/dev/null
  rm "$USE_EXCL" 2>/dev/null
  if [ "$CONF_TMP" != "/tmp/" ]; then
      find "$CONF_TMP" -mtime +5 -name "*.*[0-9]*.[ec]*" -exec rm {} \;
  fi
}

echo ---------- config files -----------
echo "$USE_CONF"
echo "$USE_EXCL"

EXCL_LINE_A=$(grep -n SYNC_EXCLUDE "$CONF" | cut -d : -f 1)
EXCL_LINE_B=""
CONF_DEF=""
EXCL_DEF=""
EXCL_EXIST=1
if [ ! -z "$EXCL_LINE_A" ] && [ "$EXCL_LINE_A" -gt 2 ]; then
  CONF_LINE=$((EXCL_LINE_A-1))
  if [ ! -z "$CONF_LINE" ] && [ "$CONF_LINE" -gt 0 ]; then
    CONF_DEF=$(head -n "$CONF_LINE" "$CONF")
  fi
  EXCL_LINE_A=$((EXCL_LINE_A+1))
  EXCL_SEARCH=$(tail -n +"$EXCL_LINE_A" "$CONF")
  EXCL_FIRST=$(tail -n +"$EXCL_LINE_A" "$CONF" | head -1)
  if [ "$EXCL_FIRST" == ")" ]; then
      EXCL_EXIST=""
  fi
  # echo "$EXCL_EXIST"
  # echo "$EXCL_SEARCH"
  EXCL_LINE_B=$(echo "$EXCL_SEARCH" | grep -n -x ')' | head -1 | cut -d : -f 1)
  # echo $EXCL_LINE_B
  if [ ! -z "$EXCL_LINE_B" ] && [ "$EXCL_LINE_B" -ge 2 ]; then
    EXCL_LINE_B=$((EXCL_LINE_B-1))
    EXCL_PART=$(echo "$EXCL_SEARCH" | head -n +"$EXCL_LINE_B")
    EXCL_DEF=$(echo "$EXCL_PART" | sed 's/^[[:space:]]*//;')
  else 
    EXCL_LINE_B=""
  fi
fi

if [ ! -z "$EXCL_EXIST" ]; then
  if [ -z "$CONF_DEF" ] || [ -z "$EXCL_LINE_B" ]; then
    echo "Cannot process configuration file in $CONF_DIR$1.conf"
    exit
  fi
fi

# Cleanup, then write new config files
cleanup
echo "$CONF_DEF" > "$USE_CONF"
if [ ! -z "$EXCL_EXIST" ]; then
  echo "$EXCL_DEF" > "$USE_EXCL"
else
  touch "$USE_EXCL"
fi
if [ ! -f "$USE_CONF" ] || [ ! -f "$USE_EXCL" ]; then
  echo "Cannot write process config or exclude file in $CONF_TMP"
  exit
fi

echo ---------- configuration ----------
echo "$CONF_DEF"
echo ------------- exclude -------------
echo "$EXCL_DEF"

# Function to remove our temporary config files and exit
exit_clean () { 
  cleanup
  exit
}
# exit_clean

# Now, use the actual configuration
source "$USE_CONF"

# echo "$SYNC_USER"@"$SYNC_SERVER"

# Make sure directories have trailing slashes and define backup subfolder
if [ -f "$SYNC_LOCAL" ] && [ ! -d "$SYNC_LOCAL" ]; then
  SYNC_LOCAL=$(echo $SYNC_LOCAL | sed  s,/$,,g)
  SYNC_REMOTE=$(echo $SYNC_REMOTE | sed  s,/$,,g)
else
  SYNC_LOCAL=$(echo $SYNC_LOCAL | sed  s,/$,,g)/
  SYNC_REMOTE=$(echo $SYNC_REMOTE | sed  s,/$,,g)/
fi

TS=$(date +%Y%m%d_%H%M%S)
if [ ! -z "$SYNC_BKP_LOCAL" ]; then
    SYNC_BKP_LOCAL=$(echo $SYNC_BKP_LOCAL | sed  s,/$,,g)/
    # SYNC_BKP_LOCAL="$SYNC_BKP_LOCAL""$TS"_"$NAME"
    SYNC_BKP_LOCAL="$SYNC_BKP_LOCAL""$NAME."$TS
fi
if [ ! -z "$SYNC_BKP_REMOTE" ]; then
    SYNC_BKP_REMOTE=$(echo $SYNC_BKP_REMOTE | sed  s,/$,,g)/
    # SYNC_BKP_REMOTE="$SYNC_BKP_REMOTE""$TS"_"$NAME"
    SYNC_BKP_REMOTE="$SYNC_BKP_REMOTE""$NAME."$TS.pushed
fi

TEMP_DIR=""
if [ ! -z "$SYNC_TMP_DIR" ]; then
    TEMP_DIR="--temp-dir=$SYNC_TMP_DIR"
fi

# Function to remove old backups (which exceed $BKP_KEEP)
tidy_up_local_backups() {
  BKP_PARENT="$(dirname "$SYNC_BKP_LOCAL")"
  N=0
  # ls -1t "$BKP_PARENT/""$NAME.2[0-9]*" | while read f; do 
  FOUND=$(find "$BKP_PARENT/" -type d -name "$NAME."2[0-9]* 2>/dev/null)
  if [ ! -z "$FOUND" ]; then
      ls -1td "$BKP_PARENT/""$NAME."2[0-9]* 2>/dev/null | while read f; do 
      N=$((N+1))
      # if [ "$N" -gt "$BKP_KEEP" ] && [ "${f##*/}" != "$SKIP" ] && [ "${f##*/}" != "$SKIP_OWN" ]; then
      if [ "$N" -gt "$BKP_KEEP" ] && [ "$N" -gt 1 ]; then
        echo $N: rm -rf "$f"
        rm -rf "$f"
      fi;
    done
  fi
}

echo -------------- backup folders --------------
echo "$SYNC_BKP_LOCAL"
echo "$SYNC_BKP_REMOTE"
echo "$SYNC_LOCAL"
echo "$SYNC_REMOTE"


SYNC_INFO="$SYNC_USER@$SYNC_SERVER:"
if [ -z "$SYNC_SERVER" ]; then
    SYNC_INFO=""
fi
# echo "$DEPLOY_SERVER"

echo ... "$SYNC_REMOTE"

# Optional: find local git repos and print branch info
echo_git() {
    if [ "$SYNC_GIT_CHECK" == "" ] || [ "$SYNC_GIT_CHECK" -eq 0 ]; then
        # echo "Skipping git check..."
        return;
    fi
    cwd=$(pwd)
    find $1 -type d -name "*.git" -print0 | xargs -0 -n 1 echo | sed  s,\/\.git$,,g | while read dir; do
        dirname=$(basename "$dir")
         echo "$dirname"
        cd "$dir"
        # git status | head -1 | sed s,"On branch ",,g
        git_branch=$(git status 2>/dev/null | head -1 | sed s,"On branch ",,g)
        echo "Git: on $git_branch ($dirname)"
    done
    cd $cwd
}


if [ "$BACKPORT" -eq 0 ]; then

  # Normal mode of operation: deploy and sync to server
  echo "-------------------------------------------------------"
  echo "rsync to $SYNC_SERVER"
  echo "Source: $SYNC_LOCAL"
  echo_git "$SYNC_LOCAL"
  echo "Target: $SYNC_INFO$SYNC_REMOTE"
  echo "Exclude file: $USE_EXCL"
  echo "Config file:  $USE_CONF"
  echo "Start rsync --dry-run (y/n)?" 

  read -n1 -p "" RYN 
  if [ ! -z "$RYN" ]; then echo; fi

  # Offer a 'dry run' before the actual sync run
  if [ "$RYN" = "y" ]; then
    echo "Starting rsync --dry-run..."

    if [ -z "$SYNC_SERVER" ]; then
      if [ -z "$SYNC_BKP_REMOTE" ]; then
        RSY=$(rsync --dry-run -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            "$SYNC_LOCAL" "$SYNC_REMOTE")
      else
        RSY=$(rsync --dry-run -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            -b --backup-dir="$SYNC_BKP_REMOTE" \
            "$SYNC_LOCAL" "$SYNC_REMOTE")
      fi
      
    else    
      if [ -z "$SYNC_BKP_REMOTE" ]; then
        RSY=$(rsync -e ssh --dry-run -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            "$SYNC_LOCAL" "$SYNC_USER"@"$SYNC_SERVER":"'$SYNC_REMOTE'")
      else
        RSY=$(rsync -e ssh --dry-run -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            -b --backup-dir="$SYNC_BKP_REMOTE" \
            "$SYNC_LOCAL" "$SYNC_USER"@"$SYNC_SERVER":"'$SYNC_REMOTE'")
      fi
    fi

    RSY_L=$(echo "$RSY" | wc -l)
    if [ $RSY_L -gt 500 ]; then
        echo -e "rsync --dry-run...\n$RSY" | less
    else
        echo "$RSY"
    fi
    echo 
    echo "Please check if the dry run looks all right."
  else
    echo "Skipping rsync --dry-run"
  fi

  # Actual sync run
  echo "-------------------------------------------------------"
  echo "Start rsync (y/n)?"

  read -n1 -p "" RYN 
  if [ ! -z "$RYN" ]; then echo; fi

  if [ "$RYN" = "y" ]; then
    echo "Starting rsync..."

    if [ -z "$SYNC_SERVER" ]; then
      if [ -z "$SYNC_BKP_REMOTE" ]; then
        rsync -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            "$SYNC_LOCAL" "$SYNC_REMOTE"
      else
        rsync -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            -b --backup-dir="$SYNC_BKP_REMOTE" \
            "$SYNC_LOCAL" "$SYNC_REMOTE"
      fi
      
    else    
      if [ -z "$SYNC_BKP_REMOTE" ]; then
        rsync -e ssh -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            "$SYNC_LOCAL" "$SYNC_USER"@"$SYNC_SERVER":"'$SYNC_REMOTE'"
      else
        rsync -e ssh -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            -b --backup-dir="$SYNC_BKP_REMOTE" \
            "$SYNC_LOCAL" "$SYNC_USER"@"$SYNC_SERVER":"'$SYNC_REMOTE'"
      fi
    fi

  else
    echo "Skipping rsync"
  fi

else 

  # Backport mode of operation: copy back from remote server
  FROM_DIR="$SYNC_REMOTE"
  TO_DIR="$SYNC_LOCAL"
  
  echo "-------------------------------------------------------"
  echo "Back sync from $SYNC_SERVER"
  echo "Source: $SYNC_INFO$FROM_DIR"
  echo "Target: $TO_DIR"
  echo "Exclude file: $USE_EXCL"
  echo "Config file:  $USE_CONF"
  echo "Local backup dir: $SYNC_BKP_LOCAL"
  echo "Note: Make sure that you have a local backup and your repo is on the right branch"
  echo 
  echo "Start backport --dry-run (y/n)?" 
  
  # echo rsync -e ssh --dry-run -v -r -l -t -O -i -D   --delete --exclude-from=$EXCLUDE  -b --backup-dir=$LOCAL_BACKPORT_BACKUP  $DEPLOY_ACCOUNT@$DEPLOY_SERVER:$FROM_DIR $TO_DIR

  read -n1 -p "" RYN 
  if [ ! -z "$RYN" ]; then echo; fi

  if [ "$RYN" = "y" ]; then
    echo "Starting backport --dry-run..."

    if [ -z "$SYNC_SERVER" ]; then
      if [ -z "$SYNC_BKP_LOCAL" ]; then
        RSY=$(rsync --dry-run -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            "$FROM_DIR" "$TO_DIR")
      else
        RSY=$(rsync --dry-run -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            -b --backup-dir="$SYNC_BKP_LOCAL" \
            "$FROM_DIR" "$TO_DIR")
      fi
    
    elif [ "$DEPLOY_KEY" == "" ]; then
      if [ -z "$SYNC_BKP_LOCAL" ]; then
        RSY=$(rsync -e ssh --dry-run -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            "$SYNC_USER"@"$SYNC_SERVER":"'$FROM_DIR'" "$TO_DIR")
      else
        RSY=$(rsync -e ssh --dry-run -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            -b --backup-dir="$SYNC_BKP_LOCAL" \
            "$SYNC_USER"@"$SYNC_SERVER":"'$FROM_DIR'" "$TO_DIR")
      fi
    fi

    RSY_L=$(echo "$RSY" | wc -l)
    if [ $RSY_L -gt 500 ]; then
        echo -e "back sync --dry-run...\n$RSY" | less
    else
        echo "$RSY"
    fi
    echo "Does the dry run for the back sync look okay?"
  else
    echo "Skipping --dry-run"
  fi
  
  echo "-------------------------------------------------------"
  echo "Start BACK SYNC (y/n)?"

  read -n1 -p "" RYN 
  if [ ! -z "$RYN" ]; then echo; fi

  if [ "$RYN" = "y" ]; then
    echo "Starting BACK SYNC..."
    
    if [ ! -z "$SYNC_BKP_LOCAL" ] && [ ! -d "$SYNC_BKP_LOCAL" ]; then
        BKP_PARENT="$(dirname "$SYNC_BKP_LOCAL")"
        if [ -d "$BKP_PARENT" ]; then
          mkdir "$SYNC_BKP_LOCAL"
        fi
        if [ ! -d "$SYNC_BKP_LOCAL" ]; then
          echo "Local folder for backport backups does not exist [$SYNC_BKP_LOCAL]. Cannot proceed..."
          exit_clean;
        fi
    fi

    if [ -z "$SYNC_SERVER" ]; then
      if [ -z "$SYNC_BKP_LOCAL" ]; then
        rsync -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            "$FROM_DIR" "$TO_DIR"
      else
        tidy_up_local_backups
        rsync -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            -b --backup-dir="$SYNC_BKP_LOCAL" \
            "$FROM_DIR" "$TO_DIR"
      fi
    
    elif [ "$DEPLOY_KEY" == "" ]; then
      if [ -z "$SYNC_BKP_LOCAL" ]; then
        rsync -e ssh -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            "$SYNC_USER"@"$SYNC_SERVER":"'$FROM_DIR'" "$TO_DIR"
      else
        tidy_up_local_backups
        rsync -e ssh -v -r -l -t -O -i -D  $TEMP_DIR  --delete --exclude-from="$USE_EXCL" \
            -b --backup-dir="$SYNC_BKP_LOCAL" \
            "$SYNC_USER"@"$SYNC_SERVER":"'$FROM_DIR'" "$TO_DIR"
      fi
    fi

  else
    echo "Skipping back sync"
  fi

fi

exit_clean;
