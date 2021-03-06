#!/bin/bash

DEST='/opt/velas/vvcm'
cd $DEST

################################
#### CONVENIENCE FUNCTIONS #####
################################

#Courtesy of cardano guild tools
get_input_default() {
  printf "%s (default: %s): " "$1" "$2" >&2; read -r answer
  if [ -z "$answer" ]; then echo "$2"; else echo "$answer"; fi
}

#Courtesy of cardano guild tools
get_answer() {
  printf "%s (y/n): " "$*" >&2; read -n1 -r answer
  while : 
  do
    case $answer in
    [Yy]*)
      return 0;;
    [Nn]*)
      return 1;;
    *) echo; printf "%s" "Please enter 'y' or 'n' to continue: " >&2; read -n1 -r answer
    esac
  done
}

generate_data(){
cat << EOF
{
"chain": "vlx",
"name": "$NAME",
"address": "$NODE_IDENTITY",
"telegram_username": "$TELEGRAM_USER",
"email_username": "$EMAIL_USER",
"monitor": {
  "process": "$MONITOR_PROCESS",
  "cpu": "$MONITOR_CPU",
  "nvme_heat": "$MONITOR_NVME_HEAT",
  "nvme_lifespan": "$MONITOR_NVME_LIFESPAN",
  "nvme_selftest": "$MONITOR_NVME_SELFTEST",
  "drive_space": "$MONITOR_DRIVE_SPACE",
  "delinquent_status": "$MONITOR_DELINQUENT_STATUS",
  "oom_condition": "$MONITOR_OOM_CONDITION"
  }
}
EOF
}

write_env() {
  echo -ne "
##### VVCM user variables #####
### Uncomment the next line to set your own peak_load_avg value or leave it undefined to use the VVCM default
#peak_load_avg=

##### END VVCM user variables #####

#### DO NOT EDIT BELOW THIS LINE! #####
#### TO EDIT THESE VARIABLES, RUN update_monitor.sh ####
#### DO NOT COPY THIS FILE or edit the API KEY ####
API_KEY=$API_KEY
NAME='$NAME'
MONITOR_DELINQUENT_STATUS=$MONITOR_DELINQUENT_STATUS
MONITOR_PROCESS=$MONITOR_PROCESS
MONITOR_CPU=$MONITOR_CPU
MONITOR_OOM_CONDITION=$MONITOR_OOM_CONDITION
MONITOR_DRIVE_SPACE=$MONITOR_DRIVE_SPACE
MONITOR_NVME_HEAT=$MONITOR_NVME_HEAT
MONITOR_NVME_LIFESPAN=$MONITOR_NVME_LIFESPAN
MONITOR_NVME_SELFTEST=$MONITOR_NVME_SELFTEST
EMAIL_USER=$EMAIL_USER
TELEGRAM_USER=$TELEGRAM_USER
NODE_IDENTITY=$NODE_IDENTITY
ACTIVE=$ACTIVE
" | sudo dd of=$DEST/env status=none
}

####################################
#### END CONVENIENCE FUNCTIONS #####
####################################

echo; echo

cat << "EOF"


 __     __   _            __     __    _ _     _       _                                                     
 \ \   / /__| | __ _ ___  \ \   / /_ _| (_) __| | __ _| |_ ___  _ __                                         
  \ \ / / _ \ |/ _` / __|  \ \ / / _` | | |/ _` |/ _` | __/ _ \| '__|                                        
   \ V /  __/ | (_| \__ \   \ V / (_| | | | (_| | (_| | || (_) | |                                           
    \_/ \___|_|\__,_|___/    \_/ \__,_|_|_|\__,_|\__,_|\__\___/|_|                                           
    ____                                      _ _           __  __             _ _             _             
   / ___|___  _ __ ___  _ __ ___  _   _ _ __ (_) |_ _   _  |  \/  | ___  _ __ (_) |_ ___  _ __(_)_ __   __ _ 
  | |   / _ \| '_ ` _ \| '_ ` _ \| | | | '_ \| | __| | | | | |\/| |/ _ \| '_ \| | __/ _ \| '__| | '_ \ / _` |
  | |__| (_) | | | | | | | | | | | |_| | | | | | |_| |_| | | |  | | (_) | | | | | || (_) | |  | | | | | (_| |
   \____\___/|_| |_| |_|_| |_| |_|\__,_|_| |_|_|\__|\__, | |_|  |_|\___/|_| |_|_|\__\___/|_|  |_|_| |_|\__, |
                                                    |___/                                              |___/ 

EOF
echo; echo;

if [ ! -f $DEST/env ]
then
    echo "Cannot find VVCM config file, please install VVCM"
    exit; exit
fi

source $DEST/env

#### Make sure server and local monitoring status is synced ###
if sudo systemctl is-active vvcm.timer | grep -qi ^active
then
  TIMER_ACTIVE=true
else
  TIMER_ACTIVE=false
fi
if ! [[ $ACTIVE =~ $TIMER_ACTIVE ]]
then
  echo "#####################"
  if [[ $TIMER_ACTIVE =~ "true" ]]
  then
    echo "WARNING: vvcm.timer is active but monitoring is paused on our server"
    echo "If you want to resume monitoring, continue and enter y on the next prompt"
    echo "If you want to disable monitoring completely, run sudo systemctl stop vvcm.timer"
  else
    echo "WARNING: vvcm.timer is inactive but monitoring is active on our server"
    echo "If you want to resume monitoring, run sudo systemctl start vvcm.timer"
    echo "If you want to disable monitoring completely, continue and enter y on the next prompt"
  fi
  echo "#####################"
  echo; echo
fi

#### Give the option to pause or resume monitoring
if [[ $ACTIVE =~ "true" ]]
then
  if get_answer "Monitoring is active, do you want to pause monitoring? "
  then
    echo
    RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d '{"active": "false"}' https://monitor.truestaking.com/update)"
    if [[ $RESP =~ "OK" ]]
      then
      ACTIVE=false
      echo "Alerts from our server have been paused"
        if sudo systemctl stop vvcm.timer
          then echo "vvcm.timer has been paused"
          else echo "failed to stop vvcm.timer. Possibly it is not installed, or it was already stopped/disabled." 
        fi
    else
      echo "Server side error: $RESP"
      exit; exit
    fi
    write_env
  fi
else
  if get_answer "Monitoring is inactive, do you want to resume monitoring? "
  then
    echo
    RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d '{"active": "true"}' https://monitor.truestaking.com/update)"
    if [[ $RESP =~ "OK" ]]
      then
      ACTIVE=true
      sudo systemctl start vvcm.timer
      echo "Monitoring has been resumed"
    else
      echo "Server side error: $RESP"
      exit; exit
    fi
    write_env
  fi
fi
echo; echo

if ! get_answer "Do you wish to make any other adjustments to your monitoring?"; then echo; exit; fi
echo; echo

##########################
#### SET ENV VARIABLES ####
##########################

#### Set active to be true by default in the setup.sh ####
ACTIVE=true
if get_answer "The current name is $NAME do you want to set a different name for this server account? "
then
  echo
  NAME=$(get_input_default "Please enter the name for this service account" $NAME)
else echo
fi
echo

#### is the validator is delinquent? ####
if get_answer "Do you want to be alerted if your node is delinquent? "
    then MONITOR_DELINQUENT_STATUS=true
    echo
        a=$(curl --connect-timeout 1 http://localhost:18899 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1, "method":"getIdentity"}' | cut -f 4 -d ":" | cut -f 1 -d "}" | sed 's/\"//g')
        if [[ $a =~ [a-z] ]]
        then NODE_IDENITY=$a
        else
                echo "failed to obtain NODE_IDENTITY via RPC to localhost"
                echo;echo
    		NODE_IDENTITY=$(get_input "Please enter your node identity (can be found on your profile page on velasvalidators.com). Paste and press <ENTER> ")
    	fi
	else MONITOR_DELINQUENT_STATUS=false
    echo
fi
echo

#### is the validator process still running? ####
if get_answer "Do you want to be alerted if your validator service stops running?"
    then 
	echo
        service=$(get_input_default "Please enter the service name you want to monitor? This is usually 'velas' " $MONITOR_PROCESS)
        if (sudo systemctl -q is-active $service)
            then MONITOR_PROCESS=$service
            else
                MONITOR_PROCESS=false
                echo "\"systemctl is-active $service\" failed, please check service name and rerun setup."
                exit;exit
        fi
    else MONITOR_PROCESS=false
    echo
fi
echo

#### is there an out of memory error condition ####
if get_answer "Do you want to check for an out of memory error condition"
then MONITOR_OOM_CONDITION=true
else MONITOR_OOM_CONDITION=false
fi
echo; echo

#### is my CPU going nuts? ####
if get_answer "Do you want to be alerted if your CPU load average is high?"
    then MONITOR_CPU=true
        if ! sudo apt list --installed 2>/dev/null | grep -qi util-linux
            then sudo apt install util-linux
        fi
        if ! sudo apt list --installed 2>/dev/null | grep -qi ^bc\/
            then sudo apt install bc
        fi
    else MONITOR_CPU=false
fi
echo; echo

#### are the NVME drives running hot? ####
if get_answer "Do you want to be alerted for NVME drive high temperatures? "
    then MONITOR_NVME_HEAT=true
    else MONITOR_NVME_HEAT=false
fi
echo; echo

#### are the NVME drives approaching end of life? ####
if get_answer "Do you want to be alerted when NVME drives reach 80% anticipated lifespan?"
    then MONITOR_NVME_LIFESPAN=true
    else MONITOR_NVME_LIFESPAN=false
fi
echo; echo

#### are the NVME drives failing the selftest? ####
if get_answer "Do you want to be alerted when an NVME drives fails the self-assessment check? "
    then MONITOR_NVME_SELFTEST=true
    else MONITOR_NVME_SELFTEST=false
fi
echo; echo

#### are any of the disks at 90%+ capacity? ####
if get_answer "Do you want to be alerted when any drive reaches 90% capacity?"
    then MONITOR_DRIVE_SPACE=true
    else MONITOR_DRIVE_SPACE=false
fi
echo; echo

#### do we need to install NVME utilities? ####
if echo $MONITOR_NVME_HEAT,$MONITOR_NVME_LIFESPAN,$MONITOR_NVME_SELFTEST | grep -qi true
    then
        echo "checking for NVME utilities..."
        if ! sudo apt list --installed 2>/dev/null | grep -qi nvme-cli
            then
                echo "installing nvme-cli.."
                if ! sudo apt install nvme-cli
                then echo;
                    echo "VVCM setup failed to install nvme-cli. Please manually install nvme-cli and rerun setup."
                echo; echo
                fi
        fi
        if ! sudo apt list --installed 2>/dev/null | grep -qi smartmontools
            then
                echo "installing smartmontools..."
                if ! sudo apt install smartmontools
                then echo
                    echo "VVCM setup failed to install smartmontools. Please manually install nvme-cli and rerun setup."
                    echo; echo
                fi
        fi
	echo;
fi

#### alert via email? ####
if get_answer "Do you want to receive validator alerts via email?" 
    then echo;
    EMAIL_USER=$(get_input_default "Please enter an email address for receiving alerts " $EMAIL_USER)
    else EMAIL_USER=''
fi
echo

#### alert via TG ####
if get_answer "Do you want to receive validator alerts via Telegram?"
    then echo;
    TELEGRAM_USER=$(get_input_default "Please enter your telegram username " $TELEGRAM_USER)
    echo "IMPORTANT: Please enter a telegram chat with our bot LINK: https://t.me/velasvvcm_bot"
    echo "IMPORTANT: If you are already in a telegram chat with our bot you do not have to create a new one. Press <enter>"
    read -p "After you join a chat with our bot, return here and press <enter>."; echo
    else TELEGRAM_USER=''
fi
if ( echo $TELEGRAM_USER | grep -qi [A-Za-z0-9] )
    then echo -n "Please do not exit the chat with our telegram bot. If you do, you will not be able to receive alerts about your system. If you leave the chat please run update_monitor.sh"; echo ;
fi

#### check that there is at least one valid alerting mechanism ####
if ! ( [[ $EMAIL_USER =~ [\@] ]] || [[ $TELEGRAM_USER =~ [a-zA-Z0-9] ]] )
then
  logger "VVCM requires either email or telegram for alerting, bailing out of setup."
  echo "VVCM requires either email or telegram for alerting. Rerun setup to provide email or telegram alerting. Bailing out."
  exit
fi

###############################
#### END SET ENV VARIABLES ####
###############################

##### update truestaking alert server #####
RESP="$('/usr/bin/curl' -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer '$API_KEY'' -d "$(generate_data)" https://monitor.truestaking.com/update)"
if ! [[ $RESP =~ "OK" ]]
then 
    echo "We encountered an error: $RESP "
    exit
else echo "success!"
fi
echo

write_env

if [[ $ACTIVE =~ "false" ]]
then
  echo
  echo "#############################"
  echo "Warning alerts are currently paused, to resume alerts run update_monitor.sh"
  echo "#############################"
fi
