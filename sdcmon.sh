#!/bin/bash

# fetched
# don't run multiple times
if pidof -x $0 -o $$; then
    echo "Already running. Exiting."
    exit 1
fi

function CheckMode {
    if [ "$MODE"  != "$PRODUCTIVE_MODE" -a "$MODE" != "$REMOTE_MAINTENANCE_MODE" -a "$MODE" != "$MAINTENANCE_MODE" -a "$MODE" != "$SERVERDOWN_MODE" -a "$MODE" != "" ]; then
        echo "Unsupported mode $MODE."
        echo "Usage: $0 [$PRODUCTIVE_MODE | $MAINTENANCE_MODE | $REMOTE_MAINTENANCE_MODE |  $SERVERDOWN_MODE]"
        exit 1
    fi
}

### begin functions ###
function GetStatus {
    case $SYSTYPE in
    HANA)
        local SID=$i
        local INSTNUM
        local SIDADM
        local COUNT
        local HDBVERSION
        local HANAPYTHONRESULT
        SIDADM=$(echo $SID | tr '[:upper:]' '[:lower:]')
        SIDADM=${SIDADM}adm
        INSTNUM=$(ls -1 /usr/sap/${SID}/SYS/profile/${SID}_HDB*_* | awk -F '/' '{print $NF}' | awk -F '_' '{print $2}' | tr -d '/HDB/' | head -1)
        test -f $HDBSTAT && rm -f $HDBSTAT
        HANAPYTHONRESULT=$(su - $SIDADM -c "python /usr/sap/$SID/SYS/exe/hdb/python_support/landscapeHostConfiguration.py | grep overall | cut -d: -f2 | awk '{print $1}'| sed 's/^[ \t]*//' ")
        HDBVERSION=$(su - $SIDADM -c " HDB version | grep version: |  sed 's/[^.-9]*//g' 2>&1")
        echo "DB-Type: HANA $HDBVERSION" > $HDBSTAT
        su - $SIDADM -c "sapcontrol -nr $INSTNUM -function GetProcessList 2>&1" >> $HDBSTAT

        if [ "$HANAPYTHONRESULT" == "ok" ]; then
            STATUS=$STATUS_OKAY
            rm -f $CLDSCRIPTS/.${SID}_* > /dev/null 2>&1
        elif [ "$HANAPYTHONRESULT" == "warning" ]; then
            unset COUNT
            COUNT=$(grep -i "Indexserver"  $HDBSTAT | grep "GREEN" | wc -l)
            test -z $COUNT && COUNT=0
            if [ "$COUNT" -lt "1" ]; then
                STATUS=$STATUS_NOT_OKAY
            else
                STATUS=$STATUS_OKAY
                HANAWARNING="but shows WARNING"
                rm -f $CLDSCRIPTS/.${SID}_* > /dev/null 2>&1
            fi
        fi
    ;;
    SAPMZ)
        local STAT256=""
        local RUNNINGSTAT="is running"
        test -f $MZSTAT && rm -f $MZSTAT
        STAT256=$(su - mzadmin -c "mzsh mzadmin/dr status")
        echo $STAT256
        if [[ "$STAT256" == *${RUNNINGSTAT}* ]]; then
            echo "SAPMZ Platform EC1 is running." > $MZSTAT
            STATUS=$STATUS_OKAY
            rm -f $CLDSCRIPTS/.${SID}_* > /dev/null 2>&1
        else
            STATUS=$STATUS_NOT_OKAY
        fi
    ;;
    SMP)
        local SID=$i
        local SIDADM=sybase
        local SMPPAGE
        test -f $SMPSTAT && rm -f $SMPSTAT
        unset SMPPAGE
        unset https_proxy
        SMPPAGE=$(curl -ko /dev/null --silent --head --write-out '%{http_code}\n' https://${HOSTNAME}:8084/Admin)
        if [ "$SMPPAGE" == "302" ]; then
            echo "The SMP server has initialized and is ready." > $SMPSTAT
            STATUS=$STATUS_OKAY
            rm -f $CLDSCRIPTS/.${SID}_* > /dev/null 2>&1
        else
            STATUS=$STATUS_NOT_OKAY
        fi
    ;; 
    ABAP)
        local SID=$i
        local INSTNUM
        local SIDADM
        local COUNT
        SIDADM=$(echo $SID | tr '[:upper:]' '[:lower:]')
        SIDADM=${SIDADM}adm
        INSTNUM=$(grep -w SAPSYSTEM /usr/sap/${SID}/SYS/profile/${SID}*DVEB* | awk -F '=' '{print $2}' | tr -d '[:blank:]' | head -1)
        #for newer versions of NW, profiles SID_DVEB* is now SID_D*
        if [ -z "$INSTNUM" ]; then
            INSTNUM=$(grep -w SAPSYSTEM /usr/sap/${SID}/SYS/profile/${SID}*D* | awk -F '=' '{print $2}' | tr -d '[:blank:]' | head -1)
        fi   
        test -f $ABAPSTAT && rm -f $ABAPSTAT 
        echo "ABAP SYSTEM Monitoring" > $ABAPSTAT
        su - $SIDADM -c "sapcontrol -nr $INSTNUM -function GetProcessList" >> $ABAPSTAT
        unset COUNT
        COUNT=$(grep -i "RED"  $ABAPSTAT | wc -l)
        test -z $COUNT && COUNT=0
        if [ "$COUNT" -gt "0" ]; then
            STATUS=$STATUS_NOT_OKAY
        else
            unset COUNT
            COUNT=$(grep -i "YELLOW"  $ABAPSTAT | wc -l)
            test -z $COUNT && COUNT=0
            if [ "$COUNT" -gt "0" ]; then
                STATUS=$STATUS_NOT_OKAY
            else
                unset COUNT
                COUNT=$(grep -i "GRAY"  $ABAPSTAT | wc -l)
                test -z $COUNT && COUNT=0
                if [ "$COUNT" -gt "0" ]; then
                    STATUS=$STATUS_NOT_OKAY
                else
                    unset COUNT
                    COUNT=$(grep -i "disp+work"  $ABAPSTAT | grep "GREEN" | wc -l)
                    test -z $COUNT && COUNT=0
                    if [ "$COUNT" -lt "1" ]; then
                        STATUS=$STATUS_NOT_OKAY
                    else
                        STATUS=$STATUS_OKAY
                        rm -f $CLDSCRIPTS/.${SID}_* > /dev/null 2>&1
                    fi
                fi			  
            fi
        fi
    ;;
    J2EE)
        local SID=$i
        local INSTNUM
        local SIDADM
        local COUNT
        SIDADM=$(echo $SID | tr '[:upper:]' '[:lower:]')
        SIDADM=${SIDADM}adm
        INSTNUM=$(grep -w SAPSYSTEM /usr/sap/${SID}/SYS/profile/${SID}*J* | awk -F '=' '{print $2}' | tr -d '[:blank:]' | head -1)
        #for newer versions of NW, profiles SID_JXX if older SID_JCXX
        if [ -z "$INSTNUM" ]; then
            INSTNUM=$(grep -w SAPSYSTEM /usr/sap/${SID}/SYS/profile/${SID}*JC* | awk -F '=' '{print $2}' | tr -d '[:blank:]' | head -1)
        fi
        test -f $J2EESTAT && rm -f $J2EESTAT
        echo "J2EE SYSTEM Monitoring" > $J2EESTAT
        su - $SIDADM -c "sapcontrol -nr $INSTNUM -function GetProcessList" >> $J2EESTAT
        unset COUNT
        COUNT=$(grep -i "RED"  $J2EESTAT | wc -l)
        test -z $COUNT && COUNT=0
        if [ "$COUNT" -gt "0" ]; then
            STATUS=$STATUS_NOT_OKAY
        else
            unset COUNT
            COUNT=$(grep -i "YELLOW"  $J2EESTAT | wc -l)
            test -z $COUNT && COUNT=0
            if [ "$COUNT" -gt "0" ]; then
                STATUS=$STATUS_NOT_OKAY
            else
                unset COUNT
                COUNT=$(grep -i "GRAY"  $J2EESTAT | wc -l)
                test -z $COUNT && COUNT=0
                if [ "$COUNT" -gt "0" ]; then
                    STATUS=$STATUS_NOT_OKAY
                else
                    unset COUNT
                    COUNT=$(grep -i "jstart"  $J2EESTAT | grep "GREEN" | wc -l)
                    test -z $COUNT && COUNT=0
                    if [ "$COUNT" -lt "1" ]; then
                        STATUS=$STATUS_NOT_OKAY
                    else
                        STATUS=$STATUS_OKAY
                        rm -f $CLDSCRIPTS/.${SID}_* > /dev/null 2>&1
                    fi
                fi
            fi
        fi
    ;;
    WEBDISPATCHER)
        local SID=$i
        local INSTNUM
        local SIDADM
        local COUNT
        SIDADM=$(echo $SID | tr '[:upper:]' '[:lower:]')
        SIDADM=${SIDADM}adm
        INSTNUM=$(grep -w SAPSYSTEM /usr/sap/${SID}/SYS/profile/${SID}*W* | awk -F '=' '{print $2}' | tr -d '[:blank:]' | head -1)
        test -f $WDSTAT && rm -f $WDSTAT
        su - $SIDADM -c "sapcontrol -nr $INSTNUM -function GetProcessList" > $WDSTAT
        unset COUNT
        COUNT=$(grep -i "RED"  $WDSTAT | wc -l)
        test -z $COUNT && COUNT=0
        if [ "$COUNT" -gt "0" ]; then
            STATUS=$STATUS_NOT_OKAY
        else
            unset COUNT
            COUNT=$(grep -i "YELLOW"  $WDSTAT | wc -l)
            test -z $COUNT && COUNT=0
            if [ "$COUNT" -gt "0" ]; then
                STATUS=$STATUS_NOT_OKAY
            else
                unset COUNT
                COUNT=$(grep -i "GRAY"  $WDSTAT | wc -l)
                test -z $COUNT && COUNT=0
                if [ "$COUNT" -gt "0" ]; then
                    STATUS=$STATUS_NOT_OKAY
                else
                    unset COUNT
                    COUNT=$(grep -i "sapwebdisp"  $WDSTAT | grep "GREEN" | wc -l)
                    test -z $COUNT && COUNT=0
                    if [ "$COUNT" -lt "1" ]; then
                        STATUS=$STATUS_NOT_OKAY
                    else
                        STATUS=$STATUS_OKAY
                        rm -f $CLDSCRIPTS/.${SID}_* > /dev/null 2>&1
                    fi
                fi 		   
            fi
        fi
    ;;
    *)
    # this is especially for SIDS=---
    STATUS=$STATUS_OKAY
    esac
}

function MountAndTransferCLD41 {
    local BASEOUT=$(basename $OUTFILE)
    local MONPATH="SDC_Monitoring"
    local SMBSHARE="//cldvmxwi00041/SDC_Monitoring"
    local SID=$i
    local TRANSLOG="$WORK/trans.log"
    local TLSIZE=$(stat -c%s $TRANSLOG)
    echo "$(date) : MountAndTransferCLD41" >> $TRANSLOG 2>&1
    if [ "$TLSIZE" -gt "1000000" ]; then
        mv -f $TRANSLOG ${TRANSLOG}.bak
    fi
    echo >> $TRANSLOG
    sleep $(( $(($RANDOM - 1)) % 8 ))
    /usr/bin/smbclient $SMBSHARE -N -A /root/.sdcmoncred2 -c \
    "del ${HOSTNAME}_${SID}_*.txt;
    put $OUTFILE ${HOSTNAME}_${SID}_${STATUS}.txt" >> $TRANSLOG 2>&1
    rc=$?
    if [ "$rc" -ne "0" ]; then
        echo "ERROR: Could not transfer $OUTFILE" | tee -a $TRANSLOG
        return
    else
        echo "Successfully transferred $OUTFILE"  | tee -a $TRANSLOG
    fi
}

function MountAndTransfer {
    local BASEOUT=$(basename $OUTFILE)
    local MONPATH="TDC_nonAbap\\SDC_Monitoring\\$SHOWROOMFOLDER"
    local SMBSHARE="//$MONSRV/sdc"
    local SID=$i
    local TRANSLOG="$WORK/trans.log"
    local TLSIZE=$(stat -c%s $TRANSLOG)
    echo "$(date) : MountAndTransfer" >> $TRANSLOG 2>&1
    if [ "$TLSIZE" -gt "1000000" ]; then
        mv -f $TRANSLOG ${TRANSLOG}.bak
    fi
    echo >> $TRANSLOG
    sleep $(( $(($RANDOM - 1)) % 8 ))
    /usr/bin/recode latin1..dos $OUTFILE
    /usr/bin/smbclient $SMBSHARE -N -A /root/.sdcmoncred -c \
    "del  $MONPATH\\${clusterName}${SHOWROOM}_${HOSTNAME}_${SID}_*.txt;
    put $OUTFILE $MONPATH\\$BASEOUT" >> $TRANSLOG 2>&1
    rc=$?
    if [ "$rc" -ne "0" ]; then
        echo "ERROR: Could not transfer $OUTFILE" | tee -a $TRANSLOG
        return
    else
        echo "Successfully transferred $OUTFILE"  | tee -a $TRANSLOG
    fi
}

function CheckForUpdate {
    local MONPATH="TDC_nonAbap\\SDC_startscript\\Linux"
    local SMBSHARE="//$MONSRV/sdc"
    local TESTFILE="update.yes"
    local SCRIPT=$SCRIPTNAME
    local DIR="$CLDSCRIPTS"
    local TRANSLOG="$WORK/trans.log"
    local rc
    local CURRDATE="$(date +"%d")_$(date +"%m")_$(date +"%y")_update.txt"
    local UPDATEOUT="$WORK/$CURRDATE"
    echo "$(date) : CheckForUpdate" >> $TRANSLOG 2>&1
    find  $WORK/*_update.txt -maxdepth 2 -type f -mtime +3 | xargs rm -rf 
    #update only at 1 o'clock
    if  [ $(date +"%H") = "01" ]; then
        #update only if today not already done
        if [ ! -f $UPDATEOUT ]
            then
            /usr/bin/smbclient $SMBSHARE -N -A /root/.sdcmoncred -c \
            "get  $MONPATH\\$TESTFILE $WORK/$TESTFILE" >> $TRANSLOG 2>&1
            rc=$?
            if [ "$rc" -eq "0" ]; then
                rm -f $WORK/$TESTFILE
                /usr/bin/smbclient $SMBSHARE -N -A /root/.sdcmoncred -c \
                "get  $MONPATH\\$SCRIPT $WORK/$SCRIPT.new" >> $TRANSLOG 2>&1
                rc=$?
                if [ "$rc" -eq "0" ]; then
                    mv -f $DIR/$SCRIPT $DIR/$SCRIPT.bak
                    chmod 750 $WORK/$SCRIPT.new
                    mv -f $WORK/$SCRIPT.new $DIR/$SCRIPT
                    echo "Updated $DIR/$SCRIPT" | tee -a $TRANSLOG
                    echo "$date" > $UPDATEOUT
                fi
            fi
        fi
    fi
}

function CheckForEmergencyUpdate {
    local MONPATH="TDC_nonAbap\\SDC_startscript\\Linux"
    local SMBSHARE="//$MONSRV/sdc"
    local TEST_EMERGENCY="update_emergency.yes"
    local TEST_UPDATE="update.yes"
    local SCRIPT=$SCRIPTNAME
    local DIR="$CLDSCRIPTS"
    local TRANSLOG="$WORK/trans.log"
    local rc
    echo "$(date) : CheckForEmergencyUpdate" >> $TRANSLOG 2>&1
    /usr/bin/smbclient $SMBSHARE -N -A /root/.sdcmoncred -c \
    "get  $MONPATH\\$TEST_EMERGENCY $WORK/$TEST_EMERGENCY" >> $TRANSLOG 2>&1
    rc=$?

    if [ "$rc" -eq "0" ]; then
        rm -f $WORK/$TEST_EMERGENCY
        /usr/bin/smbclient $SMBSHARE -N -A /root/.sdcmoncred -c \
        "get  $MONPATH\\$SCRIPT $WORK/$SCRIPT.new" >> $TRANSLOG 2>&1
        rc=$?
        if [ "$rc" -eq "0" ]; then
            mv -f $DIR/$SCRIPT $DIR/$SCRIPT.bak
            chmod 750 $WORK/$SCRIPT.new
            mv -f $WORK/$SCRIPT.new $DIR/$SCRIPT
            echo "Updated $DIR/$SCRIPT" | tee -a $TRANSLOG
        fi
    fi
}

function UpdateKeyFile { #update $SID /usr/sap/$SIDS/home/.ssh/authorized_keys
    local SID=$i
    local MONPATH="TDC_nonAbap\\SDC_startscript\\Linux"
    local SMBSHARE="//$MONSRV/sdc"
    local KEYFILE="authorized_keys"
    local KEYDIR="/usr/sap/$SID/home/.ssh"  
    local TRANSLOG="$WORK/trans.log"
    local rc
    local SIDADM
    SIDADM=$(echo $SID | tr '[:upper:]' '[:lower:]')
    SIDADM=${SIDADM}adm
    echo "$(date) : UpdateKeyFile" >> $TRANSLOG 2>&1
    if [ ! -f ${KEYDIR}/${KEYFILE} ]; then
        if [ ! -f ${KEYDIR} ]; then
            mkdir $KEYDIR
            chmod 700 $KEYDIR
        fi
        /usr/bin/smbclient $SMBSHARE -N -A /root/.sdcmoncred -c \
        "get  $MONPATH\\$KEYFILE $WORK/$KEYFILE.new" >> $TRANSLOG 2>&1
        rc=$?
        if [ "$rc" -eq "0" ]; then
            mv -f $KEYDIR/$KEYFILE $KEYDIR/$KEYFILE.bak
            chmod 640 $WORK/$KEYFILE.new
            mv -f $WORK/$KEYFILE.new $KEYDIR/$KEYFILE
            chown $SIDADM:sapsys $KEYDIR/$KEYFILE
            echo "Updated $KEYDIR/$KEYFILE" | tee -a $TRANSLOG
        fi
        chown $SIDADM:sapsys $KEYDIR
    fi
}

function UpdateSudoers { #update the /etc/sudoers file for additional sapsys sudo functionality
    if grep sapsys /etc/sudoers; then
        echo "sapsys entry exists already in /etc/sudoers file"
    else
        echo "will add sapsys entry in /etc/sudoers file"
        echo '%sapsys  ALL=NOPASSWD: /opt/cldscripts/sdcmon.sh, /sbin/reboot' >> /etc/sudoers
    fi
}

function UpdateCred2 { #update /root/.sdcmoncred2 file with contents
    local MONPATH="TDC_nonAbap\\SDC_startscript\\Linux"
    local SMBSHARE="//$MONSRV/sdc"
    local KEYFILE=".sdcmoncred2"
    local KEYDIR="/root"
    local TRANSLOG="$WORK/trans.log"
    local rc
    echo "$(date) : UpdateCred2" >> $TRANSLOG 2>&1
    if [ ! -f ${KEYDIR}/${KEYFILE} ]; then
        /usr/bin/smbclient $SMBSHARE -N -A /root/.sdcmoncred -c \
        "get  $MONPATH\\$KEYFILE $WORK/$KEYFILE.new" >> $TRANSLOG 2>&1
        rc=$?
        if [ "$rc" -eq "0" ]; then
            mv -f $KEYDIR/$KEYFILE $KEYDIR/$KEYFILE.bak
            chmod 640 $WORK/$KEYFILE.new
            mv -f $WORK/$KEYFILE.new $KEYDIR/$KEYFILE
            chmod 600 $KEYDIR/$KEYFILE
            chown tdcroot:root $KEYDIR/$KEYFILE
            echo "Updated $KEYDIR/$KEYFILE" | tee -a $TRANSLOG
        fi
    fi
}

function WhereAreWe {
    local MD_PROP="${WORK}/metaData.prop"
    local FENCE_TXT=$FENCE
    local BASH_MD_PROP="$WORK/md.sh"
    test -f $MD_PROP && rm -f  $MD_PROP
    unset http_proxy
    /usr/bin/wget --no-proxy --quiet -O $MD_PROP  http://f0vlm:1080/metaData.prop
    # assume we are in CDA if we cannot retreive metaData.prop
    if [ ! -s $MD_PROP ]; then
        rm -f $MD_PROP
        clusterName='CDA'
    else
        test -f  $FENCE_TXT && rm -f $FENCE_TXT
        /usr/bin/wget --no-proxy --quiet -O $FENCE_TXT  http://f0vlm:1080/fence.txt
        /usr/bin/dos2unix $MD_PROP
        /usr/bin/dos2unix $FENCE_TXT
        rm -f $BASH_MD_PROP
        cat $MD_PROP | sed 's/&/,/g' | sed -r 's/(.*)=(.*)/\1="\2"/g' > $BASH_MD_PROP
        source $BASH_MD_PROP
    fi

    unset SHOWROOM
    if [ "$clusterName" = "CDA" ]; then
        SHOWROOMFOLDER='CDA'
        MONSRV='sdcmon'
    elif [ "$clusterName" = "CLA" ]; then
        SHOWROOMFOLDER='Showrooms'
        clusterVersion=$(echo $clusterVersion | sed -r 's/([0-9]{4})(.*)/\1-\2/')
        SHOWROOM="_Internet-${clusterVersion}-longterm-clone"
        MONSRV='sdcmon-trans'
    else
        case "$vlName" in
        
		*Assembly\ Showroom*|*Pre-Showroom*)
            SHOWROOMFOLDER='Showrooms'
            clusterName="${order}-PRE-${clusterName}"
            if [ -z $monitoring ] ; then     
                SHOWROOM="_Showroom-${clusterVersion}-${clusterBuild}"
            elif [ $monitoring == "PRESR" ]; then
                SHOWROOM="_PreShowroom-${clusterVersion}-${clusterBuild}"
            else
                SHOWROOM="_Showroom-${clusterVersion}-${clusterBuild}"
            fi
            MONSRV='sdcmon-trans'
        ;;
		
        *Assembly*)
            SHOWROOMFOLDER='Assembly'
            clusterName="${order}-${clusterName}"
            SHOWROOM="_Assembly-${clusterVersion}-${clusterBuild}"
            MONSRV='sdcmon'
        ;;
		
        *CTA*)
            SHOWROOMFOLDER='CTA'
            MONSRV='sdcmon'
        ;;
    
	    *CSA*)
            SHOWROOMFOLDER='Showrooms'
            SHOWROOM="_Internet-${clusterVersion}-weekly-clone"
            MONSRV='sdcmon-trans'
        ;;
    
	    *PRIVATE*)
            SHOWROOMFOLDER='Showrooms'
            vlNameFull=$(echo $vlNameFull | sed 's/ /-/g')
            vlEdition=$(echo $vlEdition | sed 's/Edition //' | sed 's/ /-/g')
            clusterName="PRV-${order}_${vlNameFull}-${vlEdition}"
            unset SHOWROOM
            MONSRV='sdcmon-trans'
        ;;
		
        *)
            SHOWROOMFOLDER='Showrooms'
            clusterName="${order}-${clusterName}"
            if [ -z $monitoring ] ; then     #if parameter monitoring was initialized from metadata.prop
                SHOWROOM="_Showroom-${clusterVersion}-${clusterBuild}"
            elif [ $monitoring == "PRESR" ]; then
                SHOWROOM="_PreShowroom-${clusterVersion}-${clusterBuild}"
            else
                SHOWROOM="_Showroom-${clusterVersion}-${clusterBuild}"
            fi
            MONSRV='sdcmon-trans'
        ;;
    esac
    fi
}

function GetServerIPVersion {
    local OF=$OUTFILE
    local DEFDEVICE=$(ip route | grep default | awk '{print $5}')
    local OSTYPE=$(cat /etc/SuSE-release | head -1)
    local VERSION=$(cat /etc/SuSE-release | grep 'VERSION' | cut -d: -f2 | awk '{ print $3}')
    local LEVEL=$(cat /etc/SuSE-release | grep 'PATCHLEVEL' | cut -d: -f2 | awk '{ print $3}')
    local INTERNALIP=$(/sbin/ifconfig $DEFDEVICE | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
    echo 'OS-Version: '$OSTYPE ' Version '$VERSION ' PatchLevel '$LEVEL >> $OF
    echo 'Internal IP: '$INTERNALIP >> $OF
}

function IsSIDValid {
    local SEARCHSIDS=$SIDS
    if [ "$SID" == "SMP" ]; then
        return 0
    elif [ "$SID" == "SAPMZ" ]; then
        return 0
    else
        for i in $SEARCHSIDS; do
        if [ "$i" == "$SID" ]; then
            return 0
        fi
        done
        echo 'The System with SID '$SID' does not exist in this server.'
        return 1
    fi
}

function GetMemStats {
    local OF=$OUTFILE
    local SAFILE=$(ls -1tr /var/log/sa/sa* | grep -v sar | tail -2 | head -1)
    echo "Check RAM allocation:" >> $OF
    echo "-----------------------" >> $OF
    if ! /usr/bin/sar -r -f $SAFILE > /dev/nul 2>&1 ; then
        echo "ERROR: cannot read SA file" >> $OF
    else
        local PHYSMEM=$(/usr/bin/free -m | grep Mem: | awk '{print $2}')
        local FREEMEM=$(/usr/bin/sar -r  -f $SAFILE  | tail -1 | awk '{print $2}')
        FREEMEM=$(($FREEMEM / 1024))
        local USEDMEM=$(/usr/bin/sar -r  -f $SAFILE  | tail -1 | awk '{print $3}')
        USEDMEM=$(($USEDMEM/1024))
        echo 'Total physical memory (MB): '$PHYSMEM >> $OF
        echo 'Available physical memory (MB): '$FREEMEM >> $OF
    fi
}



####
#
# main
#
#####

# some global vars that are also used in fuctions
SCRIPTNAME=$(basename $0)
CLDSCRIPTS='/opt/cldscripts'
WORK="$CLDSCRIPTS/work"
FENCE="$WORK/fence.txt"
test -d $WORK || mkdir -p $WORK
HDBSTAT="$WORK/hdbstat"
ABAPSTAT="$WORK/abapstat"
WDSTAT="$WORK/wdstat"
SMPSTAT="$WORK/smpstat"
MZSTAT="$WORK/mzstat"
J2EESTAT="$WORK/j2eestat"
STATUS_OKAY='okay'
STATUS_NOT_OKAY='not_running'
STATUS_MAINT='down'
MODE="$1"
STATUS_SERVERDOWN='serverdown'
STATUS_REMOTE_MAINT='remote_down'
SERVERDOWN_MODE='serverdown_mode'
MAINTENANCE_MODE='maintenance'
REMOTE_MAINTENANCE_MODE='remote_maintenance'
PRODUCTIVE_MODE='productive'
# list of SIDs to filter out -- SDM, diagnostic agents, etc.
UNWANTED_SIDS='DAA|DAB|DAC|DAD|DA1|DA2|DA3'
SMPSERVERDIR='/sap/MobilePlatform3/Server'
SAPMZDIR='/opt/mz'

CheckMode

# Determine environment and set more global vars
WhereAreWe
UpdateCred2
UpdateSudoers

#update tdcroot cronjob if sdcmon is running 10min set it to run every 5 minutes
if [ -f /var/spool/cron/tabs/tdcroot ]; then
    sed -i 's/5-55\/10/*\/5/g' /var/spool/cron/tabs/tdcroot
fi

SID=$(echo $2 | tr '[:lower:]' '[:upper:]')
SIDS=$(grep ^SAPSYSTEMNAME /usr/sap/???/SYS/profile/DEFAULT.PFL 2>/dev/null | egrep -v "$UNWANTED_SIDS" | awk -F '=' '{print $2}' | tr -d '/ //')

if [ ! -z "$SID" ]; then
    IsSIDValid || exit
    SIDS=$SID
else
    if [ -z "$SIDS" ]; then
        if [ -f ${SMPSERVERDIR}/log/${HOSTNAME}-smp-server.log ]; then
            SIDS='SMP'
        elif [ -f ${SAPMZDIR}/log/platform.log ]; then
            SIDS='SAPMZ'
        else
            SIDS='---'
        fi
    fi
fi

if [ "$MODE" = "$MAINTENANCE_MODE" ]; then 
    echo " "
    echo " "
    echo " "
    echo " "
    echo " "
    echo " "
    echo "To keep track who set system to maintenance mode. Pls enter your user ID in format D1234567 :  "
    read MAINT_USER
    while [[ ! $MAINT_USER =~ [CcDdIi]{1}[0-9]{6,7} ]]
    do
        echo "Invalid username format. Pls enter your username again : "
        read MAINT_USER
    done
    echo "Enter ticket number and justification on setting system to maintenance mode : "
    read MAINT_REASON
fi

for i in $SIDS; do
    unset SYSTYPE
    if egrep -q 'system/type.*=.*ABAP' /usr/sap/${i}/SYS/profile/DEFAULT.PFL; then
        SYSTYPE=ABAP
    fi
    if egrep -q 'system/type.*=.*J2EE' /usr/sap/${i}/SYS/profile/DEFAULT.PFL; then
        SYSTYPE=J2EE
    fi
    if [ 0 -lt $(ls /usr/sap/${i}/SYS/profile/${i}_HDB* 2>/dev/null | wc -w) ]; then
        SYSTYPE=HANA
        UpdateKeyFile
    fi
    if [ 0 -lt $(ls /usr/sap/${i}/SYS/profile/${i}_W* 2>/dev/null | wc -w) ]; then
        SYSTYPE=WEBDISPATCHER
    fi
    if [ "${i}" = "SMP" ]; then 
        SYSTYPE=SMP
    fi
    if [ "${i}" = "SAPMZ" ]; then
        SYSTYPE=SAPMZ
    fi

    unset STATUS
    unset HANAWARNING
    if [ "$MODE" = "$MAINTENANCE_MODE" ]; then 
        STATUS=$STATUS_MAINT
        STATFILE="$CLDSCRIPTS/.${i}_${STATUS_MAINT}"
  #      [ -f $STATFILE ] || echo "$MAINT_USER - activity is $MAINT_REASON " > $STATFILE 
        if egrep -q 'maintenance' "$WORK/${clusterName}${SHOWROOM}_${HOSTNAME}_${i}_${STATUS_MAINT}.txt"; then
            echo "$i system is already set to maintenance. Cannot set it again to maintenance to preserve timestamp when it started to be on maintenance. Pls set it to down or productive before setting it to maintenance."
        else
            echo "$MAINT_USER - activity is $MAINT_REASON " > $STATFILE
            echo "$i system set to maintenance mode successfully by user $MAINT_USER"
        fi
   
     echo "Setting $MODE mode for $i"
    elif [ "$MODE" = "$REMOTE_MAINTENANCE_MODE" ]; then
        STATUS=$STATUS_REMOTE_MAINT
        echo "Setting $MODE mode for $i"
    elif [ "$MODE" = "$SERVERDOWN_MODE" ]; then
        STATUS=$STATUS_SERVERDOWN
        echo "Setting $MODE mode for $i"
    elif [ "$MODE" = "$PRODUCTIVE_MODE" ]; then
        echo "Setting $MODE mode for $i"
        rm -f ${CLDSCRIPTS}/.${i}_${STATUS_MAINT}
        GetStatus
    elif [ -f ${CLDSCRIPTS}/.${i}_${STATUS_MAINT} ]; then
        if egrep -q 'maintenance remotely' "$WORK/${clusterName}${SHOWROOM}_${HOSTNAME}_${i}_${STATUS_MAINT}.txt"; then
            STATUS=$STATUS_REMOTE_MAINT
        elif egrep -q 'maintenance' "$WORK/${clusterName}${SHOWROOM}_${HOSTNAME}_${i}_${STATUS_MAINT}.txt"; then
            STATUS=$STATUS_MAINT
        else
            STATUS=$STATUS_SERVERDOWN
        fi
    else
            GetStatus
    fi

    if [ "$STATUS" = "$STATUS_SERVERDOWN" ]; then
        STATFILE="$CLDSCRIPTS/.${i}_${STATUS_MAINT}"
        OUTFILE="$WORK/${clusterName}${SHOWROOM}_${HOSTNAME}_${i}_${STATUS_MAINT}.txt"
    elif [ "$STATUS" = "$STATUS_REMOTE_MAINT" ]; then
        STATFILE="$CLDSCRIPTS/.${i}_${STATUS_MAINT}"
        OUTFILE="$WORK/${clusterName}${SHOWROOM}_${HOSTNAME}_${i}_${STATUS_MAINT}.txt"
    else
        STATFILE="$CLDSCRIPTS/.${i}_${STATUS}"
        OUTFILE="$WORK/${clusterName}${SHOWROOM}_${HOSTNAME}_${i}_${STATUS}.txt"
    fi
    
    if [ "$STATUS" != "$STATUS_OKAY" ]; then
        test -f $STATFILE || touch $STATFILE
        DOWNTIME=$(stat -c %y $STATFILE  | awk -F '.' '{print $1}')
    else
        rm -f $CLDSCRIPTS/.${i}_*
    fi

    date > $OUTFILE
    if [ "$STATUS" = "$STATUS_MAINT" ]; then
        echo "Instance $i on $HOSTNAME is in maintenance" >> $OUTFILE
        echo "since $DOWNTIME" >>  $OUTFILE
        test -f $STATFILE && cat $STATFILE >> $OUTFILE
     elif [ "$STATUS" = "$STATUS_REMOTE_MAINT" ]; then
        echo "Instance $i on $HOSTNAME is set in maintenance remotely. Please check ABAP monitor for maintenance info" >> $OUTFILE
        echo "since $DOWNTIME" >>  $OUTFILE 
    elif [ "$STATUS" = "$STATUS_SERVERDOWN" ]; then
        echo "Instance $i on $HOSTNAME has been stopped" >> $OUTFILE
        echo "since $DOWNTIME" >>  $OUTFILE
    elif [ "$STATUS" = "$STATUS_NOT_OKAY" ]; then
        echo "Instance $i on $HOSTNAME is not running" >> $OUTFILE
        echo "since $DOWNTIME" >>  $OUTFILE
        echo >> $OUTFILE
        if [ "$SYSTYPE" = "ABAP" ]; then
            test -f $ABAPSTAT && cat $ABAPSTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "J2EE" ]; then
            test -f $J2EESTAT && cat $J2EESTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "WEBDISPATCHER" ]; then
            test -f $WDSTAT && cat $WDSTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "SMP" ]; then
            test -f $SMPSTAT && cat $SMPSTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "SAMPZ" ]; then
            test -f $MZSTAT && cat $MZSTAT >> $OUTFILE
        fi
    else
        echo "Instance $i on $HOSTNAME is $STATUS $HANAWARNING" >> $OUTFILE
        echo >> $OUTFILE
        if [ "$SYSTYPE" = "ABAP" ]; then
            test -f $ABAPSTAT && cat $ABAPSTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "J2EE" ]; then
            test -f $J2EESTAT && cat $J2EESTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "WEBDISPATCHER" ]; then
            test -f $WDSTAT && cat $WDSTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "HANA" ]; then
            test -f $HDBSTAT && cat $HDBSTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "SMP" ]; then
            test -f $SMPSTAT && cat $SMPSTAT >> $OUTFILE
        elif [ "$SYSTYPE" = "SAMPZ" ]; then
            test -f $MZSTAT && cat $MZSTAT >> $OUTFILE
        fi
        echo >> $OUTFILE
        echo "DOWNTIME HISTORY:" >> $OUTFILE
        uptime >>  $OUTFILE
    fi
    echo >> $OUTFILE
    echo "Check available disk space:" >> $OUTFILE
    echo "------------------------------" >> $OUTFILE
    df -B G -P >> $OUTFILE 2>&1
    echo  >> $OUTFILE
    GetServerIPVersion
    echo  >> $OUTFILE
    GetMemStats
    echo >> $OUTFILE
    test -f $FENCE && cat $FENCE >> $OUTFILE
    echo >> $OUTFILE
    echo "Ordernumber in ECM: $order" >> $OUTFILE
    echo >> $OUTFILE
    ### make sure this ist the last log entry!
    echo "time reference (UTC):" >> $OUTFILE
    date '+%s' >>  $OUTFILE
    MountAndTransfer
    MountAndTransferCLD41
done
#CheckForEmergencyUpdate
#CheckForUpdate



